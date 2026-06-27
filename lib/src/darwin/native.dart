import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:platform_image_converter/src/darwin/apple_cf_types.dart';
import 'package:platform_image_converter/src/darwin/bindings.g.dart';
import 'package:platform_image_converter/src/exif_orientation_policy.dart';
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
    OutputFormat format = .jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
    ExifOrientationPolicy orientation = .apply,
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

      final rawWidth = CGImageGetWidth(originalImage);
      final rawHeight = CGImageGetHeight(originalImage);

      // EXIF orientation: 1 (no transform) when ignoring it or when absent.
      final exifOrientation = orientation == .apply
          ? _readOrientation(arena, imageSource)
          : 1;

      // Orientations 5-8 are 90/270 degree rotations, which swap the displayed
      // width and height relative to the decoded buffer. Evaluate the resize
      // against the oriented (display) dimensions so the request is intuitive.
      final swapsAxes = exifOrientation >= 5 && exifOrientation <= 8;
      final displayWidth = swapsAxes ? rawHeight : rawWidth;
      final displayHeight = swapsAxes ? rawWidth : rawHeight;
      final (newWidth, newHeight) = resizeMode.calculateSize(
        displayWidth,
        displayHeight,
      );

      // Always render through the sRGB context (even at the original size) so
      // output is independent of whether a resize happened, matching the
      // Android/Web backends which always produce 8-bit sRGB.
      final imageToEncode = _renderToSRGB(
        arena,
        originalImage,
        rawWidth,
        rawHeight,
        newWidth,
        newHeight,
        exifOrientation,
      );

      final outputData = CFDataCreateMutable(kCFAllocatorDefault, 0)
        ..releasedBy(arena);
      if (outputData == nullptr) {
        throw ImageEncodingException(format, 'Failed to create output CFData.');
      }

      final utiStr = switch (format) {
        // https://developer.apple.com/documentation/uniformtypeidentifiers/uttypejpeg
        .jpeg => 'public.jpeg',
        // https://developer.apple.com/documentation/uniformtypeidentifiers/uttypepng
        .png => 'public.png',
        // https://developer.apple.com/documentation/uniformtypeidentifiers/uttypeheic
        .heic => 'public.heic',
        // https://developer.apple.com/documentation/uniformtypeidentifiers/uttypewebp
        .webp => throw UnsupportedFormatException(
          format,
          .platformUnsupported,
          'WebP output is not supported on iOS/macOS via ImageIO.',
        ),
      };
      final cfString = CFStringCreateWithCString(
        kCFAllocatorDefault,
        utiStr.toNativeUtf8(allocator: arena).cast(),
        kCFStringEncodingUTF8,
      )..releasedBy(arena);
      if (cfString == nullptr) {
        throw ImageEncodingException(format, 'Failed to create UTI string.');
      }

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

      final properties = _createPropertiesForFormat(arena, format, quality);
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

  /// Builds the encoding options dictionary, or `null` for formats without
  /// options (PNG/WebP). Both the dictionary and its quality [CFNumberRef] are
  /// registered in [arena] (the caller's), so they are released when it drains —
  /// after the dictionary's use during encoding.
  CFDictionaryRef? _createPropertiesForFormat(
    Arena arena,
    OutputFormat format,
    int quality,
  ) {
    // PNG is lossless and WebP is unsupported on this backend; neither carries
    // a lossy compression-quality dictionary. Exhaustive over OutputFormat so a
    // future format forces a decision here instead of silently being treated as
    // lossy.
    switch (format) {
      case .png || .webp:
        return null;
      case .jpeg || .heic:
        break;
    }

    final keys = arena<CFStringRef>(1);
    final values = arena<Pointer<Void>>(1);

    keys[0] = kCGImageDestinationLossyCompressionQuality;

    final qualityPtr = arena<Double>()..value = quality / 100.0;
    final number = CFNumberCreate(
      kCFAllocatorDefault,
      kCFNumberFloat64Type,
      qualityPtr.cast(),
    )..releasedBy(arena);
    if (number == nullptr) {
      throw ImageEncodingException(format, 'Failed to create quality value.');
    }
    values[0] = number.cast<Void>();

    // Null callbacks: the dictionary neither retains nor releases its key/value
    // (their lifetimes are managed by the arena). Register the dictionary in the
    // arena too, beside its CFNumber — `releasedBy` skips a nullptr, so a failed
    // create is still returned for the caller's null check.
    return CFDictionaryCreate(
      kCFAllocatorDefault,
      keys.cast(),
      values.cast(),
      1,
      nullptr,
      nullptr,
    )..releasedBy(arena);
  }

  /// Draws [originalImage] into a fixed 8-bpc sRGB premultiplied-RGBA context
  /// sized [width]x[height] (the oriented, resized output), normalizing any
  /// source format (16-bpc / grayscale / CMYK / indexed sources otherwise make
  /// CGBitmapContextCreate return NULL), applying the [exifOrientation]
  /// transform, and scaling — all in the same pass. Output is always 8-bit sRGB.
  ///
  /// [rawWidth]/[rawHeight] are the decoded buffer's dimensions; the image is
  /// drawn at that size and the CTM maps it onto the oriented output box.
  ///
  /// The returned image is registered in [arena]; it is released when [arena]
  /// is released, so callers must not release it themselves.
  CGImageRef _renderToSRGB(
    Arena arena,
    CGImageRef originalImage,
    int rawWidth,
    int rawHeight,
    int width,
    int height,
    int exifOrientation,
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
      kCGImageAlphaPremultipliedLast,
    )..releasedBy(arena);
    if (context == nullptr) {
      throw const ImageConversionException(
        'Failed to create bitmap context for resizing.',
      );
    }

    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);

    // Concatenate scale-then-orient so the raw image, drawn at its own size,
    // lands upright and resized in the oriented output box. Identity for
    // orientation 1, so the non-oriented path is unchanged.
    CGContextConcatCTM(
      context,
      _orientationTransform(
        exifOrientation,
        rawWidth,
        rawHeight,
        width,
        height,
      ),
    );

    final rect = Struct.create<CGRect>()
      ..origin.x = 0
      ..origin.y = 0
      ..size.width = rawWidth.toDouble()
      ..size.height = rawHeight.toDouble();

    CGContextDrawImage(context, rect, originalImage);

    final resizedImage = CGBitmapContextCreateImage(context)..releasedBy(arena);
    if (resizedImage == nullptr) {
      throw const ImageConversionException(
        'Failed to create resized image from context.',
      );
    }
    return resizedImage;
  }

  /// Reads the EXIF orientation (1-8) from the image source's properties,
  /// returning 1 when absent or unreadable. The copied properties dictionary is
  /// owned and registered in [arena]; the value fetched from it is borrowed.
  int _readOrientation(Arena arena, CGImageSourceRef imageSource) {
    final props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nullptr)
      ..releasedBy(arena);
    if (props == nullptr) {
      return 1;
    }
    final value = CFDictionaryGetValue(
      props,
      kCGImagePropertyOrientation.cast(),
    );
    if (value == nullptr) {
      return 1;
    }
    final out = arena<Int32>();
    final ok = CFNumberGetValue(value.cast(), kCFNumberIntType, out.cast());
    if (ok == 0) {
      return 1;
    }
    final orientation = out.value;
    return (orientation >= 1 && orientation <= 8) ? orientation : 1;
  }

  /// Builds the `CGAffineTransform` that maps the raw [rawWidth]x[rawHeight]
  /// image onto the [outWidth]x[outHeight] oriented output box for the given
  /// EXIF [orientation] (1-8). The transform composes the orientation's
  /// rotation/mirror with the scale to the output size.
  ///
  /// The orientation's linear part is `(x, y) -> (a0*x + c0*y, b0*x + d0*y)` in
  /// the context's bottom-left, y-up space (identity reproduces the input). The
  /// four corners of the raw box are mapped to find the translation that seats
  /// the result in the positive quadrant; the scale to the output is folded in.
  CGAffineTransform _orientationTransform(
    int orientation,
    int rawWidth,
    int rawHeight,
    int outWidth,
    int outHeight,
  ) {
    // Linear part per EXIF orientation: [a0 (x<-x), c0 (x<-y), b0 (y<-x),
    // d0 (y<-y)]. 1 none, 2 flipH, 3 rot180, 4 flipV, 5 transpose,
    // 6 rotate 90 CW, 7 transverse, 8 rotate 90 CCW.
    final (a0, c0, b0, d0) = switch (orientation) {
      2 => (-1, 0, 0, 1),
      3 => (-1, 0, 0, -1),
      4 => (1, 0, 0, -1),
      5 => (0, -1, -1, 0),
      6 => (0, 1, -1, 0),
      7 => (0, 1, 1, 0),
      8 => (0, -1, 1, 0),
      _ => (1, 0, 0, 1), // 1 and any unexpected value
    };

    final w = rawWidth.toDouble();
    final h = rawHeight.toDouble();
    // Map the four corners through the linear part to find the bounding box.
    final xs = [0.0, a0 * w, c0 * h, a0 * w + c0 * h];
    final ys = [0.0, b0 * w, d0 * h, b0 * w + d0 * h];
    final minX = xs.reduce((p, q) => p < q ? p : q);
    final minY = ys.reduce((p, q) => p < q ? p : q);
    final maxX = xs.reduce((p, q) => p > q ? p : q);
    final maxY = ys.reduce((p, q) => p > q ? p : q);

    // Scale the oriented full-res box (maxX-minX) x (maxY-minY) to the output.
    final sx = outWidth / (maxX - minX);
    final sy = outHeight / (maxY - minY);

    return Struct.create<CGAffineTransform>()
      ..a = sx * a0
      ..b = sy * b0
      ..c = sx * c0
      ..d = sy * d0
      ..tx = sx * -minX
      ..ty = sy * -minY;
  }
}
