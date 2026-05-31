import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:platform_image_converter/src/exif_orientation_policy.dart';
import 'package:platform_image_converter/src/image_conversion_exception.dart';
import 'package:platform_image_converter/src/image_converter_platform_interface.dart';
import 'package:platform_image_converter/src/output_format.dart';
import 'package:platform_image_converter/src/output_resize.dart';
import 'package:web/web.dart';

/// Web image converter using Canvas API.
///
/// Implements image conversion for web platforms using the HTML5 Canvas API
/// for decoding and encoding images in the browser.
///
/// **Features:**
/// - Supports JPEG, PNG, WebP formats (browser-dependent)
/// - HEIC format not supported on Web
/// - Adjustable quality for JPEG and WebP compression
/// - Asynchronous image loading and encoding
///
/// **API Stack:**
/// - `HTMLImageElement`: Load and decode input image via Blob URL
/// - `CanvasRenderingContext2D.drawImage`: Render image to canvas
/// - `HTMLCanvasElement.toBlob`: Encode canvas to target format
///
/// **Limitations:**
/// - HEIC not supported (throws UnsupportedFormatException)
/// - Output format support depends on browser capabilities
/// - JPEG and PNG are universally supported
/// - WebP is widely supported in modern browsers
///
/// **Performance:**
/// - Browser-native image decoding and encoding
/// - In-memory processing with Blob/ArrayBuffer
/// - Quality parameter controls compression ratio
final class ImageConverterWeb implements ImageConverterPlatform {
  const ImageConverterWeb();

  @override
  Future<Uint8List> convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
    ExifOrientationPolicy orientation = ExifOrientationPolicy.apply,
  }) async {
    final blob = Blob([inputData.toJS].toJS);

    // Decode via createImageBitmap so the EXIF orientation can be applied
    // (`from-image`) or ignored (`none`) explicitly. An <img> element always
    // applies it, which would make `ignore` impossible and the default differ
    // from the native backends. With `from-image` the bitmap's width/height are
    // already the oriented (displayed) dimensions, so the resize matches.
    final ImageBitmap bitmap;
    try {
      bitmap = await window
          .createImageBitmap(
            blob,
            ImageBitmapOptions(
              imageOrientation: orientation == ExifOrientationPolicy.apply
                  ? 'from-image'
                  : 'none',
            ),
          )
          .toDart;
    } catch (_) {
      throw const ImageDecodingException('Failed to load image from data.');
    }

    final (destWidth, destHeight) = resizeMode.calculateSize(
      bitmap.width,
      bitmap.height,
    );

    final canvas = HTMLCanvasElement();
    canvas.width = destWidth;
    canvas.height = destHeight;

    final ctx = canvas.getContext('2d') as CanvasRenderingContext2D
      ..imageSmoothingEnabled = true
      ..imageSmoothingQuality = 'high';
    ctx.drawImage(bitmap, 0, 0, destWidth, destHeight);
    bitmap.close();

    final encodeCompleter = Completer<Blob>();
    final type = switch (format) {
      OutputFormat.jpeg => 'image/jpeg',
      OutputFormat.png => 'image/png',
      OutputFormat.webp => 'image/webp',
      OutputFormat.heic => throw UnsupportedFormatException(
        format,
        UnsupportedFormatReason.platformUnsupported,
        'HEIC output is not supported on Web.',
      ),
    };

    canvas.toBlob(
      (Blob? blob) {
        if (blob != null) {
          encodeCompleter.complete(blob);
        } else {
          encodeCompleter.completeError(
            ImageEncodingException(format, 'Canvas toBlob returned null.'),
          );
        }
      }.toJS,
      type,
      (quality / 100).toJS,
    );

    final result = await encodeCompleter.future;
    final arrayBuffer = await result.arrayBuffer().toDart;
    return arrayBuffer.toDart.asUint8List();
  }
}
