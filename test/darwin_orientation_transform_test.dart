import 'package:flutter_test/flutter_test.dart';
import 'package:platform_image_converter/src/darwin/native.dart';

void main() {
  // `orientationTransform` is pure math returning a managed `CGAffineTransform`
  // (no native call), so it runs on the host unit-test runner. It pins the
  // CoreGraphics CTM that bakes each EXIF orientation while scaling the raw image
  // onto the oriented output box. The integration test validates the resulting
  // pixels against an oracle; this fixes the matrix itself so a refactor cannot
  // silently change it. raw is a non-square 64x32 so the axis swap of the 90/270
  // rotations (orientations 5-8) is observable.
  const converter = ImageConverterDarwin();
  const rawW = 64;
  const rawH = 32;

  // (orientation, outW, outH, [a, b, c, d, tx, ty]). Orientations 1-4 keep the
  // raw dimensions; the axis-swapping 5-8 receive swapped output dimensions
  // (as the real caller does), so the transform fills the oriented box exactly.
  const cases = <(int, int, int, List<double>)>[
    (1, 64, 32, [1, 0, 0, 1, 0, 0]),
    (2, 64, 32, [-1, 0, 0, 1, 64, 0]),
    (3, 64, 32, [-1, 0, 0, -1, 64, 32]),
    (4, 64, 32, [1, 0, 0, -1, 0, 32]),
    (5, 32, 64, [0, -1, -1, 0, 32, 64]),
    (6, 32, 64, [0, -1, 1, 0, 0, 64]),
    (7, 32, 64, [0, 1, 1, 0, 0, 0]),
    (8, 32, 64, [0, 1, -1, 0, 32, 0]),
  ];

  for (final (orientation, outW, outH, e) in cases) {
    test('orientation $orientation builds its oriented, box-filling CTM', () {
      final t = converter.orientationTransform(
        orientation,
        rawW,
        rawH,
        outW,
        outH,
      );
      expect(t.a, closeTo(e[0], 1e-9), reason: 'a');
      expect(t.b, closeTo(e[1], 1e-9), reason: 'b');
      expect(t.c, closeTo(e[2], 1e-9), reason: 'c');
      expect(t.d, closeTo(e[3], 1e-9), reason: 'd');
      expect(t.tx, closeTo(e[4], 1e-9), reason: 'tx');
      expect(t.ty, closeTo(e[5], 1e-9), reason: 'ty');
    });
  }

  test('an unmapped orientation falls back to identity', () {
    final t = converter.orientationTransform(99, rawW, rawH, rawW, rawH);
    expect(t.a, closeTo(1, 1e-9));
    expect(t.b, closeTo(0, 1e-9));
    expect(t.c, closeTo(0, 1e-9));
    expect(t.d, closeTo(1, 1e-9));
    expect(t.tx, closeTo(0, 1e-9));
    expect(t.ty, closeTo(0, 1e-9));
  });

  test('a downscale folds the scale into the orientation CTM', () {
    // Orientation 1 with the output halved: the identity linear part is scaled
    // by 0.5 on both axes, with no translation.
    final t = converter.orientationTransform(1, rawW, rawH, 32, 16);
    expect(t.a, closeTo(0.5, 1e-9));
    expect(t.d, closeTo(0.5, 1e-9));
    expect(t.tx, closeTo(0, 1e-9));
    expect(t.ty, closeTo(0, 1e-9));
  });
}
