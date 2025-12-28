import 'dart:typed_data';

import 'package:jni/jni.dart';
import 'package:platform_image_converter/src/android/bindings.g.dart';
import 'package:platform_image_converter/src/image_conversion_exception.dart';
import 'package:platform_image_converter/src/image_converter_platform_interface.dart';
import 'package:platform_image_converter/src/output_format.dart';
import 'package:platform_image_converter/src/output_resize.dart';

/// Android image converter using BitmapFactory and Bitmap compression.
///
/// Implements image conversion for Android 9+ (API level 28+) platforms using
/// BitmapFactory for decoding and Bitmap.compress for encoding via JNI.\n///
/// **Features:**
/// - Supports JPEG, PNG, WebP, GIF, BMP input formats
/// - Can read HEIC files (Android 9+)
/// - Cannot write HEIC (throws UnsupportedError)
/// - Efficient memory usage with ByteArrayOutputStream
///
/// **API Stack:**
/// - `BitmapFactory.decodeByteArray`: Auto-detect and decode input
/// - `Bitmap.createScaledBitmap`: Resize image with filtering
/// - `Bitmap.compress`: Encode to target format with quality control
/// - `ByteArrayOutputStream`: Memory-based output buffer
///
/// **Limitations:**
/// - HEIC output not supported (use JPEG or PNG instead)
/// - Requires Android 9+ for full format support
///
/// **Performance:**
/// - Native image decoding via BitmapFactory
/// - Efficient compression with quality adjustment
final class ImageConverterAndroid implements ImageConverterPlatform {
  const ImageConverterAndroid();

  @override
  Future<Uint8List> convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
  }) async {
    return using((arena) {
      final inputJBytes = JByteArray.from(inputData)..releasedBy(arena);
      final originalBitmap = BitmapFactory.decodeByteArray(
        inputJBytes,
        0,
        inputData.length,
      )?..releasedBy(arena);
      if (originalBitmap == null) {
        throw const ImageDecodingException('Invalid image data.');
      }

      final originalWidth = originalBitmap.getWidth();
      final originalHeight = originalBitmap.getHeight();
      final (newWidth, newHeight) = resizeMode.calculateSize(
        originalWidth,
        originalHeight,
      );

      final Bitmap? bitmapToCompress;
      if (newWidth == originalWidth && newHeight == originalHeight) {
        bitmapToCompress = originalBitmap;
      } else {
        bitmapToCompress = Bitmap.createScaledBitmap(
          originalBitmap,
          newWidth,
          newHeight,
          true, // filter
        )?..releasedBy(arena);
      }
      if (bitmapToCompress == null) {
        throw const ImageConversionException(
          'Bitmap could not be prepared for compression.',
        );
      }

      final compressFormat = switch (format) {
        OutputFormat.jpeg => Bitmap$CompressFormat.JPEG,
        OutputFormat.png => Bitmap$CompressFormat.PNG,
        // TODO: WebP is deprecated since Android 10, consider using WebP_LOSSY or WebP_LOSSLESS
        OutputFormat.webp => Bitmap$CompressFormat.WEBP,
        OutputFormat.heic => throw UnsupportedError(
          'HEIC output format is not supported on Android.',
        ),
      }..releasedBy(arena);

      final outputStream = ByteArrayOutputStream()..releasedBy(arena);
      final success = bitmapToCompress.compress(
        compressFormat,
        quality,
        outputStream,
      );
      if (!success) {
        throw ImageEncodingException(format, 'Failed to compress bitmap.');
      }

      final outputJBytes = outputStream.toByteArray()?..releasedBy(arena);
      if (outputJBytes == null) {
        throw ImageEncodingException(
          format,
          'Failed to get byte array from output stream.',
        );
      }

      return Uint8List.fromList(outputJBytes.toList());
    });
  }
}
