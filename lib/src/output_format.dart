/// Output image format for conversion.
///
/// Specifies the target format when converting images.
///
/// **Format Support:**
/// | Format | iOS/macOS | Android | Windows | Linux | Web |
/// |--------|-----------|---------|---------|-------| ----|
/// | jpeg   | ✓         | ✓       | ✓       | ✓     | ✓   |
/// | png    | ✓         | ✓       | ✓       | ✓     | ✓   |
/// | webp   |           | ✓       |         | ‡     | ✓   |
/// | heic   | ✓         |         | ✓†      | ‡     |     |
///
/// † Windows HEIC output requires the OS HEVC/HEIF codec (Windows 11 22H2+, or
///   the Store "HEVC Video Extensions"); otherwise it throws an
///   `UnsupportedFormatException` with reason `codecUnavailable`.
///
/// ‡ Linux WebP/HEIC output requires a *writable* GdkPixbuf loader module (e.g.
///   `webp-pixbuf-loader`, or the libheif GdkPixbuf loader), which varies by
///   distribution; otherwise it throws an `UnsupportedFormatException` with
///   reason `codecUnavailable`.
///
/// **Notes:**
/// - [jpeg]: Good compression with adjustable quality
/// - [png]: Lossless compression, supports transparency
/// - [webp]: Modern format with better compression than JPEG
/// - [heic]: High Efficiency Image Format, not supported on Android or Web
enum OutputFormat {
  /// JPEG format (.jpg, .jpeg)
  /// Lossy compression, suitable for photos
  jpeg,

  /// PNG format (.png)
  /// Lossless compression, supports transparency
  png,

  /// WebP format (.webp)
  /// Modern format with superior compression. Not supported on Darwin/Windows;
  /// on Linux it requires a writable GdkPixbuf WebP loader.
  webp,

  /// HEIC format (.heic)
  /// High Efficiency Image Format. Output on Darwin, on Windows (where the OS
  /// HEVC/HEIF codec is present), and on Linux (where a writable libheif
  /// GdkPixbuf loader is installed); not supported on Android or Web.
  heic,
}
