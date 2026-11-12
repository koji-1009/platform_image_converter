// Regenerate bindings with `dart run ffigen.dart`.
import 'package:ffigen/ffigen.dart';

/// Local definitions for the Apple "common" types (CFString, CGRect, ...) that
/// ffigen's built-in type table would otherwise source from package:objective_c.
const _appleTypes = LibraryImport(
  'appleCf',
  'package:platform_image_converter/src/darwin/apple_cf_types.dart',
);

/// USR -> Dart name of the Apple common types defined in [_appleTypes].
const _appleTypesByUsr = {
  'c:@S@__CFString': ('CFString', '__CFString'),
  'c:@S@CGRect': ('CGRect', 'CGRect'),
  'c:@S@CGAffineTransform': ('CGAffineTransform', 'CGAffineTransform'),
};

const _functions = {
  // CFData operations
  'CFDataCreate',
  'CFDataCreateMutable',
  'CFDataGetBytePtr',
  'CFDataGetLength',
  // CFDictionary operations
  'CFDictionaryCreate',
  'CFDictionaryGetValue',
  // CFString / CFNumber value creation (replaces objective_c NSString/NSNumber)
  'CFStringCreateWithCString',
  'CFNumberCreate',
  'CFNumberGetValue',
  // CGImageSource operations (decoding)
  'CGImageSourceCreateWithData',
  'CGImageSourceCreateImageAtIndex',
  // EXIF orientation lookup from the source's properties
  'CGImageSourceCopyPropertiesAtIndex',
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
  'CGContextConcatCTM',
  // CGBitmapContext operations
  'CGBitmapContextCreateImage',
  'CGBitmapContextCreate',
  // Memory management
  'CFRelease',
};

const _globals = {
  'kCFAllocatorDefault',
  'kCGImageDestinationLossyCompressionQuality',
  'kCGColorSpaceSRGB',
  'kCGImagePropertyOrientation',
};

// The CF/CG enum constants used are surfaced as top-level `const int`s via
// unnamed enum constants (their named enums are not emitted as Dart enums in
// C mode).
const _unnamedEnumConstants = {
  'kCFStringEncodingUTF8',
  'kCFNumberFloat64Type',
  'kCFNumberIntType',
  'kCGImageAlphaPremultipliedLast',
  'kCGInterpolationHigh',
};

const _typedefs = {
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
};

final config = FfiGenerator(
  input: Input(
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
  output: Output(
    dart: DartOutput(path: Uri.file('lib/src/darwin/bindings.g.dart')),
  ),
  // Override ffigen's built-in objective_c mapping for the Apple common types,
  // pointing them at local definitions so the bindings carry no objective_c dep.
  importType: (declaration) {
    final names = _appleTypesByUsr[declaration.usr];
    if (names == null) return null;
    final (dartName, nativeName) = names;
    return ImportedType(
      _appleTypes,
      dartName,
      dartName,
      nativeName,
      importedDartType: true,
    );
  },
  visitors: [
    Visitor(
      func: (node) => node.isIncluded = _functions.contains(node.originalName),
      global: (node) => node.isIncluded = _globals.contains(node.originalName),
      unnamedEnumConstant: (node) =>
          node.isIncluded = _unnamedEnumConstants.contains(node.originalName),
      typealias: (node) =>
          node.isIncluded = _typedefs.contains(node.originalName)
          ? TypealiasInclude.ifUsed
          : TypealiasInclude.never,
    ),
  ],
);

Future<void> main() => config.generate();
