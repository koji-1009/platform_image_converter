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

/// GdkPixbuf encoder type name for each [OutputFormat]. GdkPixbuf names the
/// HEIF/HEIC handler `heif`.
String _typeName(OutputFormat format) => switch (format) {
  OutputFormat.jpeg => 'jpeg',
  OutputFormat.png => 'png',
  OutputFormat.webp => 'webp',
  OutputFormat.heic => 'heif',
};

/// Linux image converter using GdkPixbuf from the GLib/GTK stack.
///
/// Decodes input with an in-memory `GdkPixbufLoader`, resizes with
/// `gdk_pixbuf_scale_simple`, and re-encodes with `gdk_pixbuf_save_to_bufferv`.
///
/// **Output formats:**
/// - JPEG and PNG: always available (built-in GdkPixbuf loaders).
/// - WebP and HEIC: available only where a *writable* loader module is
///   installed (e.g. `webp-pixbuf-loader`, or the libheif GdkPixbuf loader),
///   which varies by distribution. When none is present the backend throws
///   [UnsupportedFormatException] with reason
///   [UnsupportedFormatReason.codecUnavailable] rather than failing hard.
final class ImageConverterLinux implements ImageConverterPlatform {
  const ImageConverterLinux();

  @override
  Uint8List convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
    ExifOrientationPolicy orientation = ExifOrientationPolicy.apply,
  }) {
    final type = _typeName(format);

    // Reject an output format with no *writable* loader before touching the
    // image. JPEG and PNG are built in; WebP and HEIF are optional loader
    // modules whose presence — and save support — varies by distribution, so a
    // missing one is a recoverable codecUnavailable, not a hard error. This
    // also mirrors the other backends, which reject unsupported output up front.
    if (!_hasWritableLoader(type)) {
      throw UnsupportedFormatException(
        format,
        UnsupportedFormatReason.codecUnavailable,
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

      final width = gdk_pixbuf_get_width(decoded);
      final height = gdk_pixbuf_get_height(decoded);
      final (newWidth, newHeight) = resizeMode.calculateSize(width, height);

      // Scale only when the size changes (high-quality resampling). The scaled
      // pixbuf is a new reference we own; the decoded one stays owned by loader.
      var pixbuf = decoded;
      if (newWidth != width || newHeight != height) {
        pixbuf = gdk_pixbuf_scale_simple(
          decoded,
          newWidth,
          newHeight,
          GdkInterpType.GDK_INTERP_HYPER,
        )..unrefBy(arena);
        if (pixbuf == nullptr) {
          throw const ImageConversionException('Failed to resize image.');
        }
      }

      // Encode to an in-memory buffer.
      final (keys, values) = _encodeOptions(arena, format, quality);
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

  /// Whether GdkPixbuf has a *writable* loader for the format's [type] name
  /// (`jpeg`/`png`/`webp`/`heif`). JPEG/PNG are built in; WebP/HEIF are optional
  /// modules whose presence varies by distribution. Walks the format list only
  /// until the requested type is found, freeing each name and the list itself
  /// even if a lookup throws.
  bool _hasWritableLoader(String type) {
    final head = gdk_pixbuf_get_formats();
    try {
      for (var node = head; node != nullptr; node = node.ref.next) {
        final fmt = node.ref.data;
        if (fmt == nullptr || gdk_pixbuf_format_is_writable(fmt.cast()) == 0) {
          continue;
        }
        final namePtr = gdk_pixbuf_format_get_name(fmt.cast());
        if (namePtr == nullptr) continue;
        try {
          if (namePtr.cast<Utf8>().toDartString() == type) return true;
        } finally {
          g_free(namePtr.cast());
        }
      }
      return false;
    } finally {
      if (head != nullptr) g_slist_free(head);
    }
  }

  /// Builds the NULL-terminated GdkPixbuf save option arrays. Lossy formats
  /// (JPEG/WebP/HEIC) take a `quality` (0-100); PNG is lossless and takes no
  /// options, so `gdk_pixbuf_save_to_bufferv` receives NULL arrays.
  (Pointer<Pointer<Char>>, Pointer<Pointer<Char>>) _encodeOptions(
    Arena arena,
    OutputFormat format,
    int quality,
  ) {
    if (format == OutputFormat.png) {
      return (nullptr, nullptr);
    }
    final keys = arena<Pointer<Char>>(2);
    keys[0] = 'quality'.toNativeUtf8(allocator: arena).cast();
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
