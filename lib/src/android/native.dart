import 'dart:typed_data';

import 'package:jni/jni.dart';
import 'package:platform_image_converter/src/android/bindings.g.dart';
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
    JByteArray? inputJBytes;
    Bitmap? originalBitmap;
    Bitmap? scaledBitmap;
    Bitmap? bitmapToCompress;
    Bitmap$CompressFormat? compressFormat;
    ByteArrayOutputStream? outputStream;
    JByteArray? outputJBytes;
    try {
      inputJBytes = JByteArray.from(inputData);
      originalBitmap = BitmapFactory.decodeByteArray(
        inputJBytes,
        0,
        inputData.length,
      );
      if (originalBitmap == null) {
        throw Exception('Failed to decode image. Invalid image data.');
      }

      switch (resizeMode) {
        case OriginalResizeMode():
          bitmapToCompress = originalBitmap;
        case ExactResizeMode(width: final w, height: final h):
          scaledBitmap = Bitmap.createScaledBitmap(
            originalBitmap,
            w,
            h,
            true, // filter
          );
          bitmapToCompress = scaledBitmap;
        case FitResizeMode(:final width, :final height):
          final originalWidth = originalBitmap.getWidth();
          final originalHeight = originalBitmap.getHeight();

          double newWidth;
          double newHeight;

          if (width != null && height != null) {
            if (originalWidth <= width && originalHeight <= height) {
              bitmapToCompress = originalBitmap;
              break;
            }
            final aspectRatio = originalWidth / originalHeight;
            newWidth = width.toDouble();
            newHeight = newWidth / aspectRatio;
            if (newHeight > height) {
              newHeight = height.toDouble();
              newWidth = newHeight * aspectRatio;
            }
          } else if (width != null) {
            if (originalWidth <= width) {
              bitmapToCompress = originalBitmap;
              break;
            }
            newWidth = width.toDouble();
            final aspectRatio = originalWidth / originalHeight;
            newHeight = newWidth / aspectRatio;
          } else if (height != null) {
            if (originalHeight <= height) {
              bitmapToCompress = originalBitmap;
              break;
            }
            newHeight = height.toDouble();
            final aspectRatio = originalWidth / originalHeight;
            newWidth = newHeight * aspectRatio;
          } else {
            // This case should not be reachable due to the assertion
            // in the FitResizeMode constructor.
            bitmapToCompress = originalBitmap;
            break;
          }

          scaledBitmap = Bitmap.createScaledBitmap(
            originalBitmap,
            newWidth.round(),
            newHeight.round(),
            true, // filter
          );
          bitmapToCompress = scaledBitmap;
      }

      if (bitmapToCompress == null) {
        // This should not happen if originalBitmap is valid
        throw Exception('Bitmap could not be prepared for compression.');
      }

      compressFormat = switch (format) {
        OutputFormat.jpeg => Bitmap$CompressFormat.JPEG,
        OutputFormat.png => Bitmap$CompressFormat.PNG,
        // TODO: WebP is deprecated since Android 10, consider using WebP_LOSSY or WebP_LOSSLESS
        OutputFormat.webp => Bitmap$CompressFormat.WEBP,
        OutputFormat.heic => throw UnsupportedError(
          'HEIC output format is not supported on Android.',
        ),
      };

      outputStream = ByteArrayOutputStream();
      final success = bitmapToCompress.compress(
        compressFormat,
        quality,
        outputStream,
      );
      if (!success) {
        throw Exception('Failed to compress bitmap.');
      }

      outputJBytes = outputStream.toByteArray();
      if (outputJBytes == null) {
        throw Exception('Failed to get byte array from output stream.');
      }

      return Uint8List.fromList(outputJBytes.toList());
    } finally {
      inputJBytes?.release();
      originalBitmap?.recycle();
      originalBitmap?.release();
      scaledBitmap?.recycle();
      scaledBitmap?.release();
      compressFormat?.release();
      outputStream?.release();
      outputJBytes?.release();
    }
  }
}
