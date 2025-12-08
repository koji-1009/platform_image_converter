// Regenerate bindings with `dart run ffigen.dart`.
import 'package:ffigen/ffigen.dart';

final config = FfiGenerator(
  headers: Headers(
    entryPoints: [
      Uri.file(
        '$macSdkPath/System/Library/Frameworks/ImageIO.framework/Headers/ImageIO.h',
      ),
    ],
  ),
  objectiveC: ObjectiveC(interfaces: Interfaces.includeSet({'ImageIO'})),
  output: Output(dartFile: Uri.file('lib/gen/darwin_bindings.dart')),
  functions: Functions.includeSet({
    // CFData operations
    'CFDataCreate',
    'CFDataCreateMutable',
    'CFDataGetBytePtr',
    'CFDataGetLength',
    // CGImageSource operations (decoding)
    'CGImageSourceCreateWithData',
    'CGImageSourceCreateImageAtIndex',
    // CGImageDestination operations (encoding)
    'CGImageDestinationCreateWithData',
    'CGImageDestinationAddImage',
    'CGImageDestinationFinalize',
  }),
  globals: Globals.includeSet({'kCFAllocatorDefault'}),
);

void main() => config.generate();
