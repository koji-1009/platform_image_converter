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
/// | avif   | §         |         | ¶       | #     |     |
///
/// † Windows HEIC output requires the OS HEVC/HEIF codec (Windows 11 22H2+, or
///   the Store "HEVC Video Extensions"); otherwise it throws an
///   `UnsupportedFormatException` with reason `codecUnavailable`.
///
/// ‡ Linux WebP/HEIC output requires a *writable* GdkPixbuf loader module (e.g.
///   `webp-pixbuf-loader`; the libheif GdkPixbuf loader only decodes, so it
///   does not enable HEIC output), which varies by distribution; otherwise it
///   throws an `UnsupportedFormatException` with reason `codecUnavailable`.
///
/// # Linux AVIF output requires a writable `avif` GdkPixbuf format: a GdkPixbuf
///   built with glycin provides one, which needs a libheif AV1 encoder plugin
///   (e.g. `libheif-plugin-aomenc`); otherwise a loader module such as
///   `libavif-gdk-pixbuf` provides it. Without them it throws an
///   `UnsupportedFormatException` with reason `codecUnavailable`.
///
/// § iOS/macOS AVIF output requires an AVIF encoder in ImageIO; otherwise it
///   throws an `UnsupportedFormatException` with reason `codecUnavailable`.
///
/// ¶ Windows AVIF output requires the Store "HEIF Image Extension" and a Media
///   Foundation AV1 encoder. Windows ships no software AV1 encoder (the Store
///   "AV1 Video Extension" only decodes); GPU drivers for hardware with AV1
///   encoding can provide one. Otherwise it throws an
///   `UnsupportedFormatException` with reason `codecUnavailable`.
///
/// **Notes:**
/// - [jpeg]: Good compression with adjustable quality
/// - [png]: Lossless compression, supports transparency
/// - [webp]: Modern format with better compression than JPEG
/// - [heic]: High Efficiency Image Format, not supported on Android or Web
/// - [avif]: AV1 Image File Format, not supported on Android or Web
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
  /// HEVC/HEIF codec is present), and on Linux (where a writable `heif`
  /// GdkPixbuf loader is installed; the libheif GdkPixbuf loader only
  /// decodes); not supported on Android or Web.
  heic,

  /// AVIF format (.avif)
  /// AV1 Image File Format. Output on iOS/macOS (where ImageIO provides an
  /// AVIF encoder), on Windows (where the HEIF codec and an AV1 encoder are
  /// present), and
  /// on Linux (where GdkPixbuf has a writable `avif` format with an AV1
  /// encoder); not supported on Android or Web.
  avif,
}
