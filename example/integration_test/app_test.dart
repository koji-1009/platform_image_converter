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

  group('Conversion across source pixel formats', () {
    final sources = <(String, img.Format, int)>[
      ('8-bit grayscale', img.Format.uint8, 1),
      ('8-bit RGB', img.Format.uint8, 3),
      ('8-bit RGBA', img.Format.uint8, 4),
      ('16-bit grayscale', img.Format.uint16, 1),
      ('16-bit RGB', img.Format.uint16, 3),
      ('16-bit RGBA', img.Format.uint16, 4),
    ];

    for (final (label, format, channels) in sources) {
      test('$label resizes and stays coherent', () async {
        final input = _makePng(format: format, numChannels: channels);

        final converted = await ImageConverter.convert(
          inputData: input,
          format: OutputFormat.png,
          resizeMode: ExactResizeMode(width: 64, height: 64),
        );

        expect(converted, isNotEmpty);
        final decoded = img.decodeImage(converted);
        expect(decoded, isNotNull);
        expect(decoded!.width, 64);
        expect(decoded.height, 64);

        final info = _inspect(decoded);
        expect(info.varies, isTrue, reason: '$label lost its gradient');
        if (channels == 1) {
          expect(info.achromatic, isTrue, reason: '$label is not gray anymore');
        }
      });
    }

    test('semi-transparent RGBA keeps its alpha through resize', () async {
      final input = _makePng(
        format: img.Format.uint8,
        numChannels: 4,
        transparent: true,
      );

      final converted = await ImageConverter.convert(
        inputData: input,
        format: OutputFormat.png,
        resizeMode: ExactResizeMode(width: 64, height: 64),
      );

      final decoded = img.decodeImage(converted);
      expect(decoded, isNotNull);
      expect(
        _inspect(decoded!).alphaVaries,
        isTrue,
        reason: 'transparency was not preserved',
      );
    });

    test('indexed (palette) PNG resizes without crashing', () async {
      final base = img.Image(width: 128, height: 128, numChannels: 3);
      for (final pixel in base) {
        final v = (((pixel.x + pixel.y) / 254) * 255).round();
        pixel
          ..r = v
          ..g = v ~/ 2
          ..b = 255 - v;
      }
      final input = img.encodePng(img.quantize(base, numberOfColors: 16));

      final converted = await ImageConverter.convert(
        inputData: input,
        format: OutputFormat.png,
        resizeMode: ExactResizeMode(width: 64, height: 64),
      );

      final decoded = img.decodeImage(converted);
      expect(decoded, isNotNull);
      expect(decoded!.width, 64);
      expect(decoded.height, 64);
      expect(_inspect(decoded).varies, isTrue);
    });

    test('16-bit source converts at original size (no-resize path)', () async {
      final input = _makePng(format: img.Format.uint16, numChannels: 3);

      final converted = await ImageConverter.convert(
        inputData: input,
        format: OutputFormat.png,
        resizeMode: const OriginalResizeMode(),
      );

      final decoded = img.decodeImage(converted);
      expect(decoded, isNotNull);
      expect(decoded!.width, 128);
      expect(decoded.height, 128);
    });
  });
}

/// Load an image from assets and return as [Uint8List]
Future<Uint8List> _loadAssetImage(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  return data.buffer.asUint8List();
}

/// Build a PNG with the given bit depth and channel count. When [transparent]
/// the alpha channel ramps 0..max across X so transparency is exercised.
Uint8List _makePng({
  required img.Format format,
  required int numChannels,
  bool transparent = false,
}) {
  final image = img.Image(
    width: 128,
    height: 128,
    format: format,
    numChannels: numChannels,
  );
  final maxValue = format == img.Format.uint16 ? 65535 : 255;
  for (final pixel in image) {
    final v = (((pixel.x + pixel.y) / 254) * maxValue).round();
    pixel
      ..r = v
      ..g = v
      ..b = v
      ..a = transparent ? ((pixel.x / 127) * maxValue).round() : maxValue;
  }
  return img.encodePng(image);
}

/// Sparse-sample [im]: whether it varies, stays achromatic (r==g==b), and
/// whether its alpha varies. Tolerant — exact values differ per platform.
({bool varies, bool achromatic, bool alphaVaries}) _inspect(img.Image im) {
  int? firstLum;
  int? firstAlpha;
  var varies = false;
  var achromatic = true;
  var alphaVaries = false;
  for (var y = 0; y < im.height; y += 8) {
    for (var x = 0; x < im.width; x += 8) {
      final p = im.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final a = p.a.toInt();
      final lum = r + g + b;
      if ((firstLum ??= lum) != lum) varies = true;
      if ((r - g).abs() > 4 || (r - b).abs() > 4) achromatic = false;
      if ((firstAlpha ??= a) != a) alphaVaries = true;
    }
  }
  return (varies: varies, achromatic: achromatic, alphaVaries: alphaVaries);
}
