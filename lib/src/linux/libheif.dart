import 'dart:ffi';

/// `struct heif_error` (libheif `heif_error.h`): returned by value from
/// `heif_init`.
final class _HeifError extends Struct {
  @Int32()
  external int code;

  @Int32()
  external int subcode;

  external Pointer<Void> message;
}

/// `heif_compression_AV1` (libheif `heif_context.h`).
const int _heifCompressionAv1 = 4;

/// Whether libheif, as installed on this system, has an AV1 encoder.
///
/// glycin encodes AVIF in its HEIF loader with libheif, which takes its AV1
/// encoder from a plugin (e.g. `libheif-plugin-aomenc`). libheif is opened
/// from the same system library path the loader uses, and `heif_init` loads
/// the plugins from libheif's default plugin path, as it does for the loader.
/// Returns `false` when libheif itself cannot be opened.
bool libheifHasAv1Encoder() {
  final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open('libheif.so.1');
  } on ArgumentError {
    return false;
  }
  final heifInit = lib
      .lookupFunction<
        _HeifError Function(Pointer<Void>),
        _HeifError Function(Pointer<Void>)
      >('heif_init');
  final heifDeinit = lib.lookupFunction<Void Function(), void Function()>(
    'heif_deinit',
  );
  final heifHaveEncoderForFormat = lib
      .lookupFunction<Int32 Function(Int32), int Function(int)>(
        'heif_have_encoder_for_format',
      );

  // heif_init/heif_deinit are reference counted; the error code is
  // heif_error_Ok (0) on success.
  if (heifInit(nullptr).code != 0) return false;
  try {
    return heifHaveEncoderForFormat(_heifCompressionAv1) != 0;
  } finally {
    heifDeinit();
  }
}
