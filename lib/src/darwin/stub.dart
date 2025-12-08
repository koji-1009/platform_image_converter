import 'dart:typed_data';

import 'package:platform_image_converter/src/image_converter_platform_interface.dart';
import 'package:platform_image_converter/src/output_format.dart';

final class ImageConverterDarwin implements ImageConverterPlatform {
  const ImageConverterDarwin();

  @override
  Future<Uint8List> convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
  }) async => throw UnimplementedError();
}
