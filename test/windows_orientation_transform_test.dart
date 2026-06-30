import 'package:flutter_test/flutter_test.dart';
import 'package:platform_image_converter/src/windows/native.dart';

void main() {
  // `orientationTransform` is a pure mapping (no native/COM call), so it runs on
  // the host unit-test runner even though the rest of the Windows backend needs
  // WIC. Pins the EXIF-orientation -> WICBitmapTransformOptions mapping so a
  // regression (e.g. swapping the transpose/transverse pair) is caught without a
  // Windows machine. The per-bit constants below are from wincodec.h: rotations
  // occupy the low two bits, the two flips are independent flag bits.
  const rotate0 = 0x0;
  const rotate90 = 0x1;
  const rotate180 = 0x2;
  const rotate270 = 0x3;
  const flipHorizontal = 0x8;
  const flipVertical = 0x10;

  const converter = ImageConverterWindows();

  const expected = <int, int>{
    1: rotate0,
    2: flipHorizontal,
    3: rotate180,
    4: flipVertical,
    5: flipHorizontal | rotate270,
    6: rotate90,
    7: flipHorizontal | rotate90,
    8: rotate270,
  };

  expected.forEach((orientation, options) {
    test('orientation $orientation maps to its WIC transform options', () {
      expect(converter.orientationTransform(orientation), options);
    });
  });

  for (final invalid in const [0, 9, -1, 100]) {
    test('out-of-range orientation $invalid falls back to Rotate0', () {
      expect(converter.orientationTransform(invalid), rotate0);
    });
  }
}
