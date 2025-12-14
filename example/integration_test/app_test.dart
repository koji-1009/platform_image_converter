import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:platform_image_converter/platform_image_converter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpegData;
  late Uint8List pngData;
  late Uint8List webpData;

  setUpAll(() async {
    // Load test images from assets
    jpegData = await _loadAssetImage('assets/jpeg.jpg');
    pngData = await _loadAssetImage('assets/png.png');
    webpData = await _loadAssetImage('assets/webp.webp');
  });

  group('Image resizing tests', () {
    test('OriginalResizeMode preserves original dimensions', () async {
      final originalImage = img.decodeImage(jpegData)!;
      final originalWidth = originalImage.width;
      final originalHeight = originalImage.height;

      final converted = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.jpeg,
        resizeMode: const OriginalResizeMode(),
      );

      final resizedImage = img.decodeImage(converted)!;
      expect(resizedImage.width, equals(originalWidth));
      expect(resizedImage.height, equals(originalHeight));
    });

    test('ExactResizeMode resizes to exact dimensions', () async {
      final targetWidth = 100;
      final targetHeight = 150;

      final converted = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.jpeg,
        resizeMode: ExactResizeMode(width: targetWidth, height: targetHeight),
      );

      final resizedImage = img.decodeImage(converted)!;
      expect(resizedImage.width, equals(targetWidth));
      expect(resizedImage.height, equals(targetHeight));
    });

    test('FitResizeMode maintains aspect ratio when downscaling', () async {
      // Original jpeg.jpg is 1502x2000
      final targetWidth = 200;
      final targetHeight = 200;
      final expectedWidth = 150;
      final expectedHeight = 200;

      final converted = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.jpeg,
        resizeMode: FitResizeMode(width: targetWidth, height: targetHeight),
      );

      final resizedImage = img.decodeImage(converted)!;
      // Allow for small rounding differences
      expect(resizedImage.width, closeTo(expectedWidth, 1));
      expect(resizedImage.height, closeTo(expectedHeight, 1));
    });

    test('FitResizeMode does not upscale smaller images', () async {
      final originalImage = img.decodeImage(jpegData)!;
      final originalWidth = originalImage.width;
      final originalHeight = originalImage.height;

      // Target dimensions are larger than the original
      final targetWidth = originalWidth * 2;
      final targetHeight = originalHeight * 2;

      final converted = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.jpeg,
        resizeMode: FitResizeMode(width: targetWidth, height: targetHeight),
      );

      final resizedImage = img.decodeImage(converted)!;
      expect(resizedImage.width, equals(originalWidth));
      expect(resizedImage.height, equals(originalHeight));
    });

    test('FitResizeMode with only width maintains aspect ratio', () async {
      // Original jpeg.jpg is 1502x2000
      final targetWidth = 150;
      final expectedWidth = 150;
      final expectedHeight = 200;

      final converted = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.jpeg,
        resizeMode: FitResizeMode(width: targetWidth),
      );

      final resizedImage = img.decodeImage(converted)!;
      // Allow for small rounding differences
      expect(resizedImage.width, closeTo(expectedWidth, 1));
      expect(resizedImage.height, closeTo(expectedHeight, 1));
    });

    test('FitResizeMode with only height maintains aspect ratio', () async {
      // Original jpeg.jpg is 1502x2000
      final targetHeight = 200;
      final expectedWidth = 150;
      final expectedHeight = 200;

      final converted = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.jpeg,
        resizeMode: FitResizeMode(height: targetHeight),
      );

      final resizedImage = img.decodeImage(converted)!;
      // Allow for small rounding differences
      expect(resizedImage.width, closeTo(expectedWidth, 1));
      expect(resizedImage.height, closeTo(expectedHeight, 1));
    });
  });

  group('File size consistency tests', () {
    test('Same format with quality 100 should produce same file size', () async {
      // JPEG to JPEG with quality 100
      final converted1 = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.jpeg,
        quality: 100,
      );
      final converted2 = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.jpeg,
        quality: 100,
      );

      expect(
        converted1.length,
        equals(converted2.length),
        reason:
            'Converting same image with same format and quality=100 should produce same file size',
      );
    });

    test(
      'Same format with quality 50 should produce different file size than quality 100',
      () async {
        // JPEG to JPEG with quality 100
        final quality100 = await ImageConverter.convert(
          inputData: jpegData,
          format: OutputFormat.jpeg,
          quality: 100,
        );

        // JPEG to JPEG with quality 50
        final quality50 = await ImageConverter.convert(
          inputData: jpegData,
          format: OutputFormat.jpeg,
          quality: 50,
        );

        expect(
          quality100.length,
          isNot(equals(quality50.length)),
          reason:
              'Converting same image with same format but different quality should produce different file size',
        );

        // Quality 50 should typically be smaller than quality 100
        expect(
          quality50.length,
          lessThan(quality100.length),
          reason: 'Lower quality should result in smaller file size',
        );
      },
    );

    test(
      'Different formats with quality 100 should produce different file size',
      () async {
        // JPEG with quality 100
        final jpegConverted = await ImageConverter.convert(
          inputData: jpegData,
          format: OutputFormat.jpeg,
          quality: 100,
        );

        // PNG with quality 100
        final pngConverted = await ImageConverter.convert(
          inputData: jpegData,
          format: OutputFormat.png,
          quality: 100,
        );

        expect(
          jpegConverted.length,
          isNot(equals(pngConverted.length)),
          reason:
              'Converting same image to different formats should produce different file size',
        );
      },
    );

    test('PNG to PNG with quality 100 should produce same file size', () async {
      // PNG to PNG with quality 100
      final converted1 = await ImageConverter.convert(
        inputData: pngData,
        format: OutputFormat.png,
        quality: 100,
      );
      final converted2 = await ImageConverter.convert(
        inputData: pngData,
        format: OutputFormat.png,
        quality: 100,
      );

      expect(
        converted1.length,
        equals(converted2.length),
        reason:
            'Converting same PNG with same format and quality=100 should produce same file size',
      );
    });

    test('PNG to PNG with quality 50 should produce same file size', () async {
      // PNG with quality 100
      final quality100 = await ImageConverter.convert(
        inputData: pngData,
        format: OutputFormat.png,
        quality: 100,
      );

      // PNG with quality 50
      final quality50 = await ImageConverter.convert(
        inputData: pngData,
        format: OutputFormat.png,
        quality: 50,
      );

      expect(
        quality100.length,
        equals(quality50.length),
        reason:
            'Converting same PNG with same format and quality=50 should produce same file size',
      );
    });

    test('WebP to WebP with quality 100 should produce same file size', () async {
      if (defaultTargetPlatform == TargetPlatform.android || kIsWeb) {
        // WebP to WebP with quality 100
        final converted1 = await ImageConverter.convert(
          inputData: webpData,
          format: OutputFormat.webp,
          quality: 100,
        );
        final converted2 = await ImageConverter.convert(
          inputData: webpData,
          format: OutputFormat.webp,
          quality: 100,
        );

        expect(
          converted1.length,
          equals(converted2.length),
          reason:
              'Converting same WebP with same format and quality=100 should produce same file size',
        );
      } else {
        expect(
          () => ImageConverter.convert(
            inputData: webpData,
            format: OutputFormat.webp,
            quality: 100,
          ),
          throwsA(isA<UnsupportedError>()),
          reason: 'WebP output is only supported on Android and Web.',
        );
      }
    });

    test(
      'WebP with quality 50 should produce different file size than quality 100',
      () async {
        if (defaultTargetPlatform == TargetPlatform.android || kIsWeb) {
          // WebP with quality 100
          final quality100 = await ImageConverter.convert(
            inputData: webpData,
            format: OutputFormat.webp,
            quality: 100,
          );

          // WebP with quality 50
          final quality50 = await ImageConverter.convert(
            inputData: webpData,
            format: OutputFormat.webp,
            quality: 50,
          );

          expect(
            quality100.length,
            isNot(equals(quality50.length)),
            reason:
                'Converting same WebP with different quality should produce different file size',
          );
        } else {
          expect(
            () => ImageConverter.convert(
              inputData: webpData,
              format: OutputFormat.webp,
              quality: 50,
            ),
            throwsA(isA<UnsupportedError>()),
            reason: 'WebP output is only supported on Android and Web.',
          );
        }
      },
    );
  });

  group('Format conversion tests', () {
    test('JPEG to PNG should produce different file size', () async {
      final jpegConverted = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.jpeg,
        quality: 100,
      );

      final pngConverted = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.png,
        quality: 100,
      );

      expect(
        jpegConverted.length,
        isNot(equals(pngConverted.length)),
        reason: 'Converting JPEG to PNG should produce different file size',
      );
    });

    test('JPEG to WebP should produce different file size', () async {
      if (defaultTargetPlatform == TargetPlatform.android || kIsWeb) {
        final jpegConverted = await ImageConverter.convert(
          inputData: jpegData,
          format: OutputFormat.jpeg,
          quality: 100,
        );

        final webpConverted = await ImageConverter.convert(
          inputData: jpegData,
          format: OutputFormat.webp,
          quality: 100,
        );

        expect(
          jpegConverted.length,
          isNot(equals(webpConverted.length)),
          reason: 'Converting JPEG to WebP should produce different file size',
        );
      } else {
        expect(
          () => ImageConverter.convert(
            inputData: jpegData,
            format: OutputFormat.webp,
            quality: 100,
          ),
          throwsA(isA<UnsupportedError>()),
          reason: 'WebP output is only supported on Android and Web.',
        );
      }
    });

    test('PNG to JPEG should produce different file size', () async {
      final pngConverted = await ImageConverter.convert(
        inputData: pngData,
        format: OutputFormat.png,
        quality: 100,
      );

      final jpegConverted = await ImageConverter.convert(
        inputData: pngData,
        format: OutputFormat.jpeg,
        quality: 100,
      );

      expect(
        pngConverted.length,
        isNot(equals(jpegConverted.length)),
        reason: 'Converting PNG to JPEG should produce different file size',
      );
    });
  });

  group('Platform-specific format support', () {
    test('WebP output support', () async {
      if (defaultTargetPlatform == TargetPlatform.android || kIsWeb) {
        final webpConverted = await ImageConverter.convert(
          inputData: jpegData,
          format: OutputFormat.webp,
        );
        expect(webpConverted, isA<Uint8List>());
        expect(webpConverted.isNotEmpty, isTrue);
      } else {
        expect(
          () => ImageConverter.convert(
            inputData: jpegData,
            format: OutputFormat.webp,
          ),
          throwsA(isA<UnsupportedError>()),
          reason: 'WebP output is not supported on this platform.',
        );
      }
    });
  });
}

/// Load an image from assets and return as [Uint8List]
Future<Uint8List> _loadAssetImage(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  return data.buffer.asUint8List();
}
