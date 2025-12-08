# image_ffi

A high-performance Flutter plugin for cross-platform image format conversion using native APIs.

## Features

- 🖼️ **Versatile Format Conversion**: Supports conversion between JPEG, PNG, and WebP. It also handles HEIC/HEIF, allowing conversion *from* HEIC on all supported platforms and *to* HEIC on iOS/macOS.
- ⚡ **Native Performance**: Achieves high speed by using platform-native APIs directly: ImageIO on iOS/macOS and BitmapFactory on Android.
- 🔒 **Efficient Native Interop**: Employs FFI and JNI to create a fast, type-safe bridge between Dart and native code, ensuring robust and reliable communication.

## Platform Support

| Platform | Minimum Version | API Used |
|----------|-----------------|----------|
| iOS      | 14.0            | ImageIO (CoreFoundation, CoreGraphics) |
| macOS    | 10.15           | ImageIO (CoreFoundation, CoreGraphics) |
| Android  | 7               | BitmapFactory, Bitmap compression |
| Web      | -               | Canvas API |

**Note:**
- On iOS and macOS, WebP input is supported but WebP output is not supported.
- On Android, HEIC input is supported on Android 9+ but HEIC output is not supported.
- On Web, HEIC is not supported.

## Getting Started

### Installation

Add `image_ffi` to your `pubspec.yaml`:

```yaml
dependencies:
  image_ffi: ^0.0.1
```

### Basic Usage

```dart
import 'package:image_ffi/image_ffi.dart';
import 'dart:typed_data';

// Convert HEIC image to JPEG
final jpegData = await ImageConverter.convert(
  inputData: heicImageData,
  format: OutputFormat.jpeg,
  quality: 90,
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

### Output Formats
The supported output formats are defined by the `OutputFormat` enum, with platform-specific limitations:
- **JPEG**: Supported on all platforms.
- **PNG**: Supported on all platforms.
- **WebP**: Supported on Android only.
- **HEIC**: Supported on iOS/macOS only.

## API Reference

### `ImageConverter.convert()`

```dart
static Future<Uint8List> convert({
  required Uint8List inputData,
  OutputFormat format = OutputFormat.jpeg,
  int quality = 100,
}) async
```

**Parameters:**
- `inputData` (`Uint8List`): Raw image data to convert
- `format` (`OutputFormat`): Target image format (default: JPEG)
- `quality` (`int`): Compression quality 1-100 (default: 100, only for lossy formats)

**Returns:** `Future<Uint8List>` containing the converted image data

**Throws:**
- `UnsupportedError`: If the platform or format is not supported
- `Exception`: If conversion fails

### `OutputFormat` Enum

```dart
enum OutputFormat {
  /// JPEG format (.jpg, .jpeg)
  /// Lossy compression, suitable for photos
  jpeg,

  /// PNG format (.png)
  /// Lossless compression, supports transparency
  png,

  /// WebP format (.webp)
  /// Modern format with superior compression (not supported on Darwin)
  webp,

  /// HEIC format (.heic)
  /// High Efficiency Image Format (not supported on Android)
  heic,
}
```

## Implementation Details

### iOS/macOS Implementation

The iOS/macOS implementation uses the [ImageIO](https://developer.apple.com/documentation/imageio) framework via FFI bindings:

1. **Decoding**: `CGImageSourceCreateWithData` reads input data
2. **Rendering**: `CGImageSourceCreateImageAtIndex` decodes to `CGImage`
3. **Encoding**: `CGImageDestinationCreateWithData` encodes to target format
4. **Quality**: Uses `kCGImageDestinationLossyCompressionQuality` for JPEG/WebP

**Key Functions:**
- `CFDataCreate`: Create immutable data from input bytes
- `CGImageSourceCreateWithData`: Create image source from data
- `CGImageDestinationCreateWithData`: Create image destination
- `CGImageDestinationAddImage`: Add image to destination
- `CGImageDestinationFinalize`: Complete encoding

### Android Implementation

The Android implementation uses [BitmapFactory](https://developer.android.com/reference/android/graphics/BitmapFactory) and [Bitmap.compress](https://developer.android.com/reference/android/graphics/Bitmap#compress(android.graphics.Bitmap.CompressFormat,%20int,%20java.io.OutputStream)):

1. **Decoding**: `BitmapFactory.decodeByteArray` handles all supported formats
2. **Compression**: `Bitmap.compress` encodes to target format
3. **Buffer Management**: `ByteArrayOutputStream` manages output data

**Key Limitations:**
- HEIC can be read (input only) but cannot be written (output format not supported)
- Requires Android 9+ for full HEIC support

### Web Implementation

The Web implementation uses the [Canvas API](https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API) for image conversion:

1. **Decoding**: `HTMLImageElement` loads image data via Blob URL
2. **Rendering**: `CanvasRenderingContext2D.drawImage` renders the image to canvas
3. **Encoding**: `HTMLCanvasElement.toBlob` encodes to target format
4. **Quality**: Supports quality parameter for JPEG and WebP (0.0-1.0 scale)

**Key Steps:**
- `Blob` and `URL.createObjectURL`: Create temporary URL from input bytes
- `HTMLImageElement.onLoad`: Wait for image to load asynchronously
- `canvas.width/height = img.width/height`: Set canvas size to match image dimensions
- `canvas.toBlob`: Convert canvas content to target format

**Key Limitations:**
- HEIC format is not supported on Web platform
- Output format depends on browser support (JPEG and PNG are universally supported, WebP is widely supported)
