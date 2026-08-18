import 'dart:typed_data';

import 'package:jni/jni.dart';
import 'package:platform_image_converter/src/android/bindings.g.dart';
import 'package:platform_image_converter/src/exif_orientation_policy.dart';
import 'package:platform_image_converter/src/image_conversion_exception.dart';
import 'package:platform_image_converter/src/image_converter_platform_interface.dart';
import 'package:platform_image_converter/src/output_format.dart';
import 'package:platform_image_converter/src/output_resize.dart';

/// The API level that introduced `android.graphics.ImageDecoder`.
const _sdkImageDecoder = 28;

/// The API level that introduced `WEBP_LOSSY`/`WEBP_LOSSLESS` and deprecated
/// the combined `WEBP` compress format.
const _sdkExplicitWebp = 30;

/// Android image converter using ImageDecoder or BitmapFactory.
///
/// Implements image conversion on Android using ImageDecoder (API 28+) or
/// BitmapFactory for decoding, and Bitmap.compress for encoding via JNI.
///
/// **Features:**
/// - Supports JPEG, PNG, WebP, GIF, BMP input formats
/// - Can read HEIC files (Android 9+)
/// - Cannot write HEIC (throws UnsupportedFormatException)
/// - Efficient memory usage with ByteArrayOutputStream
///
/// **API Stack:**
/// - `ImageDecoder.decodeBitmap`: Decode and scale in one pass (API 28+)
/// - `BitmapFactory.decodeByteArray`: Auto-detect and decode input
/// - `Bitmap.createScaledBitmap`: Resize image with filtering
/// - `Bitmap.compress`: Encode to target format with quality control
/// - `ByteArrayOutputStream`: Memory-based output buffer
///
/// **Limitations:**
/// - HEIC output not supported (use JPEG or PNG instead)
/// - Requires Android 9+ for full format support
///
/// **Performance:**
/// - Native image decoding via ImageDecoder/BitmapFactory
/// - Efficient compression with quality adjustment
final class ImageConverterAndroid implements ImageConverterPlatform {
  const ImageConverterAndroid();

  @override
  Uint8List convert({
    required Uint8List inputData,
    OutputFormat format = .jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
    ExifOrientationPolicy orientation = .apply,
  }) {
    return using((arena) {
      // `Build.VERSION.SDK_INT` is not a compile-time constant in `android.jar`,
      // so jnigen binds it as a runtime field read: this is the API level of the
      // device, not of the SDK the plugin was built against. Every binding class
      // resolves its Java class lazily on first use, so the branches not taken
      // here never look up a class that is missing on an older device.
      final sdkInt = Build$VERSION.SDK_INT;

      // ImageDecoder scales while decoding instead of decoding at full size and
      // scaling afterwards, and it bakes in the EXIF orientation itself. It has
      // no way to *skip* that orientation, so `ignore` stays on BitmapFactory.
      final bitmapToCompress =
          sdkInt >= _sdkImageDecoder && orientation == .apply
          ? _decodeWithImageDecoder(arena, inputData, resizeMode)
          : _decodeWithBitmapFactory(arena, inputData, resizeMode, orientation);

      final compressFormat = switch (format) {
        .jpeg => Bitmap$CompressFormat.JPEG,
        .png => Bitmap$CompressFormat.PNG,
        .webp => _webpCompressFormat(sdkInt, quality),
        .heic => throw UnsupportedFormatException(
          format,
          .platformUnsupported,
          'HEIC output is not supported on Android.',
        ),
      }..releasedBy(arena);

      final outputStream = ByteArrayOutputStream()..releasedBy(arena);
      final success = bitmapToCompress.compress(
        compressFormat,
        quality,
        outputStream,
      );
      if (!success) {
        throw ImageEncodingException(format, 'Failed to compress bitmap.');
      }

      final outputJBytes = outputStream.toByteArray()?..releasedBy(arena);
      if (outputJBytes == null) {
        throw ImageEncodingException(
          format,
          'Failed to get byte array from output stream.',
        );
      }

      return Uint8List.fromList(outputJBytes.getRange(0, outputJBytes.length));
    });
  }

  /// Decodes [inputData] with [ImageDecoder], producing a bitmap that is already
  /// at the size [resizeMode] asks for and already EXIF-oriented.
  ///
  /// `setTargetSize` may only be called from `onHeaderDecoded`, so the resize
  /// arithmetic runs inside the listener. The size reported there is the
  /// oriented (display) size — ImageDecoder applies the EXIF origin to both the
  /// reported dimensions and the pixels — which is the same input the
  /// BitmapFactory path measures after [_applyOrientation].
  ///
  /// The default allocator can return a `HARDWARE` bitmap, whose pixels are not
  /// readable, so software allocation is requested for `Bitmap.compress`.
  Bitmap _decodeWithImageDecoder(
    Arena arena,
    Uint8List inputData,
    ResizeMode resizeMode,
  ) {
    // The `byte[]` overloads of `createSource` are API 31+, so the `ByteBuffer`
    // one (`createSource$6`) is the only option at this plugin's floor.
    final buffer = JByteBuffer.fromList(inputData)..releasedBy(arena);
    final source = ImageDecoder.createSource$6(buffer)?..releasedBy(arena);
    if (source == null) {
      throw const ImageDecodingException('Invalid image data.');
    }

    final listener = ImageDecoder$OnHeaderDecodedListener.implement(
      $ImageDecoder$OnHeaderDecodedListener(
        onHeaderDecoded: (decoder, info, _) {
          final size = info?.size;
          if (decoder == null || size == null) {
            return;
          }

          decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE;
          final (width, height) = resizeMode.calculateSize(
            size.width,
            size.height,
          );
          final resized = width != size.width || height != size.height;
          size.release();
          if (resized) {
            decoder.setTargetSize(width, height);
          }
        },
      ),
    )..releasedBy(arena);

    // The listener is invoked synchronously on the calling thread, which is the
    // thread of the isolate that built it, so `jni` dispatches it through the
    // direct function pointer rather than the port and cannot deadlock.
    final Bitmap? bitmap;
    try {
      bitmap = ImageDecoder.decodeBitmap$1(source, listener)
        ?..releasedBy(arena);
    } on JThrowable catch (e) {
      // ImageDecoder reports unsupported or corrupt input as a Java exception
      // (`ImageDecoder.DecodeException`, a subclass of IOException).
      throw ImageDecodingException('Failed to decode image data: ${e.message}');
    }
    if (bitmap == null) {
      throw const ImageDecodingException('Invalid image data.');
    }

    return bitmap;
  }

  /// Decodes [inputData] with [BitmapFactory], applying [orientation] and
  /// [resizeMode] to the decoded bitmap afterwards.
  ///
  /// Used below API 28 and whenever [ExifOrientationPolicy.ignore] is requested,
  /// since only this path can leave the source's orientation tag unapplied.
  Bitmap _decodeWithBitmapFactory(
    Arena arena,
    Uint8List inputData,
    ResizeMode resizeMode,
    ExifOrientationPolicy orientation,
  ) {
    final inputJBytes = JByteArray.of(inputData)..releasedBy(arena);
    final originalBitmap = BitmapFactory.decodeByteArray(
      inputJBytes,
      0,
      inputData.length,
    )?..releasedBy(arena);
    if (originalBitmap == null) {
      throw const ImageDecodingException('Invalid image data.');
    }

    // BitmapFactory ignores the EXIF orientation, so bake it into the pixels
    // before measuring/resizing (a no-op for ORIENTATION_NORMAL or `ignore`).
    // Resizing then operates on the oriented (display) dimensions.
    final orientedBitmap = orientation == .apply
        ? _applyOrientation(arena, inputJBytes, originalBitmap)
        : originalBitmap;

    final originalWidth = orientedBitmap.width;
    final originalHeight = orientedBitmap.height;
    final (newWidth, newHeight) = resizeMode.calculateSize(
      originalWidth,
      originalHeight,
    );
    if (newWidth == originalWidth && newHeight == originalHeight) {
      return orientedBitmap;
    }

    final scaledBitmap = Bitmap.createScaledBitmap(
      orientedBitmap,
      newWidth,
      newHeight,
      true, // filter
    )?..releasedBy(arena);
    if (scaledBitmap == null) {
      throw const ImageConversionException(
        'Bitmap could not be prepared for compression.',
      );
    }

    return scaledBitmap;
  }

  /// Reads the EXIF orientation from [inputJBytes] and, when it is not the
  /// normal orientation, returns a new [Bitmap] with that rotation/mirror baked
  /// into the pixels (via a [Matrix]); otherwise returns [src] unchanged.
  ///
  /// [ExifInterface] reads orientation from a stream over the original bytes;
  /// formats without EXIF (or upright images) report `ORIENTATION_NORMAL`, so
  /// this is a no-op for them. Every new JNI object is registered in [arena].
  Bitmap _applyOrientation(Arena arena, JByteArray inputJBytes, Bitmap src) {
    final exifStream = ByteArrayInputStream(inputJBytes)..releasedBy(arena);
    final exif = ExifInterface.new$2(exifStream)..releasedBy(arena);
    final tag = ExifInterface.TAG_ORIENTATION?..releasedBy(arena);
    final value = exif.getAttributeInt(tag, ExifInterface.ORIENTATION_NORMAL);
    if (value == ExifInterface.ORIENTATION_NORMAL || value < 1 || value > 8) {
      return src;
    }

    // Canonical Android EXIF-orientation matrices (setRotate is exposed as the
    // `rotate` setter by jnigen; degrees are clockwise).
    final matrix = Matrix()..releasedBy(arena);
    switch (value) {
      case 2: // flip horizontal
        matrix.setScale(-1.0, 1.0);
      case 3: // rotate 180
        matrix.rotate = 180.0;
      case 4: // flip vertical
        matrix
          ..rotate = 180.0
          ..postScale(-1.0, 1.0);
      case 5: // transpose
        matrix
          ..rotate = 90.0
          ..postScale(-1.0, 1.0);
      case 6: // rotate 90 CW
        matrix.rotate = 90.0;
      case 7: // transverse
        matrix
          ..rotate = -90.0
          ..postScale(-1.0, 1.0);
      case 8: // rotate 270 CW
        matrix.rotate = -90.0;
    }

    final oriented = Bitmap.createBitmap$2(
      src,
      0,
      0,
      src.width,
      src.height,
      matrix,
      true, // filter
    )?..releasedBy(arena);
    if (oriented == null) {
      throw const ImageConversionException('Failed to apply EXIF orientation.');
    }
    return oriented;
  }

  /// The WebP [Bitmap$CompressFormat] to use on a device at API level [sdkInt].
  ///
  /// The combined `WEBP` format is deprecated since API 30 in favour of the
  /// explicit `WEBP_LOSSY`/`WEBP_LOSSLESS`. Its documented behaviour is that a
  /// [quality] of 100 produces a lossless file and anything lower a lossy one,
  /// so splitting on that threshold keeps the output identical to what `WEBP`
  /// produced on the same device.
  Bitmap$CompressFormat _webpCompressFormat(int sdkInt, int quality) {
    if (sdkInt < _sdkExplicitWebp) {
      return Bitmap$CompressFormat.WEBP;
    }
    return quality >= 100
        ? Bitmap$CompressFormat.WEBP_LOSSLESS
        : Bitmap$CompressFormat.WEBP_LOSSY;
  }
}
