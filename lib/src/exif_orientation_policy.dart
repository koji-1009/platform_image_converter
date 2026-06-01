/// How an image's EXIF orientation tag is handled during conversion.
///
/// Cameras commonly store pixels in a fixed buffer layout alongside a separate
/// EXIF orientation tag (values 1-8) describing the rotation and/or mirroring a
/// viewer must apply to show the image upright. Because this package strips
/// metadata from its output, the orientation has to be baked into the pixels to
/// survive the conversion.
enum ExifOrientationPolicy {
  /// Bake the source's EXIF orientation into the output pixels so the result is
  /// visually upright on every platform. The output carries no orientation
  /// metadata, so it displays consistently everywhere. This is the default.
  ///
  /// When a 90 or 270 degree rotation is applied the displayed width and height
  /// swap; the resize mode is evaluated against the oriented (display)
  /// dimensions, not the raw buffer dimensions.
  apply,

  /// Ignore the EXIF orientation tag and encode the decoded pixel buffer as-is.
  /// Use this to keep the raw pixel layout when orientation is handled elsewhere
  /// or known to be absent.
  ignore,
}
