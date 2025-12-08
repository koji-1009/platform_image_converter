import 'dart:typed_data';

import 'output_format.dart';

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
  ///
  /// **Returns:** Converted image data as [Uint8List]
  ///
  /// **Throws:**
  /// - [UnimplementedError]: If not implemented by platform subclass
  /// - [UnsupportedError]: If format is not supported
  /// - [Exception]: If conversion fails
  Future<Uint8List> convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
  }) {
    throw UnimplementedError('convert() has not been implemented.');
  }
}
