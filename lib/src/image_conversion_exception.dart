import 'package:platform_image_converter/src/output_format.dart';

/// Base exception for image conversion errors.
class ImageConversionException implements Exception {
  /// Creates an [ImageConversionException] with the given [message].
  const ImageConversionException(this.message);

  /// Error message describing the exception.
  final String message;

  @override
  String toString() => 'ImageConversionException: $message';
}

/// Thrown when the input image data cannot be decoded.
class ImageDecodingException extends ImageConversionException {
  /// Creates an [ImageDecodingException] with the given [message].
  const ImageDecodingException([
    super.message = 'Failed to decode image data.',
  ]);
}

/// Thrown when the image cannot be encoded to the target format.
class ImageEncodingException extends ImageConversionException {
  /// Creates an [ImageEncodingException] with the given [message].
  ImageEncodingException(this.format, [String? message])
      : super(message ?? 'Failed to encode image to ${format.name}');

  final OutputFormat format;
}
