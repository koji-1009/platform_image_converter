/// A sealed class representing different ways to resize an image.
sealed class ResizeMode {
  const ResizeMode();
}

/// A resize mode that keeps the original dimensions of the image.
class OriginalResizeMode extends ResizeMode {
  const OriginalResizeMode();
}

/// A resize mode that resizes the image to exact dimensions,
/// possibly changing the aspect ratio.
class ExactResizeMode extends ResizeMode {
  const ExactResizeMode({required this.width, required this.height});

  /// The target width for the resized image.
  final int width;

  /// The target height for the resized image.
  final int height;
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
}
