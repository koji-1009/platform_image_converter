import 'dart:typed_data';

import 'package:platform_image_converter/platform_image_converter.dart';
import 'package:platform_image_converter/src/image_converter_platform_interface.dart';

final class ImageConverterAndroid implements ImageConverterPlatform {
  const ImageConverterAndroid();

  @override
  Uint8List convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
  }) => throw UnimplementedError();
}
