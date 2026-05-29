## 1.1.0

* Fix iOS/macOS crash when resizing 16-bit, grayscale, CMYK, or indexed images (#36).
* Normalize iOS/macOS output to 8-bit sRGB. 16-bit and wide-gamut (e.g. Display P3) sources are no longer preserved, and output no longer depends on whether a resize occurred (behavior change).

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
