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
  const ExactResizeMode({required this.width, required this.height});

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
    : assert(width != null || height != null);

  /// The maximum width for the resized image.
  final int? width;

  /// The maximum height for the resized image.
  final int? height;

  @override
  (int, int) calculateSize(int originalWidth, int originalHeight) {
    double scale = 1.0;
    if (width != null && height != null) {
      final widthScale = width! / originalWidth;
      final heightScale = height! / originalHeight;
      scale = min(widthScale, heightScale);
    } else if (width != null) {
      scale = width! / originalWidth;
    } else if (height != null) {
      scale = height! / originalHeight;
    }

    if (scale >= 1.0) {
      return (originalWidth, originalHeight);
    }

    return ((originalWidth * scale).round(), (originalHeight * scale).round());
  }
}
