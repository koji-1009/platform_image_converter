import 'dart:typed_data';

import 'package:platform_image_converter/src/output_format.dart';
import 'package:platform_image_converter/src/output_resize.dart';

/// Platform-specific image converter interface.
///
/// Abstract base class that all platform implementations must implement.
/// Handles the core logic of image format conversion on each platform.
///
/// **Implementations:**
/// - [ImageConverterDarwin]: iOS and macOS using ImageIO
/// - [ImageConverterAndroid]: Android using BitmapFactory
abstract interface class ImageConverterPlatform {
  /// Converts an image to a target format.
  ///
  /// Decodes the input image data and re-encodes it in the specified format.
  ///
  /// **Parameters:**
  /// - [inputData]: Raw bytes of the image to convert
  /// - [format]: Target [OutputFormat] (default: [OutputFormat.jpeg])
  /// - [quality]: Compression quality 1-100 for lossy formats (default: 95)
  /// - [resizeMode]: The resize mode to apply to the image.
  ///
  /// **Returns:** Converted image data as [Uint8List]
  ///
  /// **Throws:**
  /// - [UnimplementedError]: If not implemented by platform subclass
  /// - [UnsupportedError]: If format is not supported
  /// - [ImageDecodingException]: If the input image data cannot be decoded.
  /// - [ImageEncodingException]: If the image cannot be encoded to the target format.
  /// - [ImageConversionException]: For other general errors during the conversion process.
  Future<Uint8List> convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
  }) {
    throw UnimplementedError('convert() has not been implemented.');
  }
}
