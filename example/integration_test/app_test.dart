import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:platform_image_converter/platform_image_converter.dart';

import 'android_api_level.dart';

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

  group('Output format', () {
    // Each source converted to each output format: the output must be in the
    // requested format, decode, keep the source size and, where the source is
    // sRGB, keep its pixels. png.png carries a non-sRGB (PQ) colour profile
    // that the backends treat differently (see README), so only its format and
    // size are checked.
    final sources = <(String, Uint8List Function(), bool, bool)>[
      ('JPEG', () => jpegData, true, true),
      ('PNG', () => pngData, false, true),
      ('WebP', () => webpData, true, _supportsWebpInput),
    ];
    for (final (label, source, comparePixels, decodable) in sources) {
      for (final format in const [
        OutputFormat.jpeg,
        OutputFormat.png,
        OutputFormat.webp,
      ]) {
        test(
          '$label to ${format.name}',
          () async {
            final input = source();
            final converted = await ImageConverter.convert(
              inputData: input,
              format: format,
            );

            expect(_detectFormat(converted), format);
            final expected = img.bakeOrientation(img.decodeImage(input)!);
            final actual = img.decodeImage(converted);
            expect(actual, isNotNull);
            expect(actual!.width, expected.width);
            expect(actual.height, expected.height);
            if (comparePixels) {
              expect(_meanRgbDiff(expected, actual), lessThan(8));
            }
          },
          skip: !decodable
              ? '$label input is not supported'
              : format == OutputFormat.webp
              ? _webpOutputSkip
              : false,
        );
      }
    }
  });

  group('Quality', () {
    Future<(Uint8List, Uint8List)> convertAt100And50(
      Uint8List input,
      OutputFormat format,
    ) async => (
      await ImageConverter.convert(
        inputData: input,
        format: format,
        quality: 100,
      ),
      await ImageConverter.convert(
        inputData: input,
        format: format,
        quality: 50,
      ),
    );

    test('JPEG: the same quality produces identical output', () async {
      final (first, _) = await convertAt100And50(jpegData, OutputFormat.jpeg);
      final (second, _) = await convertAt100And50(jpegData, OutputFormat.jpeg);
      expect(second, equals(first));
    });

    test(
      'JPEG: lower quality gives a smaller file that still matches the source',
      () async {
        final (q100, q50) = await convertAt100And50(
          jpegData,
          OutputFormat.jpeg,
        );
        expect(q50.length, lessThan(q100.length));
        final expected = img.bakeOrientation(img.decodeImage(jpegData)!);
        expect(_meanRgbDiff(expected, img.decodeJpg(q50)!), lessThan(16));
      },
    );

    test('PNG: quality has no effect', () async {
      final (q100, q50) = await convertAt100And50(pngData, OutputFormat.png);
      expect(q50, equals(q100));
    });

    test('WebP: the same quality produces identical output', () async {
      final (first, _) = await convertAt100And50(webpData, OutputFormat.webp);
      final (second, _) = await convertAt100And50(webpData, OutputFormat.webp);
      expect(second, equals(first));
    }, skip: _webpOutputSkip);

    test(
      'WebP: lower quality gives a smaller file that still matches the source',
      () async {
        final (q100, q50) = await convertAt100And50(
          webpData,
          OutputFormat.webp,
        );
        expect(q50.length, lessThan(q100.length));
        final expected = img.bakeOrientation(img.decodeImage(webpData)!);
        expect(_meanRgbDiff(expected, img.decodeWebP(q50)!), lessThan(16));
      },
      skip: _skipUnless(
        _webpQualityAffectsOutput,
        'WebP quality does not affect the output on this platform',
      ),
    );

    test(
      'WebP: quality has no effect',
      () async {
        final (q100, q50) = await convertAt100And50(
          webpData,
          OutputFormat.webp,
        );
        expect(q50, equals(q100));
      },
      skip: _skipUnless(
        _supportsWebpOutput && !_webpQualityAffectsOutput,
        'WebP quality affects the output, or WebP output is unsupported, on '
        'this platform',
      ),
    );
  });

  group('Platform-specific format support', () {
    test('WebP output throws UnsupportedFormatException', () async {
      await expectLater(
        ImageConverter.convert(inputData: jpegData, format: OutputFormat.webp),
        throwsA(isA<UnsupportedFormatException>()),
      );
    }, skip: _skipUnless(!_supportsWebpOutput, 'WebP output is supported'));

    test('HEIC output is codecUnavailable on Linux', () async {
      await expectLater(
        ImageConverter.convert(inputData: jpegData, format: OutputFormat.heic),
        throwsA(
          isA<UnsupportedFormatException>().having(
            (e) => e.reason,
            'reason',
            UnsupportedFormatReason.codecUnavailable,
          ),
        ),
      );
    }, skip: _linuxOnlySkip);
  });

  group('AVIF output', () {
    // AVIF output is read back through the converter itself (to PNG), since
    // the image package does not decode AVIF.
    Future<img.Image> decodeAvif(Uint8List avif) async => img.decodePng(
      await ImageConverter.convert(inputData: avif, format: OutputFormat.png),
    )!;

    test('JPEG to avif', () async {
      final converted = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.avif,
        quality: 90,
      );

      expect(_detectFormat(converted), OutputFormat.avif);
      final expected = img.bakeOrientation(img.decodeImage(jpegData)!);
      final actual = await decodeAvif(converted);
      expect(actual.width, expected.width);
      expect(actual.height, expected.height);
      expect(_meanRgbDiff(expected, actual), lessThan(8));
    }, skip: _avifOutputSkip);

    test('semi-transparent RGBA keeps its alpha', () async {
      final input = _makePng(
        format: img.Format.uint8,
        numChannels: 4,
        transparent: true,
      );

      final converted = await ImageConverter.convert(
        inputData: input,
        format: OutputFormat.avif,
        quality: 90,
      );

      expect(_detectFormat(converted), OutputFormat.avif);
      final decoded = await decodeAvif(converted);
      expect(decoded.width, 128);
      expect(decoded.height, 128);
      expect(
        _inspect(decoded).alphaVaries,
        isTrue,
        reason: 'transparency was not preserved',
      );
    }, skip: _skipUnless(_avifKeepsAlpha, 'AVIF output has no alpha'));

    test('Android: transparent pixels flatten to black', () async {
      // Alpha ramps 0..255 across X (fully transparent at x=0, opaque at
      // x=127); the gray value ramps with x+y.
      final input = _makePng(
        format: img.Format.uint8,
        numChannels: 4,
        transparent: true,
      );

      final converted = await ImageConverter.convert(
        inputData: input,
        format: OutputFormat.avif,
        quality: 90,
      );

      expect(_detectFormat(converted), OutputFormat.avif);
      final decoded = await decodeAvif(converted);
      expect(decoded.width, 128);
      expect(decoded.height, 128);
      expect(_inspect(decoded).alphaVaries, isFalse);
      // Transparent edge: composited onto black.
      expect(decoded.getPixel(0, 64).r, closeTo(0, 24));
      // Opaque edge: keeps the source gray, (127 + 64) / 254 * 255 ≈ 192.
      expect(decoded.getPixel(127, 64).r, closeTo(192, 24));
    }, skip: _skipUnless(_isAndroidWithAvif, 'Not Android with AVIF output'));

    test('the same quality produces identical output', () async {
      final first = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.avif,
      );
      final second = await ImageConverter.convert(
        inputData: jpegData,
        format: OutputFormat.avif,
      );
      expect(second, equals(first));
    }, skip: _avifOutputSkip);

    test(
      'lower quality gives a smaller file that still matches the source',
      () async {
        final q100 = await ImageConverter.convert(
          inputData: jpegData,
          format: OutputFormat.avif,
          quality: 100,
        );
        final q50 = await ImageConverter.convert(
          inputData: jpegData,
          format: OutputFormat.avif,
          quality: 50,
        );
        expect(_detectFormat(q100), OutputFormat.avif);
        expect(_detectFormat(q50), OutputFormat.avif);
        expect(q50.length, lessThan(q100.length));
        final expected = img.bakeOrientation(img.decodeImage(jpegData)!);
        expect(_meanRgbDiff(expected, await decodeAvif(q50)), lessThan(16));
      },
      skip: _avifOutputSkip,
    );

    test('throws codecUnavailable where Android cannot write AVIF', () async {
      await expectLater(
        ImageConverter.convert(inputData: jpegData, format: OutputFormat.avif),
        throwsA(
          isA<UnsupportedFormatException>().having(
            (e) => e.reason,
            'reason',
            UnsupportedFormatReason.codecUnavailable,
          ),
        ),
      );
    }, skip: _skipUnless(_isAndroidWithoutAvif, 'Android writes AVIF here'));

    test('throws platformUnsupported on Web', () async {
      await expectLater(
        ImageConverter.convert(inputData: jpegData, format: OutputFormat.avif),
        throwsA(
          isA<UnsupportedFormatException>().having(
            (e) => e.reason,
            'reason',
            UnsupportedFormatReason.platformUnsupported,
          ),
        ),
      );
    }, skip: _skipUnless(kIsWeb, 'Not Web'));
  });

  group('JPEG output from a source with alpha', () {
    // Alpha ramps 0..255 across X (fully transparent at x=0, opaque at
    // x=127); the gray value ramps with x+y.
    final input = _makePng(
      format: img.Format.uint8,
      numChannels: 4,
      transparent: true,
    );

    for (final (label, resizeMode, size) in <(String, ResizeMode, int)>[
      ('original size', const OriginalResizeMode(), 128),
      ('resized', ExactResizeMode(width: 64, height: 64), 64),
    ]) {
      test('$label: transparent pixels flatten to black', () async {
        final converted = await ImageConverter.convert(
          inputData: input,
          format: OutputFormat.jpeg,
          resizeMode: resizeMode,
        );

        final decoded = img.decodeJpg(converted);
        expect(decoded, isNotNull);
        expect(decoded!.width, size);
        expect(decoded.height, size);
        expect(decoded.numChannels, 3);

        final mid = size ~/ 2;
        // Transparent edge: composited onto black.
        final transparent = decoded.getPixel(0, mid);
        expect(transparent.r, closeTo(0, 24));
        // Opaque edge: keeps the source gray, (127 + 64) / 254 * 255 ≈ 192.
        final opaque = decoded.getPixel(size - 1, mid);
        expect(opaque.r, closeTo(192, 24));
      }, skip: _linuxOnlySkip);
    }
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

  group('EXIF orientation', () {
    // A 64x32 image split into four solid-color quadrants. Non-square so the
    // axis swap of 90/270 rotations is observable, and four distinct colors so
    // the corner mapping (rotation direction and mirroring) is observable too.
    img.Image buildQuadrants() {
      final image = img.Image(width: 64, height: 32);
      for (final p in image) {
        final left = p.x < 32;
        final top = p.y < 16;
        if (top && left) {
          p.setRgb(255, 0, 0); // top-left: red
        } else if (top && !left) {
          p.setRgb(0, 255, 0); // top-right: green
        } else if (!top && left) {
          p.setRgb(0, 0, 255); // bottom-left: blue
        } else {
          p.setRgb(255, 255, 0); // bottom-right: yellow
        }
      }
      return image;
    }

    // Center of a quadrant, sampled well away from boundaries so JPEG ringing
    // does not bleed across colors.
    ({int r, int g, int b}) quadrant(
      img.Image im, {
      required bool top,
      required bool left,
    }) {
      final x = left ? im.width ~/ 4 : im.width * 3 ~/ 4;
      final y = top ? im.height ~/ 4 : im.height * 3 ~/ 4;
      final p = im.getPixel(x, y);
      return (r: p.r.toInt(), g: p.g.toInt(), b: p.b.toInt());
    }

    for (var o = 1; o <= 8; o++) {
      test('orientation $o: apply matches the baked orientation', () async {
        final tagged = buildQuadrants()..exif.imageIfd.orientation = o;
        final input = img.encodeJpg(tagged, quality: 100);

        // Oracle: the image package bakes the same EXIF orientation into pixels.
        final expected = img.bakeOrientation(img.decodeJpg(input)!);

        final outBytes = await ImageConverter.convert(
          inputData: input,
          format: OutputFormat.png,
          orientation: ExifOrientationPolicy.apply,
        );
        final out = img.decodeImage(outBytes)!;

        expect(out.width, expected.width, reason: 'orientation $o width');
        expect(out.height, expected.height, reason: 'orientation $o height');

        for (final top in const [true, false]) {
          for (final left in const [true, false]) {
            final a = quadrant(out, top: top, left: left);
            final b = quadrant(expected, top: top, left: left);
            final where =
                'o$o ${top ? 'top' : 'bottom'}-${left ? 'left' : 'right'}';
            expect(a.r, closeTo(b.r, 48), reason: '$where R');
            expect(a.g, closeTo(b.g, 48), reason: '$where G');
            expect(a.b, closeTo(b.b, 48), reason: '$where B');
          }
        }
      });
    }

    test('ignore keeps the raw buffer layout for a 90-degree tag', () async {
      final tagged = buildQuadrants()..exif.imageIfd.orientation = 6;
      final input = img.encodeJpg(tagged, quality: 100);

      final outBytes = await ImageConverter.convert(
        inputData: input,
        format: OutputFormat.png,
        orientation: ExifOrientationPolicy.ignore,
      );
      final out = img.decodeImage(outBytes)!;

      // No rotation: the raw 64x32 buffer is preserved (not swapped to 32x64),
      // and the red quadrant stays in the top-left.
      expect(out.width, 64);
      expect(out.height, 32);
      final tl = quadrant(out, top: true, left: true);
      expect(tl.r, closeTo(255, 48));
      expect(tl.g, closeTo(0, 48));
      expect(tl.b, closeTo(0, 48));
    });
  });
}

/// Load an image from assets and return as [Uint8List]
Future<Uint8List> _loadAssetImage(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  return data.buffer.asUint8List();
}

/// Platforms on which WebP output is expected to succeed.
bool get _supportsWebpOutput =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.linux;

/// Platforms on which WebP input is expected to decode. On Windows WebP
/// decoding requires an OS codec (see README).
bool get _supportsWebpInput =>
    kIsWeb || defaultTargetPlatform != TargetPlatform.windows;

/// Platforms on which WebP `quality` changes the encoded output.
bool get _webpQualityAffectsOutput =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.android;

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Android 14 (API 34) added the AV1 encoder and AVIF muxing that AVIF output
/// needs; Android 16 before QPR2 (SDK 36.0, below 3600001) writes no AVIF
/// image items (see README).
bool get _androidWritesAvif {
  final apiLevel = androidApiLevel();
  return apiLevel >= 34 && (apiLevel != 36 || androidSdkFull() >= 3600001);
}

bool get _isAndroidWithoutAvif => _isAndroid && !_androidWritesAvif;

bool get _isAndroidWithAvif => _isAndroid && _androidWritesAvif;

/// Platforms whose AVIF output keeps an alpha channel. Android's AV1 encoders
/// cannot encode the monochrome alpha image AVIF requires (see README).
bool get _avifKeepsAlpha => _supportsAvifOutput && !_isAndroid;

/// Platforms on which AVIF output is expected to succeed. On Windows it
/// depends on the HEIF codec and an AV1 encoder (see README), so it has no
/// fixed expectation.
bool get _supportsAvifOutput =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        _isAndroidWithAvif);

Object get _avifOutputSkip =>
    _skipUnless(_supportsAvifOutput, 'AVIF output is not expected to succeed');

bool get _isLinux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

/// `skip:` value: run when [condition] holds, otherwise skip with [reason].
Object _skipUnless(bool condition, String reason) => condition ? false : reason;

Object get _webpOutputSkip =>
    _skipUnless(_supportsWebpOutput, 'WebP output is not supported');

Object get _linuxOnlySkip => _skipUnless(_isLinux, 'Linux-specific behaviour');

/// The [OutputFormat] whose file signature [data] starts with, if any.
OutputFormat? _detectFormat(Uint8List data) {
  bool startsWith(int offset, List<int> signature) =>
      data.length >= offset + signature.length &&
      Iterable<int>.generate(
        signature.length,
      ).every((i) => data[offset + i] == signature[i]);

  if (startsWith(0, const [0xFF, 0xD8, 0xFF])) return OutputFormat.jpeg;
  if (startsWith(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return OutputFormat.png;
  }
  if (startsWith(0, 'RIFF'.codeUnits) && startsWith(8, 'WEBP'.codeUnits)) {
    return OutputFormat.webp;
  }
  // ISOBMFF `ftyp` box with the `avif` major brand.
  if (startsWith(4, 'ftyp'.codeUnits) && startsWith(8, 'avif'.codeUnits)) {
    return OutputFormat.avif;
  }
  return null;
}

/// Mean absolute RGB difference (0-255 scale) between [expected] and [actual],
/// which must have the same size, over a sparse grid of the pixels that are
/// fully opaque in [expected] (JPEG output flattens transparent pixels in a
/// backend-defined way).
double _meanRgbDiff(img.Image expected, img.Image actual) {
  expect(actual.width, expected.width);
  expect(actual.height, expected.height);
  final step =
      (expected.width < expected.height ? expected.width : expected.height) ~/
      32;
  var sum = 0.0;
  var count = 0;
  for (var y = 0; y < expected.height; y += step < 1 ? 1 : step) {
    for (var x = 0; x < expected.width; x += step < 1 ? 1 : step) {
      final e = expected.getPixel(x, y);
      if (e.aNormalized < 1) continue;
      final a = actual.getPixel(x, y);
      sum +=
          (e.rNormalized - a.rNormalized).abs() +
          (e.gNormalized - a.gNormalized).abs() +
          (e.bNormalized - a.bNormalized).abs();
      count += 3;
    }
  }
  expect(count, greaterThan(0), reason: 'no opaque pixels to compare');
  return sum / count * 255;
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
