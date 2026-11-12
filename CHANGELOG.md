## Unreleased

* Raise the minimum `jni` version to 1.1.0 (previously 1.0.0). The Android bindings are regenerated with `jnigen` 1.0.1, which requires `jni` 1.1.
* Regenerate the bindings with `jnigen` 1.0.1 and `ffigen` 23.0.0, configured from Dart scripts (`ffigen.dart`, `ffigen_linux.dart`, `jnigen.dart`) instead of `jnigen.yaml`.

## 2.3.0

* Add `OutputFormat.avif` for AVIF output on iOS/macOS, Android, Windows and Linux. iOS/macOS encode it with ImageIO, Windows with the WIC HEIF encoder set to AV1 compression, and Linux through GdkPixbuf's `avif` format (glycin with a libheif AV1 encoder such as `libheif-plugin-aomenc`, or a loader module such as `libavif-gdk-pixbuf`). Where the encoder is missing, AVIF throws `UnsupportedFormatException` with reason `codecUnavailable`; Web throws `platformUnsupported`. On iOS/macOS, quality 100 is encoded at 0.99, since ImageIO's AVIF encoder fails at 1.0.
* Android encodes AVIF on Android 14+ (API 34) with the platform's AV1 encoder (`MediaCodec`) and `MediaMuxer`, storing the image as a HEIF grid of AV1 tiles. Below Android 14, and on Android 16 before QPR2 (SDK 36.0), whose `MediaMuxer` writes no AVIF image items, it throws `codecUnavailable`. Android AVIF output has no alpha channel: AVIF stores alpha as a monochrome AV1 image, which Android's AV1 encoders cannot produce, so transparent pixels are composited onto black. Use it with care: handle `codecUnavailable` and fall back to another format, and expect output size, quality and encoding time to depend on the device's AV1 encoder.
* Reject unsupported output on iOS/macOS before decoding the input: WebP output with invalid input now throws `UnsupportedFormatException` instead of `ImageDecodingException`.

## 2.2.1

* Fix JPEG output on Linux from a source with an alpha channel. The RGBA pixbuf was handed to the JPEG encoder as is, which either rejected it (throwing `ImageEncodingException`) or dropped the alpha channel and kept the colour of transparent pixels, depending on the installed GdkPixbuf encoder. The source is now composited onto opaque black before encoding, in the same pass as any resize, so transparent pixels become black.
* Pass `quality` to the Linux encoder only when its GdkPixbuf loader supports the `quality` save option (`gdk_pixbuf_format_is_save_option_supported`). Otherwise it has no effect on the output, as for PNG.
* Report the HRESULT when no WIC decoder can be created for the input on Windows. The `ImageDecodingException` message was a fixed "Invalid image data."; it now includes the code, which tells invalid data apart from a format that no installed decoder supports.
* Correct the Linux HEIC output documentation: it requires a writable `heif` GdkPixbuf loader, and the libheif GdkPixbuf loader only decodes, so it does not enable HEIC output.
* Correct outdated API documentation: the Web backend decodes with `createImageBitmap` (not an `HTMLImageElement`), the Darwin backend encodes JPEG, PNG and HEIC with quality for JPEG/HEIC (not WebP), and the Android backend decodes with `ImageDecoder` or `BitmapFactory`.
* Rework the integration tests: platforms are selected with `skip` instead of branching inside test bodies, and output is checked by its detected format, decodability, size and pixels instead of by file sizes.

## 2.2.0

* Decode with `ImageDecoder` on Android 9+ (API 28) when `ExifOrientationPolicy.apply` is in effect. `setTargetSize` in the header callback scales during the decode, so a resize no longer materializes the full-resolution bitmap before `Bitmap.createScaledBitmap` shrinks it, and `ImageDecoder` bakes in the EXIF orientation itself. The `BitmapFactory` path is unchanged and still used below API 28 and for `ExifOrientationPolicy.ignore`, which `ImageDecoder` cannot express; the plugin's `minSdk` is unchanged.
* Use the explicit `WEBP_LOSSY`/`WEBP_LOSSLESS` compress formats for WebP output on Android 11+ (API 30), where the combined `WEBP` format is deprecated. A `quality` of 100 selects `WEBP_LOSSLESS` and anything lower `WEBP_LOSSY`, which is what `WEBP` itself did, so the output is unchanged.
* Free the Android JNI output buffer deterministically. `JByteArray.getRange` took its native buffer from `malloc` with a `NativeFinalizer` attached, so a buffer as large as the encoded output stayed alive until the Dart GC ran that finalizer. It now comes from the surrounding arena and is freed when the conversion scope ends.
* Regenerate the bindings with `jnigen` 0.17.0 and `ffigen` 21.0.0.
* Add host-runnable unit tests for the EXIF orientation transforms on the Darwin and Windows backends. The pure transform functions are exposed via `@visibleForTesting` and covered by tests that pin the CoreGraphics affine matrix (all eight orientations, plus a scaled case) and the WIC `WICBitmapTransformOptions` mapping, so a regression in that math is caught on the unit-test runner without a device or simulator. No behavior change.

## 2.1.3

* Fix a memory leak on iOS/macOS: the `CFDictionary` holding the JPEG/HEIC compression quality was created but never released, leaking one dictionary per lossy conversion. It is now released together with the surrounding arena.
* Guarantee resize output is at least 1x1px. An extreme aspect ratio could round a dimension down to 0 (for example fitting a 4000x3 image to width 5), producing a zero-sized surface that the native encoders reject; `ResizeMode.calculateSize` now clamps both dimensions to a minimum of 1px across every resize mode and platform.

## 2.1.2

* Restore the `jni` dependency to `^1.0.0` (and the Android bindings generated with `jnigen` 0.16.0), reverting the temporary downgrade shipped in 2.1.1. Projects that also depend on packages still on `jni` 0.15.x (such as `cronet_http`) will keep resolving to 2.1.1 automatically until those packages migrate.

## 2.1.1

* Downgrade the `jni` dependency to `^0.15.0` (and regenerate the Android bindings with `jnigen` 0.15.0) so this package can be used alongside packages that still depend on `jni` 0.15.x, such as `cronet_http`. This is a temporary compatibility release; a future release will return to `jni` 1.0.0 once the ecosystem has migrated.

## 2.1.0

* Add EXIF orientation handling via a new `orientation` parameter on `ImageConverter.convert`, controlled by the `ExifOrientationPolicy` enum. `apply` (the default) bakes the source's EXIF orientation into the output pixels so the result is upright on every platform; `ignore` encodes the decoded buffer as-is. Implemented on every backend: Darwin (CoreGraphics CTM), Android (`ExifInterface` + `Matrix`), Windows (`IWICBitmapFlipRotator` + metadata query reader), Linux (`gdk_pixbuf_apply_embedded_orientation`), and Web (`createImageBitmap` `imageOrientation`).
* **Behavior change:** because `apply` is the default, the output of EXIF-tagged sources (typically camera JPEG/HEIC) now reflects the orientation tag instead of the raw decoded buffer. For a 90°/270° tag the output width and height swap, and the resize mode is evaluated against the oriented (display) dimensions. Pass `orientation: ExifOrientationPolicy.ignore` to keep the previous raw-buffer behavior.

## 2.0.0

* **Breaking:** unsupported-output and unsupported-platform conditions now throw exceptions from the `ImageConversionException` hierarchy instead of the `dart:core` `UnsupportedError`, so a single `on ImageConversionException` clause catches every conversion failure and these recoverable conditions are no longer modelled as un-catchable `Error`s. A format that the platform cannot produce throws `UnsupportedFormatException`, whose `reason` distinguishes a permanent platform limitation (`platformUnsupported`, e.g. WebP on iOS/macOS/Windows or HEIC on Android/Web) from a codec that the user could install (`codecUnavailable`, e.g. Windows HEIC without the HEVC/HEIF codec). Running on a platform with no backend throws `UnsupportedPlatformException`. Code that caught `UnsupportedError` must now catch these types.
* Add Windows support via the Windows Imaging Component (WIC), bound directly with `dart:ffi` (no native build step). JPEG and PNG output are supported with the same resizing modes and quality control as the other platforms. HEIC output is also supported where the OS ships the HEVC/HEIF codec (Windows 11 22H2+ out of the box; older Windows via the Store "HEVC Video Extensions") — when absent, HEIC throws `UnsupportedFormatException`. WebP output is not supported (Windows has a WebP decoder but no encoder). As on the Darwin backend, every source is normalized to a fixed 8-bit surface before encoding.
* Add Linux support via GdkPixbuf (the GLib/GTK imaging stack the Flutter Linux embedder already links), bound directly with `dart:ffi` (no native build step). JPEG and PNG output are always available; WebP and HEIC output require a *writable* GdkPixbuf loader module (e.g. `webp-pixbuf-loader`; the libheif loader only decodes, so it does not enable HEIC output), which varies by distribution — when none is installed, output throws `UnsupportedFormatException` with reason `codecUnavailable`. Resizing uses high-quality (`GDK_INTERP_HYPER`) resampling and quality control matches the other platforms.

## 1.2.1

* Web: render resizes with `imageSmoothingQuality = 'high'` so downscaled output quality matches the iOS/macOS (`kCGInterpolationHigh`) and Android (`filter: true`) backends.

## 1.2.0

* Upgrade the `jni` dependency to `^1.0.0` and regenerate the Android bindings with `jnigen` 0.16.0. The minimum `jni` version is now 1.0.0 (previously 0.15.2); this major bump of a direct dependency may affect dependency resolution for consumers that also depend on `jni`.

## 1.1.0

* Fix iOS/macOS crash when resizing 16-bit, grayscale, CMYK, or indexed images (#36).
* Normalize iOS/macOS output to 8-bit sRGB. 16-bit and wide-gamut (e.g. Display P3) sources are no longer preserved, and output no longer depends on whether a resize occurred (behavior change).
* Drop the `objective_c` dependency on iOS/macOS; the native backend now binds CoreFoundation/CoreGraphics/ImageIO directly via `dart:ffi`.

## 1.0.6

* Fix lint rule.

## 1.0.5

* Fix exclude rule.

## 1.0.4

* Fix lint rules.
* Fix documentations.
* Fix resource management.

## 1.0.3

* Fix support flutter version constraint.
* Fix documentations.
* Update integration test.

## 1.0.2

* dart format applied to all files.

## 1.0.1

* Fix pubspec.ymml and .metadata files.

## 1.0.0

* Initial stable release.
* Add `ImageConversionException` for better error handling.
* Improve documentation and add usage examples.

## 0.2.0

* Support resized image output.
* Refactor codebase for better maintainability.

## 0.1.0

* Initial release of platform_image_converter.
* Support Android, iOS, macOS, and Web.
* Add `convert` method for image format conversion.
