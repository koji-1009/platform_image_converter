// Regenerate bindings with `dart run jnigen.dart`.
import 'package:jnigen/jnigen.dart';

final config = JniGenerator(
  input: Input(
    classes: [
      'java.io.ByteArrayOutputStream',
      'java.io.ByteArrayInputStream',
      'android/graphics/BitmapFactory',
      'android/graphics/Bitmap',
      'android/graphics/ImageDecoder',
      'android/graphics/Matrix',
      'android/media/ExifInterface',
      'android/media/Image',
      'android/media/MediaCodec',
      'android/media/MediaCodecInfo',
      'android/media/MediaCodecList',
      'android/media/MediaFormat',
      'android/media/MediaMuxer',
      'android/os/Build',
      'android/util/Range',
      'android/util/Size',
      'java.io.File',
    ],
    androidSdk: AndroidSdk(
      addGradleDeps: true,
      androidExample: Uri.directory('example'),
    ),
  ),
  output: Output(
    dart: DartOutput(
      path: Uri.file('lib/src/android/bindings.g.dart'),
      structure: OutputStructure.singleFile,
    ),
  ),
);

Future<void> main() => config.generate();
