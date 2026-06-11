import 'dart:typed_data';

import 'package:jni/jni.dart';
import 'package:platform_image_converter/src/android/bindings.g.dart';
import 'package:platform_image_converter/src/exif_orientation_policy.dart';
import 'package:platform_image_converter/src/image_conversion_exception.dart';
import 'package:platform_image_converter/src/image_converter_platform_interface.dart';
import 'package:platform_image_converter/src/output_format.dart';
import 'package:platform_image_converter/src/output_resize.dart';

/// Android image converter using BitmapFactory and Bitmap compression.
///
/// Implements image conversion on Android using
/// BitmapFactory for decoding and Bitmap.compress for encoding via JNI.
///
/// **Features:**
/// - Supports JPEG, PNG, WebP, GIF, BMP input formats
/// - Can read HEIC files (Android 9+)
/// - Cannot write HEIC (throws UnsupportedFormatException)
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
  Uint8List convert({
    required Uint8List inputData,
    OutputFormat format = .jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
    ExifOrientationPolicy orientation = .apply,
  }) {
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

      // BitmapFactory ignores the EXIF orientation, so bake it into the pixels
      // before measuring/resizing (a no-op for ORIENTATION_NORMAL or `ignore`).
      // Resizing then operates on the oriented (display) dimensions.
      final orientedBitmap = orientation == .apply
          ? _applyOrientation(arena, inputJBytes, originalBitmap)
          : originalBitmap;

      final originalWidth = orientedBitmap.getWidth();
      final originalHeight = orientedBitmap.getHeight();
      final (newWidth, newHeight) = resizeMode.calculateSize(
        originalWidth,
        originalHeight,
      );

      final Bitmap? bitmapToCompress;
      if (newWidth == originalWidth && newHeight == originalHeight) {
        bitmapToCompress = orientedBitmap;
      } else {
        bitmapToCompress = Bitmap.createScaledBitmap(
          orientedBitmap,
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
        .jpeg => Bitmap$CompressFormat.JPEG,
        .png => Bitmap$CompressFormat.PNG,
        // TODO: WebP is deprecated since Android 10, consider using WebP_LOSSY or WebP_LOSSLESS
        .webp => Bitmap$CompressFormat.WEBP,
        .heic => throw UnsupportedFormatException(
          format,
          .platformUnsupported,
          'HEIC output is not supported on Android.',
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

      return Uint8List.fromList(outputJBytes.getRange(0, outputJBytes.length));
    });
  }

  /// Reads the EXIF orientation from [inputJBytes] and, when it is not the
  /// normal orientation, returns a new [Bitmap] with that rotation/mirror baked
  /// into the pixels (via a [Matrix]); otherwise returns [src] unchanged.
  ///
  /// [ExifInterface] reads orientation from a stream over the original bytes;
  /// formats without EXIF (or upright images) report `ORIENTATION_NORMAL`, so
  /// this is a no-op for them. Every new JNI object is registered in [arena].
  Bitmap _applyOrientation(Arena arena, JByteArray inputJBytes, Bitmap src) {
    final exifStream = ByteArrayInputStream(inputJBytes)..releasedBy(arena);
    final exif = ExifInterface.new$2(exifStream)..releasedBy(arena);
    final tag = ExifInterface.TAG_ORIENTATION?..releasedBy(arena);
    final value = exif.getAttributeInt(tag, ExifInterface.ORIENTATION_NORMAL);
    if (value == ExifInterface.ORIENTATION_NORMAL || value < 1 || value > 8) {
      return src;
    }

    // Canonical Android EXIF-orientation matrices (degrees are clockwise).
    final matrix = Matrix()..releasedBy(arena);
    switch (value) {
      case 2: // flip horizontal
        matrix.setScale(-1.0, 1.0);
      case 3: // rotate 180
        matrix.setRotate(180.0);
      case 4: // flip vertical
        matrix
          ..setRotate(180.0)
          ..postScale(-1.0, 1.0);
      case 5: // transpose
        matrix
          ..setRotate(90.0)
          ..postScale(-1.0, 1.0);
      case 6: // rotate 90 CW
        matrix.setRotate(90.0);
      case 7: // transverse
        matrix
          ..setRotate(-90.0)
          ..postScale(-1.0, 1.0);
      case 8: // rotate 270 CW
        matrix.setRotate(-90.0);
    }

    final oriented = Bitmap.createBitmap$2(
      src,
      0,
      0,
      src.getWidth(),
      src.getHeight(),
      matrix,
      true, // filter
    )?..releasedBy(arena);
    if (oriented == null) {
      throw const ImageConversionException('Failed to apply EXIF orientation.');
    }
    return oriented;
  }
}
