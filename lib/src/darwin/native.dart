import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:objective_c/objective_c.dart';
import 'package:platform_image_converter/src/darwin/bindings.g.dart';
import 'package:platform_image_converter/src/image_conversion_exception.dart';
import 'package:platform_image_converter/src/image_converter_platform_interface.dart';
import 'package:platform_image_converter/src/output_format.dart';
import 'package:platform_image_converter/src/output_resize.dart';

extension on Pointer<Opaque> {
  /// Registers this CoreFoundation object to be released with `CFRelease` when
  /// [arena] is released, mirroring the Android backend's `releasedBy`. Skips
  /// `nullptr` because `CFRelease(NULL)` is a fatal error.
  void releasedBy(Arena arena) {
    if (this != nullptr) arena.onReleaseAll(() => CFRelease(cast<Void>()));
  }
}

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
    return using((arena) {
      final inputPtr = arena<Uint8>(inputData.length);
      inputPtr.asTypedList(inputData.length).setAll(0, inputData);

      final cfData = CFDataCreate(
        kCFAllocatorDefault,
        inputPtr.cast(),
        inputData.length,
      )..releasedBy(arena);
      if (cfData == nullptr) {
        throw const ImageConversionException(
          'Failed to create CFData from input data.',
        );
      }

      final imageSource = CGImageSourceCreateWithData(cfData, nullptr)
        ..releasedBy(arena);
      if (imageSource == nullptr) {
        throw const ImageDecodingException('Invalid image data.');
      }

      final originalImage = CGImageSourceCreateImageAtIndex(
        imageSource,
        0,
        nullptr,
      )..releasedBy(arena);
      if (originalImage == nullptr) {
        throw const ImageDecodingException();
      }

      final originalWidth = CGImageGetWidth(originalImage);
      final originalHeight = CGImageGetHeight(originalImage);
      final (newWidth, newHeight) = resizeMode.calculateSize(
        originalWidth,
        originalHeight,
      );

      // Always render through the sRGB context (even at the original size) so
      // output is independent of whether a resize happened, matching the
      // Android/Web backends which always produce 8-bit sRGB.
      final imageToEncode = _renderToSRGB(
        arena,
        originalImage,
        newWidth,
        newHeight,
      );

      final outputData = CFDataCreateMutable(kCFAllocatorDefault, 0)
        ..releasedBy(arena);
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

      final destination = CGImageDestinationCreateWithData(
        outputData,
        cfString,
        1,
        nullptr,
      )..releasedBy(arena);
      if (destination == nullptr) {
        throw ImageEncodingException(
          format,
          'Failed to create CGImageDestination.',
        );
      }

      final properties = _createPropertiesForFormat(format, quality)
        ?..releasedBy(arena);
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
    });
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

  /// Draws [originalImage] into a fixed 8-bpc sRGB premultiplied-RGBA context at
  /// [width]x[height], normalizing any source format (16-bpc / grayscale / CMYK
  /// / indexed sources otherwise make CGBitmapContextCreate return NULL) and
  /// scaling in the same pass. Output is always 8-bit sRGB.
  ///
  /// The returned image is registered in [arena]; it is released when [arena]
  /// is released, so callers must not release it themselves.
  CGImageRef _renderToSRGB(
    Arena arena,
    CGImageRef originalImage,
    int width,
    int height,
  ) {
    final colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB)
      ..releasedBy(arena);
    if (colorSpace == nullptr) {
      throw const ImageConversionException(
        'Failed to create sRGB color space for resizing.',
      );
    }

    final context = CGBitmapContextCreate(
      nullptr,
      width,
      height,
      8, // bitsPerComponent
      0, // bytesPerRow (0 means calculate automatically)
      colorSpace,
      CGImageAlphaInfo.kCGImageAlphaPremultipliedLast.value,
    )..releasedBy(arena);
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

    final resizedImage = CGBitmapContextCreateImage(context)..releasedBy(arena);
    if (resizedImage == nullptr) {
      throw const ImageConversionException(
        'Failed to create resized image from context.',
      );
    }
    return resizedImage;
  }
}
