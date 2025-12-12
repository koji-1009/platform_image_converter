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
}
