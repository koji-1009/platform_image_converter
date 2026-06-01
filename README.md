# platform_image_converter

[![pub package](https://img.shields.io/pub/v/platform_image_converter.svg)](https://pub.dev/packages/platform_image_converter)
[![GitHub license](https://img.shields.io/github/license/koji-1009/platform_image_converter)](https://github.com/koji-1009/platform_image_converter/blob/main/LICENSE)

A high-performance Flutter plugin for cross-platform image format conversion and resizing using native APIs on iOS, macOS, Android, Windows, Linux, and Web.

## Features

- 🖼️ **Versatile Format Conversion**: Supports conversion between JPEG, PNG, and WebP. It also handles HEIC/HEIF, allowing conversion *from* HEIC on all supported platforms and *to* HEIC on iOS/macOS, Windows (where the OS HEVC/HEIF codec is present), and Linux (where a writable libheif GdkPixbuf loader is installed).
- 📐 **High-Quality Resizing**: Resize images with different modes (`Fit`, `Exact`) while maintaining aspect ratio or targeting specific dimensions.
- 🧭 **EXIF Orientation**: Bakes the source's EXIF orientation into the output by default (`ExifOrientationPolicy.apply`) so camera photos come out upright and consistent on every platform; opt out with `ExifOrientationPolicy.ignore`.
- ⚡ **Native Performance**: Achieves high speed by using platform-native APIs directly: `ImageIO` and `Core Graphics` on iOS/macOS, `BitmapFactory` and `Bitmap` methods on Android, the `Windows Imaging Component` (WIC) on Windows, `GdkPixbuf` (GLib/GTK stack) on Linux, and the `Canvas API` on the Web.
- 🔒 **Efficient Native Interop**: Employs FFI and JNI to create a fast, type-safe bridge between Dart and native code, ensuring robust and reliable communication.

## Platform Support

| Platform | Minimum Version | API Used |
|----------|-----------------|----------|
| iOS      | 14.0            | ImageIO, Core Graphics |
| macOS    | 10.15           | ImageIO, Core Graphics |
| Android  | 7               | BitmapFactory, Bitmap compression |
| Windows  | 10              | Windows Imaging Component (WIC) |
| Linux    | -               | GdkPixbuf (GLib/GTK stack) |
| Web      | -               | Canvas API |

**Note:**
- On iOS and macOS, WebP input is supported but WebP output is not supported.
- On Android, HEIC input is supported on Android 9+ but HEIC output is not supported.
- On Windows, JPEG and PNG output are always supported. HEIC output is supported where the OS ships the HEVC/HEIF codec (Windows 11 22H2+ out of the box; older Windows via the Microsoft Store "HEVC Video Extensions") — when the codec is absent, HEIC throws `UnsupportedFormatException` with reason `codecUnavailable`. WebP output is not supported (Windows provides a WebP decoder but no encoder).
- On Linux, JPEG and PNG output are always supported (built-in GdkPixbuf loaders). WebP and HEIC output require a *writable* GdkPixbuf loader module (e.g. `webp-pixbuf-loader`, or the libheif GdkPixbuf loader), which varies by distribution — when none is installed, output throws `UnsupportedFormatException` with reason `codecUnavailable`.
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
- **Windows**: JPEG, PNG, GIF, BMP, TIFF, and (with the relevant OS codec) HEIC, WebP (via WIC)
- **Linux**: JPEG, PNG, GIF, BMP, and (where the relevant GdkPixbuf loader is installed) WebP, HEIC
- **Web**: JPEG, PNG, WebP, GIF, BMP (via Canvas API)

### Output Formats
The supported output formats are defined by the `OutputFormat` enum, with platform-specific limitations:
- **JPEG**: Supported on all platforms.
- **PNG**: Supported on all platforms.
- **WebP**: Supported on Android and Web, and on Linux where a writable GdkPixbuf WebP loader is installed.
- **HEIC**: Supported on iOS/macOS, on Windows where the OS HEVC/HEIF codec is present, and on Linux where a writable libheif GdkPixbuf loader is installed.

## API Reference

### `ImageConverter.convert()`

```dart
static Future<Uint8List> convert({
  required Uint8List inputData,
  OutputFormat format = OutputFormat.jpeg,
  int quality = 100,
  ResizeMode resizeMode = const OriginalResizeMode(),
  ExifOrientationPolicy orientation = ExifOrientationPolicy.apply,
  bool runInIsolate = true,
}) async
```

**Parameters:**
- `inputData` (`Uint8List`): Raw image data to convert.
- `format` (`OutputFormat`): Target image format (default: JPEG).
- `quality` (`int`): Compression quality 1-100 (default: 100, only for lossy formats).
- `resizeMode` (`ResizeMode`): The resize mode to apply. Defaults to `OriginalResizeMode`, which keeps the original dimensions.
- `orientation` (`ExifOrientationPolicy`): How to handle the source's EXIF orientation tag. Defaults to `ExifOrientationPolicy.apply`, which bakes the orientation into the output pixels (a 90°/270° tag swaps the output width/height, and the resize is evaluated against the oriented dimensions). Use `ExifOrientationPolicy.ignore` to encode the raw decoded buffer instead.
- `runInIsolate` (`bool`): Whether to run the conversion in a background isolate (default: `true`). Set to `false` only for very small images where isolate overhead is a concern.

**Returns:** `Future<Uint8List>` containing the converted image data.

**Throws:** (all conversion failures share the `ImageConversionException` base type)
- `ArgumentError`: If `quality` is outside the 1-100 range.
- `UnsupportedPlatformException`: If the current platform has no conversion backend.
- `UnsupportedFormatException`: If the output format is not available in the current environment. Inspect `reason` to tell a permanent platform limitation (`platformUnsupported`) from a missing codec the user could install (`codecUnavailable`).
- `ImageDecodingException`: If the input image data cannot be decoded.
- `ImageEncodingException`: If the image cannot be encoded to the target format.
- `ImageConversionException`: For other general errors during the conversion process.

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

### `ExifOrientationPolicy` Enum

Controls how the source's EXIF orientation tag is handled. Output never carries orientation metadata (this package strips metadata), so the tag must be baked into the pixels to survive conversion.

- **`apply`** (default): Bakes the EXIF orientation into the output pixels so the result is visually upright on every platform. A 90°/270° rotation swaps the output width and height, and the resize is evaluated against the oriented (display) dimensions.
- **`ignore`**: Encodes the decoded pixel buffer as-is, ignoring the orientation tag. Use this to keep the raw pixel layout when orientation is handled elsewhere.


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

**Note:** Every conversion renders through a fixed 8-bit sRGB context — even when no resize is requested — so iOS/macOS output is always 8-bit sRGB. 16-bit and wide-gamut (e.g. Display P3) sources are not preserved, keeping output consistent with the Android and Web backends.

### Android Implementation

The Android implementation uses [BitmapFactory](https://developer.android.com/reference/android/graphics/BitmapFactory) and [Bitmap.compress](https://developer.android.com/reference/android/graphics/Bitmap#compress(android.graphics.Bitmap.CompressFormat,%20int,%20java.io.OutputStream)):

1. **Decoding**: `BitmapFactory.decodeByteArray` handles all supported formats.
2. **Resizing**: `Bitmap.createScaledBitmap` is used to create a new, resized bitmap from the original, with filtering enabled for smoother results.
3. **Compression**: `Bitmap.compress` encodes the final bitmap to the target format.
4. **Buffer Management**: `ByteArrayOutputStream` manages output data.

### Windows Implementation

The Windows implementation uses the [Windows Imaging Component](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-lib) (WIC), a COM-based imaging stack in `windowscodecs.dll`, bound directly via `dart:ffi` (no native build step):

1. **Decoding**: `IWICImagingFactory::CreateDecoderFromStream` → `GetFrame` decodes the input.
2. **Normalization**: `IWICFormatConverter` re-renders the frame to a fixed 32bpp BGRA surface, so output is independent of the source's pixel format (8/16-bit, grayscale, indexed, CMYK).
3. **Resizing**: `IWICBitmapScaler` with high-quality cubic interpolation, when the target size differs.
4. **Encoding**: `CreateEncoder` (by container GUID) → `IWICBitmapFrameEncode::WriteSource` encodes into an in-memory `IStream`. Quality for JPEG/HEIC is set via the encoder's `ImageQuality` property.

**Note:** HEIC output requires the OS HEVC/HEIF codec. It ships with Windows 11 22H2+; on older Windows the encoder is absent and HEIC throws `UnsupportedFormatException` with reason `codecUnavailable`. WebP output is not available (Windows provides a WebP decoder but no encoder). As with the other backends, every conversion renders through the fixed 8-bit surface even when no resize is requested.

### Linux Implementation

The Linux implementation uses [GdkPixbuf](https://docs.gtk.org/gdk-pixbuf/), the imaging library in the GLib/GTK stack that the Flutter Linux embedder already links, bound directly via `dart:ffi` (no native build step):

1. **Decoding**: `GdkPixbufLoader` is fed the input bytes in memory and auto-detects the format via the installed loader modules.
2. **Resizing**: `gdk_pixbuf_scale_simple` with `GDK_INTERP_HYPER` (high-quality resampling) when the target size differs from the source.
3. **Encoding**: `gdk_pixbuf_save_to_bufferv` writes the target format to an in-memory buffer. Quality for lossy formats (JPEG/WebP/HEIC) is passed via the `quality` option.

**Note:** JPEG and PNG output are always available. WebP and HEIC depend on a *writable* GdkPixbuf loader module (e.g. `webp-pixbuf-loader`, or the libheif GdkPixbuf loader), detected at runtime via `gdk_pixbuf_get_formats`. When none is installed, output throws `UnsupportedFormatException` with reason `codecUnavailable`. GdkPixbuf decodes to an 8-bit RGB/RGBA surface (normalising bit depth like the other backends), but it performs no ICC colour management: unlike the iOS/macOS sRGB normalisation, non-sRGB or wide-gamut sources (e.g. Display P3, Adobe RGB) keep their original pixel values instead of being converted to sRGB. For the common case — sRGB or untagged JPEG/PNG, which is the bulk of real input — output matches the other backends; this caveat only affects colour-managed sources.

### Web Implementation

The Web implementation uses the [Canvas API](https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API) for image conversion:

1. **Decoding**: `HTMLImageElement` loads image data via a Blob URL.
2. **Resizing & Rendering**: `CanvasRenderingContext2D.drawImage` renders the image to a canvas with the target dimensions, effectively resizing it.
3. **Encoding**: `HTMLCanvasElement.toBlob` encodes the canvas content to the target format.
4. **Quality**: Supports quality parameter for JPEG and WebP (0.0-1.0 scale).

**Key Limitations:**
- HEIC format is not supported on Web platform.
- Output format depends on browser support (JPEG and PNG are universally supported, WebP is widely supported).
