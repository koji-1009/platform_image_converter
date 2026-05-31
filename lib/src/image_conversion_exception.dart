import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:platform_image_converter/src/output_format.dart';

/// Base exception for image conversion errors.
///
/// Every error this package throws during conversion is an
/// [ImageConversionException] (or a subtype), so a single `on
/// ImageConversionException` clause catches them all. Inspect the runtime type
/// or the dedicated fields on a subtype to react to a specific condition.
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

  @override
  String toString() => 'ImageDecodingException: $message';
}

/// Thrown when the image cannot be encoded to the target format.
class ImageEncodingException extends ImageConversionException {
  /// Creates an [ImageEncodingException] with the given [message].
  ImageEncodingException(this.format, [String? message])
    : super(message ?? 'Failed to encode image to ${format.name}');

  /// The format the image was being encoded to when the failure occurred.
  final OutputFormat format;

  @override
  String toString() => 'ImageEncodingException: $message';
}

/// Why an [OutputFormat] cannot be produced in the current environment.
///
/// Lets callers tell a permanent platform limitation apart from a missing-codec
/// condition the user could resolve, instead of parsing the message string.
enum UnsupportedFormatReason {
  /// The platform's image stack has no encoder for this format and never will
  /// (for example WebP on iOS/macOS or Windows, HEIC on Android or Web). This
  /// is knowable statically: do not offer the format on this platform.
  platformUnsupported,

  /// The platform can encode this format, but the current machine lacks the
  /// required codec or OS version (for example Windows HEIC needs the HEVC/HEIF
  /// codec, shipped on Windows 11 22H2+ or installable from the Microsoft
  /// Store). Recoverable: the user can install the codec, or the app can fall
  /// back to another format.
  codecUnavailable,
}

/// Thrown when the requested [OutputFormat] cannot be produced.
///
/// Inspect [reason] to distinguish a permanent platform limitation
/// ([UnsupportedFormatReason.platformUnsupported]) from a missing codec that the
/// user could install ([UnsupportedFormatReason.codecUnavailable]).
class UnsupportedFormatException extends ImageConversionException {
  /// Creates an [UnsupportedFormatException] for [format] with the given
  /// [reason], optionally overriding the default [message].
  UnsupportedFormatException(this.format, this.reason, [String? message])
    : super(message ?? _defaultMessage(format, reason));

  /// The output format that is not available.
  final OutputFormat format;

  /// Why [format] cannot be produced in the current environment.
  final UnsupportedFormatReason reason;

  static String _defaultMessage(
    OutputFormat format,
    UnsupportedFormatReason reason,
  ) => switch (reason) {
    UnsupportedFormatReason.platformUnsupported =>
      '${format.name} output is not supported on this platform.',
    UnsupportedFormatReason.codecUnavailable =>
      '${format.name} output requires a codec that is not available in this '
          'environment.',
  };

  @override
  String toString() => 'UnsupportedFormatException: $message';
}

/// Thrown when image conversion is not supported on the current platform.
///
/// Raised when the plugin has no native backend for [platform] (for example an
/// operating system the plugin does not yet implement).
class UnsupportedPlatformException extends ImageConversionException {
  /// Creates an [UnsupportedPlatformException] for [platform], optionally
  /// overriding the default [message].
  UnsupportedPlatformException(this.platform, [String? message])
    : super(
        message ?? 'Image conversion is not supported on this platform: '
            '$platform',
      );

  /// The platform that has no image-conversion backend.
  final TargetPlatform platform;

  @override
  String toString() => 'UnsupportedPlatformException: $message';
}
