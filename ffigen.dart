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
  output: Output(dartFile: Uri.file('lib/src/darwin/bindings.g.dart')),
  functions: Functions.includeSet({
    // CFData operations
    'CFDataCreate',
    'CFDataCreateMutable',
    'CFDataGetBytePtr',
    'CFDataGetLength',
    // CFDictionary operations
    'CFDictionaryCreate',
    // CGImageSource operations (decoding)
    'CGImageSourceCreateWithData',
    'CGImageSourceCreateImageAtIndex',
    // CGImageDestination operations (encoding)
    'CGImageDestinationCreateWithData',
    'CGImageDestinationAddImage',
    'CGImageDestinationFinalize',
    // Memory management
    'CFRelease',
  }),
  globals: Globals.includeSet({
    'kCFAllocatorDefault',
    'kCGImageDestinationLossyCompressionQuality',
    'kCFTypeDictionaryValueCallBacks',
    'kCFTypeDictionaryKeyCallBacks',
  }),
  typedefs: Typedefs.includeSet({
    'CFDataRef',
    'CFDictionaryRef',
    'CGImageRef',
    'CGImageSourceRef',
    'CFMutableDataRef',
    'CGImageDestinationRef',
  }),
);

void main() => config.generate();
