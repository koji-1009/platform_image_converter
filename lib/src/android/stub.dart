import 'dart:typed_data';

import 'package:platform_image_converter/src/exif_orientation_policy.dart';
import 'package:platform_image_converter/src/image_converter_platform_interface.dart';
import 'package:platform_image_converter/src/output_format.dart';
import 'package:platform_image_converter/src/output_resize.dart';

final class ImageConverterAndroid implements ImageConverterPlatform {
  const ImageConverterAndroid();

  @override
  Uint8List convert({
    required Uint8List inputData,
    OutputFormat format = .jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
    ExifOrientationPolicy orientation = .apply,
  }) => throw UnimplementedError();
}
