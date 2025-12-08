/// Output image format for conversion.
///
/// Specifies the target format when converting images.
///
/// **Format Support:**
/// | Format | iOS/macOS | Android | Web |
/// |--------|-----------|---------| ----|
/// | jpeg   | ✓         | ✓       | ✓   |
/// | png    | ✓         | ✓       | ✓   |
/// | webp   |           | ✓       | ✓   |
/// | heic   | ✓         |         |     |
///
/// **Notes:**
/// - [jpeg]: Good compression with adjustable quality
/// - [png]: Lossless compression, supports transparency
/// - [webp]: Modern format with better compression than JPEG
/// - [heic]: High Efficiency Image Format, not supported on Android
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
  /// High Efficiency Image Format (not supported on Android and Web)
  heic,
}
