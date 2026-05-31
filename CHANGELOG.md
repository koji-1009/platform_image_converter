## 2.1.0

* Add EXIF orientation handling via a new `orientation` parameter on `ImageConverter.convert`, controlled by the `ExifOrientationPolicy` enum. `apply` (the default) bakes the source's EXIF orientation into the output pixels so the result is upright on every platform; `ignore` encodes the decoded buffer as-is. Implemented on every backend: Darwin (CoreGraphics CTM), Android (`ExifInterface` + `Matrix`), Windows (`IWICBitmapFlipRotator` + metadata query reader), Linux (`gdk_pixbuf_apply_embedded_orientation`), and Web (`createImageBitmap` `imageOrientation`).
* **Behavior change:** because `apply` is the default, the output of EXIF-tagged sources (typically camera JPEG/HEIC) now reflects the orientation tag instead of the raw decoded buffer. For a 90°/270° tag the output width and height swap, and the resize mode is evaluated against the oriented (display) dimensions. Pass `orientation: ExifOrientationPolicy.ignore` to keep the previous raw-buffer behavior.

## 2.0.0

* **Breaking:** unsupported-output and unsupported-platform conditions now throw exceptions from the `ImageConversionException` hierarchy instead of the `dart:core` `UnsupportedError`, so a single `on ImageConversionException` clause catches every conversion failure and these recoverable conditions are no longer modelled as un-catchable `Error`s. A format that the platform cannot produce throws `UnsupportedFormatException`, whose `reason` distinguishes a permanent platform limitation (`platformUnsupported`, e.g. WebP on iOS/macOS/Windows or HEIC on Android/Web) from a codec that the user could install (`codecUnavailable`, e.g. Windows HEIC without the HEVC/HEIF codec). Running on a platform with no backend throws `UnsupportedPlatformException`. Code that caught `UnsupportedError` must now catch these types.
* Add Windows support via the Windows Imaging Component (WIC), bound directly with `dart:ffi` (no native build step). JPEG and PNG output are supported with the same resizing modes and quality control as the other platforms. HEIC output is also supported where the OS ships the HEVC/HEIF codec (Windows 11 22H2+ out of the box; older Windows via the Store "HEVC Video Extensions") — when absent, HEIC throws `UnsupportedFormatException`. WebP output is not supported (Windows has a WebP decoder but no encoder). As on the Darwin backend, every source is normalized to a fixed 8-bit surface before encoding.
* Add Linux support via GdkPixbuf (the GLib/GTK imaging stack the Flutter Linux embedder already links), bound directly with `dart:ffi` (no native build step). JPEG and PNG output are always available; WebP and HEIC output require a *writable* GdkPixbuf loader module (e.g. `webp-pixbuf-loader`, or the libheif loader), which varies by distribution — when none is installed, output throws `UnsupportedFormatException` with reason `codecUnavailable`. Resizing uses high-quality (`GDK_INTERP_HYPER`) resampling and quality control matches the other platforms.

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
