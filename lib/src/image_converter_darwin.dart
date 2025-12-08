import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image_ffi/gen/darwin_bindings.dart';
import 'package:image_ffi/src/image_converter_platform_interface.dart';
import 'package:image_ffi/src/output_format.dart';
import 'package:objective_c/objective_c.dart';

/// iOS/macOS image converter using ImageIO framework.
///
/// Implements image conversion for iOS 14+ and macOS 10.15+ platforms using
/// the native ImageIO framework through FFI bindings.
///
/// **Features:**
/// - Supports all major image formats (JPEG, PNG, HEIC, WebP, etc.)
/// - Uses CoreFoundation and CoreGraphics for efficient processing
/// - Memory-safe with proper resource cleanup
///
/// **API Stack:**
/// - `CGImageSourceCreateWithData`: Decode input image
/// - `CGImageSourceCreateImageAtIndex`: Extract CGImage
/// - `CGImageDestinationCreateWithData`: Create output stream
/// - `CGImageDestinationAddImage`: Add image with encoding options
/// - `CGImageDestinationFinalize`: Complete encoding
///
/// **Performance:**
/// - Direct FFI calls with minimal overhead
/// - In-memory processing
/// - Adjustable JPEG/WebP quality for size optimization
final class ImageConverterDarwin implements ImageConverterPlatform {
  @override
  Future<Uint8List> convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
  }) async {
    Pointer<Uint8>? inputPtr;
    CFDataRef? cfData;
    CGImageSourceRef? imageSource;
    CGImageRef? cgImage;
    CFMutableDataRef? outputData;
    CGImageDestinationRef? destination;
    CFDictionaryRef? properties;
    try {
      inputPtr = calloc<Uint8>(inputData.length);
      inputPtr.asTypedList(inputData.length).setAll(0, inputData);

      cfData = CFDataCreate(
        kCFAllocatorDefault,
        inputPtr.cast(),
        inputData.length,
      );
      if (cfData == nullptr) {
        throw Exception('Failed to create CFData from input data.');
      }

      imageSource = CGImageSourceCreateWithData(cfData, nullptr);
      if (imageSource == nullptr) {
        throw Exception('Failed to create CGImageSource. Invalid image data.');
      }

      cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nullptr);
      if (cgImage == nullptr) {
        throw Exception('Failed to decode image.');
      }

      outputData = CFDataCreateMutable(kCFAllocatorDefault, 0);
      if (outputData == nullptr) {
        throw Exception('Failed to create output CFData.');
      }

      final utiStr = switch (format) {
        // https://developer.apple.com/documentation/uniformtypeidentifiers/uttypejpeg
        OutputFormat.jpeg => 'public.jpeg',
        // https://developer.apple.com/documentation/uniformtypeidentifiers/uttypepng
        OutputFormat.png => 'public.png',
        // https://developer.apple.com/documentation/uniformtypeidentifiers/uttypeheic
        OutputFormat.heic => 'public.heic',
        // https://developer.apple.com/documentation/uniformtypeidentifiers/uttypewebp
        OutputFormat.webp => throw UnsupportedError(
          'WebP output format is not supported on iOS/macOS via ImageIO.',
        ),
      };
      final cfString = utiStr
          .toNSString()
          .ref
          .retainAndAutorelease()
          .cast<CFString>();

      destination = CGImageDestinationCreateWithData(
        outputData,
        cfString,
        1,
        nullptr,
      );
      if (destination == nullptr) {
        throw Exception('Failed to create CGImageDestination.');
      }

      properties = _createPropertiesForFormat(format, quality);
      CGImageDestinationAddImage(destination, cgImage, properties ?? nullptr);

      final success = CGImageDestinationFinalize(destination);
      if (!success) {
        throw Exception('Failed to finalize image encoding.');
      }

      final length = CFDataGetLength(outputData);
      final bytePtr = CFDataGetBytePtr(outputData);
      if (bytePtr == nullptr) {
        throw Exception('Failed to get output data bytes.');
      }

      return Uint8List.fromList(bytePtr.cast<Uint8>().asTypedList(length));
    } finally {
      if (inputPtr != null) calloc.free(inputPtr);
      if (cfData != null) CFRelease(cfData.cast());
      if (imageSource != null) CFRelease(imageSource.cast());
      if (cgImage != null) CFRelease(cgImage.cast());
      if (outputData != null) CFRelease(outputData.cast());
      if (destination != null) CFRelease(destination.cast());
      if (properties != null) CFRelease(properties.cast());
    }
  }

  CFDictionaryRef? _createPropertiesForFormat(
    OutputFormat format,
    int quality,
  ) {
    if (format == OutputFormat.png || format == OutputFormat.webp) {
      return null;
    }

    return using((arena) {
      final keys = arena<Pointer<CFString>>(1);
      final values = arena<Pointer<Void>>(1);

      keys[0] = kCGImageDestinationLossyCompressionQuality;
      values[0] = (quality / 100.0)
          .toNSNumber()
          .ref
          .retainAndAutorelease()
          .cast<Void>();

      final keyCallBacks = arena<CFDictionaryKeyCallBacks>();
      final valueCallBacks = arena<CFDictionaryValueCallBacks>();
      return CFDictionaryCreate(
        kCFAllocatorDefault,
        keys.cast(),
        values.cast(),
        1,
        keyCallBacks,
        valueCallBacks,
      );
    });
  }
}
