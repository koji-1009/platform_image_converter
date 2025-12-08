library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_ffi/src/image_converter_platform_interface.dart';
import 'package:image_ffi/src/output_format.dart';
import 'package:image_ffi/src/android/shared.dart';
import 'package:image_ffi/src/darwin/shared.dart';
import 'package:image_ffi/src/web/shared.dart';

export 'src/output_format.dart';

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
  /// - [runInIsolate]: Whether to run the conversion in a separate isolate.
  ///   Defaults to `true`.
  ///
  /// **Returns:** A [Future] that completes with the converted image data.
  ///
  /// **Throws:**
  /// - [UnsupportedError]: If the platform or output format is not supported.
  /// - [Exception]: If the image decoding or encoding fails.
  ///
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
    bool runInIsolate = true,
  }) {
    if (runInIsolate) {
      return compute(
        _convertInIsolate,
        _ConvertRequest(inputData, format, quality, defaultTargetPlatform),
      );
    } else {
      // The original implementation for those who opt-out.
      return _platform.convert(
        inputData: inputData,
        format: format,
        quality: quality,
      );
    }
  }
}

/// Helper class to pass arguments to the isolate.
@immutable
class _ConvertRequest {
  final Uint8List inputData;
  final OutputFormat format;
  final int quality;
  final TargetPlatform platform;

  const _ConvertRequest(
    this.inputData,
    this.format,
    this.quality,
    this.platform,
  );
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
Future<Uint8List> _convertInIsolate(_ConvertRequest request) {
  final platform = _getPlatformForTarget(request.platform);
  return platform.convert(
    inputData: request.inputData,
    format: request.format,
    quality: request.quality,
  );
}
