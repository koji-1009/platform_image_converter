import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:platform_image_converter/platform_image_converter.dart';

void main() {
  // A plain unit test for the quality guard — no widgets, no binding. It needs
  // `flutter test` rather than `dart test` only because ImageConverter imports
  // package:flutter. Quality is validated before any decoding or platform call,
  // so a single dummy byte exercises the guard.
  final dummy = Uint8List.fromList(const [0]);

  test('quality outside 1-100 throws ArgumentError', () async {
    await expectLater(
      ImageConverter.convert(inputData: dummy, quality: 0),
      throwsArgumentError,
    );
    await expectLater(
      ImageConverter.convert(inputData: dummy, quality: 101),
      throwsArgumentError,
    );
  });
}
