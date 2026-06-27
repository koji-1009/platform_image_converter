import 'package:flutter_test/flutter_test.dart';
import 'package:platform_image_converter/src/output_resize.dart';

void main() {
  group('ResizeMode', () {
    const originalWidth = 1000;
    const originalHeight = 500;

    group('OriginalResizeMode', () {
      test('should return original dimensions', () {
        const resizeMode = OriginalResizeMode();
        final (width, height) = resizeMode.calculateSize(
          originalWidth,
          originalHeight,
        );
        expect(width, originalWidth);
        expect(height, originalHeight);
      });
    });

    group('ExactResizeMode', () {
      test('should return exact dimensions', () {
        const resizeMode = ExactResizeMode(width: 300, height: 200);
        final (width, height) = resizeMode.calculateSize(
          originalWidth,
          originalHeight,
        );
        expect(width, 300);
        expect(height, 200);
      });
    });

    group('FitResizeMode', () {
      test('downscales with both width and height, respecting aspect ratio', () {
        // Aspect ratio is 2:1 (1000x500)
        // Target is 500x500, so scale should be based on width (min(500/1000, 500/500) = 0.5)
        const resizeMode = FitResizeMode(width: 500, height: 500);
        final (width, height) = resizeMode.calculateSize(
          originalWidth,
          originalHeight,
        );
        expect(width, 500); // 1000 * 0.5
        expect(height, 250); // 500 * 0.5
      });

      test('does not upscale if image is smaller than target dimensions', () {
        const resizeMode = FitResizeMode(width: 2000, height: 1000);
        final (width, height) = resizeMode.calculateSize(
          originalWidth,
          originalHeight,
        );
        expect(width, originalWidth);
        expect(height, originalHeight);
      });

      test('downscales with only width, respecting aspect ratio', () {
        const resizeMode = FitResizeMode(width: 500);
        final (width, height) = resizeMode.calculateSize(
          originalWidth,
          originalHeight,
        );
        expect(width, 500); // 1000 * 0.5
        expect(height, 250); // 500 * 0.5
      });

      test('does not upscale with only width', () {
        const resizeMode = FitResizeMode(width: 2000);
        final (width, height) = resizeMode.calculateSize(
          originalWidth,
          originalHeight,
        );
        expect(width, originalWidth);
        expect(height, originalHeight);
      });

      test('downscales with only height, respecting aspect ratio', () {
        const resizeMode = FitResizeMode(height: 250);
        final (width, height) = resizeMode.calculateSize(
          originalWidth,
          originalHeight,
        );
        expect(width, 500); // 1000 * 0.5
        expect(height, 250); // 500 * 0.5
      });

      test('does not upscale with only height', () {
        const resizeMode = FitResizeMode(height: 1000);
        final (width, height) = resizeMode.calculateSize(
          originalWidth,
          originalHeight,
        );
        expect(width, originalWidth);
        expect(height, originalHeight);
      });
    });
  });

  group('Edge cases', () {
    test('handles 1x1 image', () {
      const originalWidth = 1;
      const originalHeight = 1;

      const resizeMode = FitResizeMode(width: 10, height: 10);
      final (width, height) = resizeMode.calculateSize(
        originalWidth,
        originalHeight,
      );
      expect(width, originalWidth);
      expect(height, originalHeight);
    });

    test('handles very large images', () {
      const originalWidth = 10000;
      const originalHeight = 5000;

      const resizeMode = FitResizeMode(width: 100);
      final (width, height) = resizeMode.calculateSize(
        originalWidth,
        originalHeight,
      );
      expect(width, 100);
      expect(height, 50);
    });

    test('ExactResizeMode rejects non-positive dimensions', () {
      expect(
        () => ExactResizeMode(width: 0, height: 10),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ExactResizeMode(width: 10, height: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('FitResizeMode rejects non-positive dimensions', () {
      expect(() => FitResizeMode(width: 0), throwsA(isA<AssertionError>()));
      expect(() => FitResizeMode(height: -5), throwsA(isA<AssertionError>()));
    });

    // An extreme aspect ratio rounds one side down to round(3 * 5 / 4000) == 0,
    // which the native encoders reject. calculateSize clamps each dimension
    // independently, so both the height side and the symmetric width side must
    // come back as 1.
    const clampCases = [
      (
        side: 'height',
        mode: FitResizeMode(width: 5),
        w: 4000,
        h: 3,
        expW: 5,
        expH: 1,
      ),
      (
        side: 'width',
        mode: FitResizeMode(height: 5),
        w: 3,
        h: 4000,
        expW: 1,
        expH: 5,
      ),
    ];
    for (final c in clampCases) {
      test('FitResizeMode clamps a rounded-to-zero ${c.side} up to 1', () {
        final (width, height) = c.mode.calculateSize(c.w, c.h);
        expect(width, c.expW);
        expect(height, c.expH);
      });
    }
  });
}
