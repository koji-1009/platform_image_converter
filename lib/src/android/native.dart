import 'dart:typed_data';

import 'package:image_ffi/gen/jnigen_bindings.dart';
import 'package:image_ffi/src/image_converter_platform_interface.dart';
import 'package:image_ffi/src/output_format.dart';
import 'package:jni/jni.dart';

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
  }) async {
    JByteArray? inputJBytes;
    Bitmap? bitmap;
    Bitmap$CompressFormat? compressFormat;
    ByteArrayOutputStream? outputStream;
    JByteArray? outputJBytes;
    try {
      inputJBytes = JByteArray.from(inputData);
      bitmap = BitmapFactory.decodeByteArray(inputJBytes, 0, inputData.length);
      if (bitmap == null) {
        throw Exception('Failed to decode image. Invalid image data.');
      }

      compressFormat = switch (format) {
        OutputFormat.jpeg => Bitmap$CompressFormat.JPEG,
        OutputFormat.png => Bitmap$CompressFormat.PNG,
        OutputFormat.webp => Bitmap$CompressFormat.WEBP_LOSSY,
        OutputFormat.heic => throw UnsupportedError(
          'HEIC output format is not supported on Android.',
        ),
      };

      outputStream = ByteArrayOutputStream();
      final success = bitmap.compress(compressFormat, quality, outputStream);
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
      bitmap?.recycle();
      bitmap?.release();
      compressFormat?.release();
      outputStream?.release();
      outputJBytes?.release();
    }
  }
}
