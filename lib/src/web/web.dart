import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

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
/// - HEIC not supported (throws UnsupportedError)
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
  }) async {
    final img = HTMLImageElement();
    final decodeCompeleter = Completer<void>();

    final blob = Blob([inputData.toJS].toJS);
    final url = URL.createObjectURL(blob);
    img.onLoad.listen((_) => decodeCompeleter.complete());
    img.onError.listen((e) {
      URL.revokeObjectURL(url);
      decodeCompeleter.completeError('Failed to load image: $e');
    });
    img.src = url;
    await decodeCompeleter.future;
    URL.revokeObjectURL(url);

    final canvas = HTMLCanvasElement();

    final int destWidth;
    final int destHeight;

    switch (resizeMode) {
      case OriginalResizeMode():
        destWidth = img.width;
        destHeight = img.height;
      case ExactResizeMode(width: final w, height: final h):
        destWidth = w;
        destHeight = h;
      case FitResizeMode(:final width, :final height):
        if (img.width <= width && img.height <= height) {
          destWidth = img.width;
          destHeight = img.height;
        } else {
          final aspectRatio = img.width / img.height;
          var newWidth = width.toDouble();
          var newHeight = newWidth / aspectRatio;

          if (newHeight > height) {
            newHeight = height.toDouble();
            newWidth = newHeight * aspectRatio;
          }
          destWidth = newWidth.round();
          destHeight = newHeight.round();
        }
    }

    canvas.width = destWidth;
    canvas.height = destHeight;

    final ctx = canvas.getContext('2d') as CanvasRenderingContext2D;
    ctx.drawImage(img, 0, 0, destWidth, destHeight);

    final encodeCompleter = Completer<Blob>();
    final type = switch (format) {
      OutputFormat.jpeg => 'image/jpeg',
      OutputFormat.png => 'image/png',
      OutputFormat.webp => 'image/webp',
      OutputFormat.heic => throw UnsupportedError(
        'HEIC output format is not supported on Web.',
      ),
    };

    canvas.toBlob(
      (Blob? blob) {
        if (blob != null) {
          encodeCompleter.complete(blob);
        } else {
          encodeCompleter.completeError(
            'Failed to convert canvas to JPEG Blob.',
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
