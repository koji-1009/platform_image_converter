import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:platform_image_converter/src/exif_orientation_policy.dart';
import 'package:platform_image_converter/src/image_conversion_exception.dart';
import 'package:platform_image_converter/src/image_converter_platform_interface.dart';
import 'package:platform_image_converter/src/linux/bindings.g.dart';
import 'package:platform_image_converter/src/output_format.dart';
import 'package:platform_image_converter/src/output_resize.dart';

// Narrowed to `Pointer<Opaque>` (the generated GdkPixbuf/GdkPixbufLoader handle
// types extend `Opaque`) so this only applies to the owned object handles —
// accidentally calling `..unrefBy` on an arena out-param (e.g. the GError**,
// buffer, or size slots, which are not `Pointer<Opaque>`) is a compile error.
extension on Pointer<Opaque> {
  /// Drops one GObject reference with `g_object_unref` when [arena] is released,
  /// mirroring the other FFI backends' `releasedBy`. Skips `nullptr`.
  void unrefBy(Arena arena) {
    if (this != nullptr) arena.onReleaseAll(() => g_object_unref(cast()));
  }
}

/// GdkPixbuf encoder type name for each [OutputFormat]. HEIC output is looked
/// up as a `heif` loader; the libheif loader (`heif/avif`) and the glycin one
/// (`heic`) only decode, so neither provides it.
String _typeName(OutputFormat format) => switch (format) {
  .jpeg => 'jpeg',
  .png => 'png',
  .webp => 'webp',
  .heic => 'heif',
};

/// Linux image converter using GdkPixbuf from the GLib/GTK stack.
///
/// Decodes input with an in-memory `GdkPixbufLoader`, resizes with
/// `gdk_pixbuf_scale_simple`, and re-encodes with `gdk_pixbuf_save_to_bufferv`.
///
/// **Output formats:**
/// - JPEG and PNG: always available (built-in GdkPixbuf loaders).
/// - WebP and HEIC: available only where a *writable* loader module is
///   installed (e.g. `webp-pixbuf-loader`; the libheif GdkPixbuf loader only
///   decodes), which varies by distribution. When none is present the backend throws
///   [UnsupportedFormatException] with reason
///   [UnsupportedFormatReason.codecUnavailable] rather than failing hard.
///
/// **Quality:** passed to the encoder only when its loader reports support for
/// the `quality` save option (`gdk_pixbuf_format_is_save_option_supported`).
/// Otherwise, as for PNG, it has no effect on the output.
///
/// **Alpha:** JPEG has no alpha channel, so for JPEG output a source with
/// alpha is composited onto opaque black (transparent pixels become black).
final class ImageConverterLinux implements ImageConverterPlatform {
  const ImageConverterLinux();

  @override
  Uint8List convert({
    required Uint8List inputData,
    OutputFormat format = .jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
    ExifOrientationPolicy orientation = .apply,
  }) {
    final type = _typeName(format);

    // Reject an output format with no *writable* loader before touching the
    // image. JPEG and PNG are built in; WebP and HEIF are optional loader
    // modules whose presence — and save support — varies by distribution, so a
    // missing one is a recoverable codecUnavailable, not a hard error. This
    // also mirrors the other backends, which reject unsupported output up front.
    final writableFormat = _findWritableFormat(type);
    if (writableFormat == nullptr) {
      throw UnsupportedFormatException(
        format,
        .codecUnavailable,
        '${format.name} output is unavailable on this system: no writable '
        'GdkPixbuf loader for "$type" is installed.',
      );
    }

    return using((arena) {
      final errorOut = arena<Pointer<GError>>();

      // Decode the input bytes through an in-memory loader.
      final loader = gdk_pixbuf_loader_new()..unrefBy(arena);
      if (loader == nullptr) {
        throw const ImageConversionException('Failed to create image loader.');
      }
      final inputPtr = arena<Uint8>(inputData.length);
      inputPtr.asTypedList(inputData.length).setAll(0, inputData);
      // close() must run even if write() succeeds; `||` short-circuits so close
      // is skipped when write already failed (and set *error).
      if (gdk_pixbuf_loader_write(
                loader,
                inputPtr.cast(),
                inputData.length,
                errorOut,
              ) ==
              0 ||
          gdk_pixbuf_loader_close(loader, errorOut) == 0) {
        throw ImageDecodingException(
          _takeErrorMessage(errorOut) ?? 'Invalid image data.',
        );
      }
      // Borrowed reference owned by the loader; valid until the loader is unref.
      final decoded = gdk_pixbuf_loader_get_pixbuf(loader);
      if (decoded == nullptr) {
        throw const ImageDecodingException();
      }

      // EXIF orientation: the JPEG/TIFF loaders attach the raw orientation tag
      // as a GdkPixbuf "orientation" option but do NOT rotate the pixels.
      // `gdk_pixbuf_apply_embedded_orientation` bakes that tag into a new,
      // upright pixbuf (transfer-full — we own it, so unref it via the arena);
      // when no tag is present it just returns an unmodified copy. Done before
      // measuring so 90/270 rotations swap width/height and the resize is
      // evaluated against the oriented (display) dimensions, matching the other
      // backends. With `ignore` we skip it and keep the raw buffer layout.
      var oriented = decoded;
      if (orientation == .apply) {
        oriented = gdk_pixbuf_apply_embedded_orientation(decoded)
          ..unrefBy(arena);
        if (oriented == nullptr) {
          throw const ImageConversionException(
            'Failed to apply EXIF orientation.',
          );
        }
      }

      final width = gdk_pixbuf_get_width(oriented);
      final height = gdk_pixbuf_get_height(oriented);
      final (newWidth, newHeight) = resizeMode.calculateSize(width, height);

      // JPEG has no alpha channel, and the JPEG encoder may reject an RGBA
      // pixbuf, so JPEG output from a source with alpha is flattened onto
      // opaque black (resizing in the same pass). Otherwise scale only when the
      // size changes (high-quality resampling). Any new pixbuf is a reference
      // we own; the oriented one is either owned by the loader (orientation
      // ignored) or by the arena (orientation applied).
      final Pointer<GdkPixbuf> pixbuf;
      if (format == .jpeg && gdk_pixbuf_get_has_alpha(oriented) != 0) {
        pixbuf = _flattenAlpha(
          arena,
          oriented,
          width,
          height,
          newWidth,
          newHeight,
        );
      } else if (newWidth != width || newHeight != height) {
        pixbuf = gdk_pixbuf_scale_simple(
          oriented,
          newWidth,
          newHeight,
          GdkInterpType.GDK_INTERP_HYPER,
        )..unrefBy(arena);
        if (pixbuf == nullptr) {
          throw const ImageConversionException('Failed to resize image.');
        }
      } else {
        pixbuf = oriented;
      }

      // Encode to an in-memory buffer.
      final (keys, values) = _encodeOptions(
        arena,
        format,
        quality,
        writableFormat,
      );
      final bufferOut = arena<Pointer<Char>>();
      final sizeOut = arena<UnsignedLong>();
      if (gdk_pixbuf_save_to_bufferv(
            pixbuf,
            bufferOut,
            sizeOut,
            type.toNativeUtf8(allocator: arena).cast(),
            keys,
            values,
            errorOut,
          ) ==
          0) {
        throw ImageEncodingException(format, _takeErrorMessage(errorOut));
      }
      final buffer = bufferOut.value;
      if (buffer == nullptr) {
        throw ImageEncodingException(format, 'Encoder returned no data.');
      }
      try {
        return Uint8List.fromList(
          buffer.cast<Uint8>().asTypedList(sizeOut.value),
        );
      } finally {
        g_free(buffer.cast());
      }
    });
  }

  /// Composites [src] (which has an alpha channel, [srcWidth]x[srcHeight]) over
  /// opaque black into a new [destWidth]x[destHeight] 8-bit RGB pixbuf without
  /// alpha, owned by [arena]. Scales with `GDK_INTERP_HYPER` when the size
  /// changes, matching `gdk_pixbuf_scale_simple` in the non-flattening path.
  Pointer<GdkPixbuf> _flattenAlpha(
    Arena arena,
    Pointer<GdkPixbuf> src,
    int srcWidth,
    int srcHeight,
    int destWidth,
    int destHeight,
  ) {
    final dest = gdk_pixbuf_new(
      GdkColorspace.GDK_COLORSPACE_RGB,
      0,
      8,
      destWidth,
      destHeight,
    )..unrefBy(arena);
    if (dest == nullptr) {
      throw const ImageConversionException('Failed to allocate image buffer.');
    }
    // gdk_pixbuf_new leaves the pixel memory uninitialized. The fill value is
    // RGBA; its alpha byte is ignored for a pixbuf without alpha.
    gdk_pixbuf_fill(dest, 0x000000ff);
    final resize = destWidth != srcWidth || destHeight != srcHeight;
    gdk_pixbuf_composite(
      src,
      dest,
      0,
      0,
      destWidth,
      destHeight,
      0,
      0,
      destWidth / srcWidth,
      destHeight / srcHeight,
      // At scale 1, NEAREST copies each source pixel as is.
      resize
          ? GdkInterpType.GDK_INTERP_HYPER
          : GdkInterpType.GDK_INTERP_NEAREST,
      255,
    );
    return dest;
  }

  /// The *writable* GdkPixbuf format whose name is [type]
  /// (`jpeg`/`png`/`webp`/`heif`), or `nullptr` if none is installed.
  /// JPEG/PNG are built in; WebP/HEIF are optional modules whose presence
  /// varies by distribution. The returned format is owned by GdkPixbuf and
  /// outlives the list. Walks the format list only until the requested type is
  /// found, freeing each name and the list itself even if a lookup throws.
  Pointer<GdkPixbufFormat> _findWritableFormat(String type) {
    final head = gdk_pixbuf_get_formats();
    try {
      for (var node = head; node != nullptr; node = node.ref.next) {
        final fmt = node.ref.data.cast<GdkPixbufFormat>();
        if (fmt == nullptr || gdk_pixbuf_format_is_writable(fmt) == 0) {
          continue;
        }
        final namePtr = gdk_pixbuf_format_get_name(fmt);
        if (namePtr == nullptr) continue;
        try {
          if (namePtr.cast<Utf8>().toDartString() == type) return fmt;
        } finally {
          g_free(namePtr.cast());
        }
      }
      return nullptr;
    } finally {
      if (head != nullptr) g_slist_free(head);
    }
  }

  /// Builds the NULL-terminated GdkPixbuf save option arrays. Lossy formats
  /// (JPEG/WebP/HEIC) take a `quality` (0-100) when [writableFormat]'s loader
  /// supports that option; PNG is lossless and takes no options. Without
  /// options `gdk_pixbuf_save_to_bufferv` receives NULL arrays.
  (Pointer<Pointer<Char>>, Pointer<Pointer<Char>>) _encodeOptions(
    Arena arena,
    OutputFormat format,
    int quality,
    Pointer<GdkPixbufFormat> writableFormat,
  ) {
    // Exhaustive over OutputFormat so a future format forces a decision here
    // instead of silently receiving a `quality` option it may not accept.
    switch (format) {
      case .png:
        return (nullptr, nullptr);
      case .jpeg || .webp || .heic:
        break;
    }
    final qualityKey = 'quality'.toNativeUtf8(allocator: arena).cast<Char>();
    if (gdk_pixbuf_format_is_save_option_supported(
          writableFormat,
          qualityKey,
        ) ==
        0) {
      return (nullptr, nullptr);
    }
    final keys = arena<Pointer<Char>>(2);
    keys[0] = qualityKey;
    keys[1] = nullptr;
    final values = arena<Pointer<Char>>(2);
    values[0] = '$quality'.toNativeUtf8(allocator: arena).cast();
    values[1] = nullptr;
    return (keys, values);
  }

  /// Reads and consumes the message from a `GError **` out-param: returns the
  /// message (if any), frees the `GError`, and resets the slot to `nullptr` so
  /// it can be reused for a later call.
  String? _takeErrorMessage(Pointer<Pointer<GError>> errorOut) {
    final error = errorOut.value;
    if (error == nullptr) return null;
    final messagePtr = error.ref.message;
    final message = messagePtr == nullptr
        ? null
        : messagePtr.cast<Utf8>().toDartString();
    g_error_free(error);
    errorOut.value = nullptr;
    return message;
  }
}
