import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:objective_c/objective_c.dart';
import 'package:platform_image_converter/src/darwin/bindings.g.dart';
import 'package:platform_image_converter/src/image_conversion_exception.dart';
import 'package:platform_image_converter/src/image_converter_platform_interface.dart';
import 'package:platform_image_converter/src/output_format.dart';
import 'package:platform_image_converter/src/output_resize.dart';

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
/// - `CGBitmapContextCreate`: Create a canvas for resizing
/// - `CGContextDrawImage`: Draw and scale the image
/// - `CGBitmapContextCreateImage`: Extract resized CGImage
/// - `CGImageDestinationCreateWithData`: Create output stream
/// - `CGImageDestinationAddImage`: Add image with encoding options
/// - `CGImageDestinationFinalize`: Complete encoding
///
/// **Performance:**
/// - Direct FFI calls with minimal overhead
/// - In-memory processing
/// - Adjustable JPEG/WebP quality for size optimization
final class ImageConverterDarwin implements ImageConverterPlatform {
  const ImageConverterDarwin();

  @override
  Uint8List convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
  }) {
    Pointer<Uint8>? inputPtr;
    CFDataRef? cfData;
    CGImageSourceRef? imageSource;
    CGImageRef? originalImage;
    CGImageRef? imageToEncode;
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
        throw const ImageConversionException(
          'Failed to create CFData from input data.',
        );
      }

      imageSource = CGImageSourceCreateWithData(cfData, nullptr);
      if (imageSource == nullptr) {
        throw const ImageDecodingException('Invalid image data.');
      }

      originalImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nullptr);
      if (originalImage == nullptr) {
        throw const ImageDecodingException();
      }

      final originalWidth = CGImageGetWidth(originalImage);
      final originalHeight = CGImageGetHeight(originalImage);
      final (newWidth, newHeight) = resizeMode.calculateSize(
        originalWidth,
        originalHeight,
      );

      if (newWidth == originalWidth && newHeight == originalHeight) {
        imageToEncode = originalImage;
      } else {
        imageToEncode = _resizeImage(originalImage, newWidth, newHeight);
      }

      if (imageToEncode == nullptr) {
        throw const ImageConversionException(
          'Failed to prepare image for encoding. Resizing may have failed.',
        );
      }

      outputData = CFDataCreateMutable(kCFAllocatorDefault, 0);
      if (outputData == nullptr) {
        throw ImageEncodingException(format, 'Failed to create output CFData.');
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
        throw ImageEncodingException(
          format,
          'Failed to create CGImageDestination.',
        );
      }

      properties = _createPropertiesForFormat(format, quality);
      CGImageDestinationAddImage(
        destination,
        imageToEncode,
        properties ?? nullptr,
      );

      final success = CGImageDestinationFinalize(destination);
      if (!success) {
        throw ImageEncodingException(
          format,
          'Failed to finalize image encoding.',
        );
      }

      final length = CFDataGetLength(outputData);
      final bytePtr = CFDataGetBytePtr(outputData);
      if (bytePtr == nullptr) {
        throw ImageEncodingException(
          format,
          'Failed to get output data bytes.',
        );
      }

      return Uint8List.fromList(bytePtr.cast<Uint8>().asTypedList(length));
    } finally {
      if (inputPtr != null) calloc.free(inputPtr);
      if (cfData != null) CFRelease(cfData.cast());
      if (imageSource != null) CFRelease(imageSource.cast());
      if (imageToEncode != null && imageToEncode != originalImage) {
        CFRelease(imageToEncode.cast());
      }
      if (originalImage != null) CFRelease(originalImage.cast());
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

  CGImageRef _resizeImage(CGImageRef originalImage, int width, int height) {
    CGContextRef? context;
    try {
      final colorSpace = CGImageGetColorSpace(originalImage);
      if (colorSpace == nullptr) {
        throw const ImageConversionException(
          'Failed to get color space from image for resizing.',
        );
      }

      final bitsPerComponent = CGImageGetBitsPerComponent(originalImage);
      final bitmapInfo = CGImageGetBitmapInfo(originalImage);

      context = CGBitmapContextCreate(
        nullptr,
        width,
        height,
        bitsPerComponent,
        0, // bytesPerRow (0 means calculate automatically)
        colorSpace,
        bitmapInfo,
      );
      if (context == nullptr) {
        throw const ImageConversionException(
          'Failed to create bitmap context for resizing.',
        );
      }

      CGContextSetInterpolationQuality(
        context,
        CGInterpolationQuality.kCGInterpolationHigh,
      );

      final rect = Struct.create<CGRect>()
        ..origin.x = 0
        ..origin.y = 0
        ..size.width = width.toDouble()
        ..size.height = height.toDouble();

      CGContextDrawImage(context, rect, originalImage);

      final resizedImage = CGBitmapContextCreateImage(context);
      if (resizedImage == nullptr) {
        throw const ImageConversionException(
          'Failed to create resized image from context.',
        );
      }
      return resizedImage;
    } finally {
      if (context != null) CFRelease(context.cast());
    }
  }
}
