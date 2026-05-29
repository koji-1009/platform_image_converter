// Regenerate bindings with `dart run ffigen.dart`.
import 'package:ffigen/ffigen.dart';

/// Local definitions for the Apple "common" types (CFString, CGRect, ...) that
/// ffigen's built-in type table would otherwise source from package:objective_c.
const _appleTypes = LibraryImport(
  'appleCf',
  'package:platform_image_converter/src/darwin/apple_cf_types.dart',
);

final config = FfiGenerator(
  headers: Headers(
    entryPoints: [
      Uri.file(
        '$macSdkPath/System/Library/Frameworks/ImageIO.framework/Headers/ImageIO.h',
      ),
    ],
    // Generate for C only (no objective_c interop). Pass the framework search
    // path and sysroot that ObjC mode would otherwise supply so the framework
    // umbrella headers resolve.
    compilerOptions: [
      '-isysroot',
      macSdkPath,
      '-F',
      '$macSdkPath/System/Library/Frameworks',
    ],
  ),
  output: Output(dartFile: Uri.file('lib/src/darwin/bindings.g.dart')),
  // Override ffigen's built-in objective_c mapping for the Apple common types,
  // pointing them at local definitions so the bindings carry no objective_c dep.
  // ignore: deprecated_member_use
  libraryImports: const [_appleTypes],
  // ignore: deprecated_member_use
  importedTypesByUsr: {
    'c:@S@__CFString': ImportedType(
      _appleTypes,
      'CFString',
      'CFString',
      '__CFString',
      importedDartType: true,
    ),
    'c:@S@CGRect': ImportedType(
      _appleTypes,
      'CGRect',
      'CGRect',
      'CGRect',
      importedDartType: true,
    ),
  },
  functions: Functions.includeSet({
    // CFData operations
    'CFDataCreate',
    'CFDataCreateMutable',
    'CFDataGetBytePtr',
    'CFDataGetLength',
    // CFDictionary operations
    'CFDictionaryCreate',
    // CFString / CFNumber value creation (replaces objective_c NSString/NSNumber)
    'CFStringCreateWithCString',
    'CFNumberCreate',
    // CGImageSource operations (decoding)
    'CGImageSourceCreateWithData',
    'CGImageSourceCreateImageAtIndex',
    // CGImageDestination operations (encoding)
    'CGImageDestinationCreateWithData',
    'CGImageDestinationAddImage',
    'CGImageDestinationFinalize',
    // CGImage operations
    'CGImageGetWidth',
    'CGImageGetHeight',
    // CGColorSpace operations
    'CGColorSpaceCreateWithName',
    // CGContext operations
    'CGContextDrawImage',
    'CGContextSetInterpolationQuality',
    // CGBitmapContext operations
    'CGBitmapContextCreateImage',
    'CGBitmapContextCreate',
    // Memory management
    'CFRelease',
  }),
  globals: Globals.includeSet({
    'kCFAllocatorDefault',
    'kCGImageDestinationLossyCompressionQuality',
    'kCGColorSpaceSRGB',
  }),
  // The CF/CG enum constants used are surfaced as top-level `const int`s via
  // unnamedEnums (their named enums are not emitted as Dart enums in C mode).
  unnamedEnums: UnnamedEnums.includeSet({
    'kCFStringEncodingUTF8',
    'kCFNumberFloat64Type',
    'kCGImageAlphaPremultipliedLast',
    'kCGInterpolationHigh',
  }),
  typedefs: Typedefs.includeSet({
    'CFDataRef',
    'CFDictionaryRef',
    'CGContextRef',
    'CGImageRef',
    'CGImageSourceRef',
    'CGColorSpaceRef',
    'CFMutableDataRef',
    'CGImageDestinationRef',
    'CFStringRef',
    'CFNumberRef',
  }),
);

void main() => config.generate();
