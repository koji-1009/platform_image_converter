import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_image_converter/platform_image_converter.dart';

void main() {
  group('ImageConversionException', () {
    test('exposes its message and is a catchable Exception', () {
      const e = ImageConversionException('boom');
      expect(e.message, 'boom');
      expect(e.toString(), 'ImageConversionException: boom');
      expect(e, isA<Exception>());
    });
  });

  group('ImageDecodingException', () {
    test('defaults its message and extends ImageConversionException', () {
      const e = ImageDecodingException();
      expect(e.message, 'Failed to decode image data.');
      expect(
        e.toString(),
        'ImageDecodingException: Failed to decode image data.',
      );
      expect(e, isA<ImageConversionException>());
    });

    test('accepts a custom message', () {
      const e = ImageDecodingException('bad header');
      expect(e.toString(), 'ImageDecodingException: bad header');
    });
  });

  group('ImageEncodingException', () {
    test('derives a default message from the format', () {
      final e = ImageEncodingException(OutputFormat.png);
      expect(e.format, OutputFormat.png);
      expect(e.message, 'Failed to encode image to png');
      expect(
        e.toString(),
        'ImageEncodingException: Failed to encode image to png',
      );
      expect(e, isA<ImageConversionException>());
    });

    test('accepts a custom message', () {
      final e = ImageEncodingException(OutputFormat.jpeg, 'encoder refused');
      expect(e.format, OutputFormat.jpeg);
      expect(e.toString(), 'ImageEncodingException: encoder refused');
    });
  });

  group('UnsupportedFormatException', () {
    test('stores the format and reason', () {
      final e = UnsupportedFormatException(
        OutputFormat.webp,
        UnsupportedFormatReason.platformUnsupported,
      );
      expect(e.format, OutputFormat.webp);
      expect(e.reason, UnsupportedFormatReason.platformUnsupported);
    });

    test('default message reflects a permanent platform limitation', () {
      final e = UnsupportedFormatException(
        OutputFormat.webp,
        UnsupportedFormatReason.platformUnsupported,
      );
      expect(e.message, 'webp output is not supported on this platform.');
      expect(e.toString(), startsWith('UnsupportedFormatException: '));
    });

    test('default message reflects a missing codec', () {
      final e = UnsupportedFormatException(
        OutputFormat.heic,
        UnsupportedFormatReason.codecUnavailable,
      );
      expect(e.message, contains('codec'));
    });

    test('accepts a custom message', () {
      final e = UnsupportedFormatException(
        OutputFormat.heic,
        UnsupportedFormatReason.codecUnavailable,
        'install HEVC Video Extensions',
      );
      expect(
        e.toString(),
        'UnsupportedFormatException: install HEVC Video Extensions',
      );
    });

    test('is a catchable ImageConversionException, not a dart:core Error', () {
      final e = UnsupportedFormatException(
        OutputFormat.webp,
        UnsupportedFormatReason.platformUnsupported,
      );
      expect(e, isA<ImageConversionException>());
      expect(e, isA<Exception>());
      expect(e, isNot(isA<Error>()));
      expect(e, isNot(isA<UnsupportedError>()));
    });
  });

  group('UnsupportedPlatformException', () {
    test('stores the platform and builds a default message', () {
      final e = UnsupportedPlatformException(TargetPlatform.linux);
      expect(e.platform, TargetPlatform.linux);
      expect(e.message, contains('TargetPlatform.linux'));
      expect(e.toString(), startsWith('UnsupportedPlatformException: '));
    });

    test('accepts a custom message', () {
      final e = UnsupportedPlatformException(
        TargetPlatform.fuchsia,
        'no backend yet',
      );
      expect(e.platform, TargetPlatform.fuchsia);
      expect(e.toString(), 'UnsupportedPlatformException: no backend yet');
    });

    test('is a catchable ImageConversionException, not a dart:core Error', () {
      final e = UnsupportedPlatformException(TargetPlatform.linux);
      expect(e, isA<ImageConversionException>());
      expect(e, isA<Exception>());
      expect(e, isNot(isA<Error>()));
    });
  });
}
