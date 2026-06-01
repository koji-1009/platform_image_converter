import 'dart:math';

/// A sealed class representing different ways to resize an image.
sealed class ResizeMode {
  const ResizeMode();

  /// Calculates the target size for the image based on the original dimensions.
  (int, int) calculateSize(int originalWidth, int originalHeight);
}

/// A resize mode that keeps the original dimensions of the image.
class OriginalResizeMode extends ResizeMode {
  const OriginalResizeMode();

  @override
  (int, int) calculateSize(int originalWidth, int originalHeight) {
    return (originalWidth, originalHeight);
  }
}

/// A resize mode that resizes the image to exact dimensions,
/// possibly changing the aspect ratio.
class ExactResizeMode extends ResizeMode {
  const ExactResizeMode({required this.width, required this.height})
    : assert(width > 0 && height > 0, 'width and height must be positive');

  /// The target width for the resized image.
  final int width;

  /// The target height for the resized image.
  final int height;

  @override
  (int, int) calculateSize(int originalWidth, int originalHeight) {
    return (width, height);
  }
}

/// A resize mode that fits the image within the specified dimensions while
/// maintaining the aspect ratio.
///
/// If the image is smaller than the specified dimensions, it will not be
/// scaled up.
class FitResizeMode extends ResizeMode {
  const FitResizeMode({this.width, this.height})
    : assert(width != null || height != null),
      assert((width ?? 1) > 0, 'width must be positive'),
      assert((height ?? 1) > 0, 'height must be positive');

  /// The maximum width for the resized image.
  final int? width;

  /// The maximum height for the resized image.
  final int? height;

  @override
  (int, int) calculateSize(int originalWidth, int originalHeight) {
    final scale = switch ((width, height)) {
      (final w?, final h?) => min(w / originalWidth, h / originalHeight),
      (final w?, null) => w / originalWidth,
      (null, final h?) => h / originalHeight,
      (null, null) => 1.0,
    };

    if (scale >= 1.0) {
      return (originalWidth, originalHeight);
    }

    return ((originalWidth * scale).round(), (originalHeight * scale).round());
  }
}
