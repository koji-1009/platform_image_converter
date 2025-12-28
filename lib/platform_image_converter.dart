library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:platform_image_converter/src/android/shared.dart';
import 'package:platform_image_converter/src/darwin/shared.dart';
import 'package:platform_image_converter/src/image_converter_platform_interface.dart';
import 'package:platform_image_converter/src/output_format.dart';
import 'package:platform_image_converter/src/output_resize.dart';
import 'package:platform_image_converter/src/web/shared.dart';

export 'src/image_conversion_exception.dart';
export 'src/output_format.dart';
export 'src/output_resize.dart';

/// Main entry point for image format conversion.
///
/// Provides a platform-agnostic interface to convert images across iOS,
/// macOS, and Android platforms using native APIs.
class ImageConverter {
  /// The platform-specific implementation of the image converter.
  ///
  /// This is initialized based on the current platform.
  static ImageConverterPlatform get _platform =>
      _getPlatformForTarget(defaultTargetPlatform);

  /// Converts an image to a target format.
  ///
  /// By default, this operation is performed in a separate isolate to avoid
  /// blocking the UI thread. For very small images, the overhead of an isolate
  /// can be disabled by setting [runInIsolate] to `false`.
  ///
  /// **Parameters:**
  /// - [inputData]: Raw bytes of the image to convert.
  /// - [format]: Target [OutputFormat]. Defaults to [OutputFormat.jpeg].
  /// - [quality]: Compression quality for lossy formats (1-100).
  /// - [resizeMode]: The resize mode to apply to the image.
  /// - [runInIsolate]: Whether to run the conversion in a separate isolate.
  ///   Defaults to `true`.
  ///
  /// **Returns:** A [Future] that completes with the converted image data.
  ///
  /// **Throws:**
  /// - [UnsupportedError]: If the platform or output format is not supported.
  /// - [ImageDecodingException]: If the input image data cannot be decoded.
  /// - [ImageEncodingException]: If the image cannot be encoded to the target format.
  /// - [ImageConversionException]: For other general errors during the conversion process.
  /// **Example - Convert HEIC to JPEG:**
  /// ```dart
  /// final jpegData = await ImageConverter.convert(
  ///   inputData: heicImageData,
  ///   format: OutputFormat.jpeg,
  ///   quality: 90,
  /// );
  /// ```
  ///
  /// **Example - Running on the main thread:**
  /// ```dart
  /// // Only do this for very small images where isolate overhead is a concern.
  /// final pngData = await ImageConverter.convert(
  ///   inputData: smallImageData,
  ///   format: OutputFormat.png,
  ///   runInIsolate: false,
  /// );
  /// ```
  static Future<Uint8List> convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
    bool runInIsolate = true,
  }) async {
    assert(
      quality >= 1 && quality <= 100,
      'Quality must be between 1 and 100.',
    );
    if (runInIsolate) {
      return await compute(_convertInIsolate, (
        inputData: inputData,
        format: format,
        quality: quality,
        resizeMode: resizeMode,
        platform: defaultTargetPlatform,
      ));
    } else {
      // The original implementation for those who opt-out.
      return await _platform.convert(
        inputData: inputData,
        format: format,
        quality: quality,
        resizeMode: resizeMode,
      );
    }
  }
}

/// Returns the platform-specific converter instance.
ImageConverterPlatform _getPlatformForTarget(TargetPlatform platform) {
  if (kIsWeb) {
    return const ImageConverterWeb();
  }
  return switch (platform) {
    TargetPlatform.android => const ImageConverterAndroid(),
    TargetPlatform.iOS || TargetPlatform.macOS => const ImageConverterDarwin(),
    _ => throw UnsupportedError(
      'Image conversion is not supported on this platform: $platform',
    ),
  };
}

/// Top-level function for `compute`.
FutureOr<Uint8List> _convertInIsolate(
  ({
    Uint8List inputData,
    OutputFormat format,
    int quality,
    ResizeMode resizeMode,
    TargetPlatform platform,
  })
  request,
) => _getPlatformForTarget(request.platform).convert(
  inputData: request.inputData,
  format: request.format,
  quality: request.quality,
  resizeMode: request.resizeMode,
);
