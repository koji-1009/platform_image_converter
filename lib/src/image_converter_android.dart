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
  @override
  Future<Uint8List> convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
  }) async {
    final inputJBytes = JByteArray.from(inputData);
    try {
      final bitmap = BitmapFactory.decodeByteArray(
        inputJBytes,
        0,
        inputData.length,
      );
      if (bitmap == null) {
        throw Exception('Failed to decode image. Invalid image data.');
      }

      try {
        final compressFormat = switch (format) {
          OutputFormat.jpeg => Bitmap$CompressFormat.JPEG,
          OutputFormat.png => Bitmap$CompressFormat.PNG,
          OutputFormat.webp => Bitmap$CompressFormat.WEBP_LOSSY,
          OutputFormat.heic => throw UnsupportedError(
            'HEIC output format is not supported on Android.',
          ),
        };

        try {
          final outputStream = ByteArrayOutputStream();
          try {
            final success = bitmap.compress(
              compressFormat,
              quality,
              outputStream,
            );
            if (!success) {
              throw Exception('Failed to compress bitmap.');
            }

            final outputJBytes = outputStream.toByteArray();
            if (outputJBytes == null) {
              throw Exception('Failed to get byte array from output stream.');
            }
            try {
              final outputList = outputJBytes.toList();
              return Uint8List.fromList(outputList);
            } finally {
              outputJBytes.release();
            }
          } finally {
            outputStream.release();
          }
        } finally {
          compressFormat.release();
        }
      } finally {
        bitmap.release();
      }
    } finally {
      inputJBytes.release();
    }
  }
}
