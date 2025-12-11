# platform_image_converter

A high-performance Flutter plugin for cross-platform image format conversion and resizing using native APIs on iOS, macOS, Android, and Web.

## Features

- 🖼️ **Versatile Format Conversion**: Supports conversion between JPEG, PNG, and WebP. It also handles HEIC/HEIF, allowing conversion *from* HEIC on all supported platforms and *to* HEIC on iOS/macOS.
- 📐 **High-Quality Resizing**: Resize images with different modes (`Fit`, `Exact`) while maintaining aspect ratio or targeting specific dimensions.
- ⚡ **Native Performance**: Achieves high speed by using platform-native APIs directly: `ImageIO` and `Core Graphics` on iOS/macOS, `BitmapFactory` and `Bitmap` methods on Android, and the `Canvas API` on the Web.
- 🔒 **Efficient Native Interop**: Employs FFI and JNI to create a fast, type-safe bridge between Dart and native code, ensuring robust and reliable communication.

## Platform Support

| Platform | Minimum Version | API Used |
|----------|-----------------|----------|
| iOS      | 14.0            | ImageIO, Core Graphics |
| macOS    | 10.15           | ImageIO, Core Graphics |
| Android  | 7               | BitmapFactory, Bitmap compression |
| Web      | -               | Canvas API |

**Note:**
- On iOS and macOS, WebP input is supported but WebP output is not supported.
- On Android, HEIC input is supported on Android 9+ but HEIC output is not supported.
- On Web, HEIC is not supported.

## Getting Started

### Basic Usage

```dart
import 'package:platform_image_converter/platform_image_converter.dart';
import 'dart:typed_data';

// Convert HEIC image to JPEG
final jpegData = await ImageConverter.convert(
  inputData: heicImageData,
  format: OutputFormat.jpeg,
  quality: 90,
);

// Convert and resize an image to fit within a width of 200, scaling height proportionally
final resizedData = await ImageConverter.convert(
  inputData: imageData,
  format: OutputFormat.png,
  resizeMode: const FitResizeMode(width: 200),
);

// Convert any format to PNG
final pngData = await ImageConverter.convert(
  inputData: imageData,
  format: OutputFormat.png,
);
```

## Supported Formats

### Input Formats
- **iOS/macOS**: JPEG, PNG, HEIC, WebP, BMP, GIF, TIFF, and more
- **Android**: JPEG, PNG, WebP, GIF, BMP, HEIC (via BitmapFactory)
- **Web**: JPEG, PNG, WebP, GIF, BMP (via Canvas API)

### Output Formats
The supported output formats are defined by the `OutputFormat` enum, with platform-specific limitations:
- **JPEG**: Supported on all platforms.
- **PNG**: Supported on all platforms.
- **WebP**: Supported on Android and Web.
- **HEIC**: Supported on iOS/macOS only.

## API Reference

### `ImageConverter.convert()`

```dart
static Future<Uint8List> convert({
  required Uint8List inputData,
  OutputFormat format = OutputFormat.jpeg,
  int quality = 100,
  ResizeMode resizeMode = const OriginalResizeMode(),
}) async
```

**Parameters:**
- `inputData` (`Uint8List`): Raw image data to convert.
- `format` (`OutputFormat`): Target image format (default: JPEG).
- `quality` (`int`): Compression quality 1-100 (default: 100, only for lossy formats).
- `resizeMode` (`ResizeMode`): The resize mode to apply. Defaults to `OriginalResizeMode`, which keeps the original dimensions.

**Returns:** `Future<Uint8List>` containing the converted image data.

**Throws:**
- `UnsupportedError`: If the platform or format is not supported.
- `Exception`: If conversion fails.

### `OutputFormat` Enum

```dart
enum OutputFormat {
  jpeg, // .jpg, .jpeg
  png,  // .png
  webp, // .webp
  heic, // .heic
}
```

### `ResizeMode` Sealed Class

A sealed class representing different ways to resize an image.

- **`OriginalResizeMode()`**: Keeps the original dimensions of the image.
- **`ExactResizeMode({required int width, required int height})`**: Resizes the image to exact dimensions, possibly changing the aspect ratio.
- **`FitResizeMode({int? width, int? height})`**: Fits the image within the specified dimensions while maintaining the aspect ratio. At least one of `width` or `height` must be provided. If only one dimension is provided, the other is scaled proportionally. If the image is smaller than the specified dimensions, it will not be scaled up.


## Implementation Details

### iOS/macOS Implementation

The iOS/macOS implementation uses the [ImageIO](https://developer.apple.com/documentation/imageio) and [Core Graphics](https://developer.apple.com/documentation/coregraphics) frameworks via FFI bindings:

1. **Decoding**: `CGImageSourceCreateWithData` reads input data.
2. **Resizing**:
   - `CGBitmapContextCreate` creates a new bitmap context with the target dimensions.
   - `CGContextDrawImage` draws the original image into the context, scaling it in the process. `CGContextSetInterpolationQuality` is set to high for better quality.
   - `CGBitmapContextCreateImage` creates a new `CGImage` from the context.
3. **Encoding**: `CGImageDestinationCreateWithData` encodes the final `CGImage` to the target format.
4. **Quality**: Uses `kCGImageDestinationLossyCompressionQuality` for JPEG/HEIC.

### Android Implementation

The Android implementation uses [BitmapFactory](https://developer.android.com/reference/android/graphics/BitmapFactory) and [Bitmap.compress](https://developer.android.com/reference/android/graphics/Bitmap#compress(android.graphics.Bitmap.CompressFormat,%20int,%20java.io.OutputStream)):

1. **Decoding**: `BitmapFactory.decodeByteArray` handles all supported formats.
2. **Resizing**: `Bitmap.createScaledBitmap` is used to create a new, resized bitmap from the original, with filtering enabled for smoother results.
3. **Compression**: `Bitmap.compress` encodes the final bitmap to the target format.
4. **Buffer Management**: `ByteArrayOutputStream` manages output data.

### Web Implementation

The Web implementation uses the [Canvas API](https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API) for image conversion:

1. **Decoding**: `HTMLImageElement` loads image data via a Blob URL.
2. **Resizing & Rendering**: `CanvasRenderingContext2D.drawImage` renders the image to a canvas with the target dimensions, effectively resizing it.
3. **Encoding**: `HTMLCanvasElement.toBlob` encodes the canvas content to the target format.
4. **Quality**: Supports quality parameter for JPEG and WebP (0.0-1.0 scale).

**Key Limitations:**
- HEIC format is not supported on Web platform.
- Output format depends on browser support (JPEG and PNG are universally supported, WebP is widely supported).
