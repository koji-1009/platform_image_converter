import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:platform_image_converter/src/image_conversion_exception.dart';
import 'package:platform_image_converter/src/image_converter_platform_interface.dart';
import 'package:platform_image_converter/src/linux/gdk_pixbuf.dart';
import 'package:platform_image_converter/src/output_format.dart';
import 'package:platform_image_converter/src/output_resize.dart';

extension on Pointer<Void> {
  /// Drops one GObject reference with `g_object_unref` when [arena] is released,
  /// mirroring the other FFI backends' `releasedBy`. Skips `nullptr`.
  void unrefBy(Arena arena) {
    if (this != nullptr) arena.onReleaseAll(() => gObjectUnref(this));
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
  }) {
    final type = _typeName(format);

    // Reject an output format with no *writable* loader before touching the
    // image. JPEG and PNG are built in; WebP and HEIF are optional loader
    // modules whose presence — and save support — varies by distribution, so a
    // missing one is a recoverable codecUnavailable, not a hard error. This
    // also mirrors the other backends, which reject unsupported output up front.
    if (!_writableTypes().contains(type)) {
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
      final loader = gdkPixbufLoaderNew()..unrefBy(arena);
      if (loader == nullptr) {
        throw const ImageConversionException('Failed to create image loader.');
      }
      final inputPtr = arena<Uint8>(inputData.length);
      inputPtr.asTypedList(inputData.length).setAll(0, inputData);
      // close() must run even if write() succeeds; `||` short-circuits so close
      // is skipped when write already failed (and set *error).
      if (gdkPixbufLoaderWrite(loader, inputPtr, inputData.length, errorOut) ==
              0 ||
          gdkPixbufLoaderClose(loader, errorOut) == 0) {
        throw ImageDecodingException(
          _takeErrorMessage(errorOut) ?? 'Invalid image data.',
        );
      }
      // Borrowed reference owned by the loader; valid until the loader is unref.
      final decoded = gdkPixbufLoaderGetPixbuf(loader);
      if (decoded == nullptr) {
        throw const ImageDecodingException();
      }

      final width = gdkPixbufGetWidth(decoded);
      final height = gdkPixbufGetHeight(decoded);
      final (newWidth, newHeight) = resizeMode.calculateSize(width, height);

      // Scale only when the size changes (high-quality resampling). The scaled
      // pixbuf is a new reference we own; the decoded one stays owned by loader.
      var pixbuf = decoded;
      if (newWidth != width || newHeight != height) {
        pixbuf = gdkPixbufScaleSimple(
          decoded,
          newWidth,
          newHeight,
          gdkInterpHyper,
        )..unrefBy(arena);
        if (pixbuf == nullptr) {
          throw const ImageConversionException('Failed to resize image.');
        }
      }

      // Encode to an in-memory buffer.
      final (keys, values) = _encodeOptions(arena, format, quality);
      final bufferOut = arena<Pointer<Uint8>>();
      final sizeOut = arena<Size>();
      if (gdkPixbufSaveToBufferv(
            pixbuf,
            bufferOut,
            sizeOut,
            type.toNativeUtf8(allocator: arena),
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
        return Uint8List.fromList(buffer.asTypedList(sizeOut.value));
      } finally {
        gFree(buffer.cast());
      }
    });
  }

  /// The set of GdkPixbuf type names that have a *writable* loader installed.
  Set<String> _writableTypes() {
    final writable = <String>{};
    final head = gdkPixbufGetFormats();
    var node = head;
    while (node != nullptr) {
      final fmt = node.ref.data;
      if (fmt != nullptr && gdkPixbufFormatIsWritable(fmt) != 0) {
        final namePtr = gdkPixbufFormatGetName(fmt);
        if (namePtr != nullptr) {
          writable.add(namePtr.toDartString());
          gFree(namePtr.cast());
        }
      }
      node = node.ref.next;
    }
    if (head != nullptr) gSListFree(head);
    return writable;
  }

  /// Builds the NULL-terminated GdkPixbuf save option arrays. Lossy formats
  /// (JPEG/WebP/HEIC) take a `quality` (0-100); PNG is lossless and takes no
  /// options, so `gdk_pixbuf_save_to_bufferv` receives NULL arrays.
  (Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>) _encodeOptions(
    Arena arena,
    OutputFormat format,
    int quality,
  ) {
    if (format == OutputFormat.png) {
      return (nullptr, nullptr);
    }
    final keys = arena<Pointer<Utf8>>(2);
    keys[0] = 'quality'.toNativeUtf8(allocator: arena);
    keys[1] = nullptr;
    final values = arena<Pointer<Utf8>>(2);
    values[0] = '$quality'.toNativeUtf8(allocator: arena);
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
    final message = messagePtr == nullptr ? null : messagePtr.toDartString();
    gErrorFree(error);
    errorOut.value = nullptr;
    return message;
  }
}
