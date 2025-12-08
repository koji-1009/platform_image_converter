import 'dart:typed_data';

import 'package:image_ffi/src/image_converter_platform_interface.dart';
import 'package:image_ffi/src/output_format.dart';

final class ImageConverterAndroid implements ImageConverterPlatform {
  const ImageConverterAndroid();

  @override
  Future<Uint8List> convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
  }) async => throw UnimplementedError();
}
