// Field/parameter names deliberately mirror the Win32 / WIC C names.
// ignore_for_file: non_constant_identifier_names
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Hand-written FFI bindings for the Windows Imaging Component (WIC) — the
/// modern, COM-based imaging stack (`windowscodecs.dll`) that decodes, scales
/// and encodes images, including HEIC where the OS ships the HEVC/HEIF codec
/// (Windows 11 22H2+ out of the box; older Windows via the Store extension).
///
/// These are written by hand by necessity, not convenience. No code generator
/// emits this surface:
///   * ffigen parses C only; WIC is pure COM (vtable dispatch), which ffigen
///     cannot model.
///   * The `win32` package (generated from win32metadata) does not include the
///     WIC interfaces at all (verified against 6.3.0).
/// So every call below is dispatched by reading the function pointer at a fixed
/// vtable slot of the COM object (its first field is the pointer to its vtable).
/// The slot indices are taken verbatim from the SDK's `wincodec.h` `*Vtbl`
/// structs — they are part of the COM ABI and never change for a shipped
/// interface.
///
/// All symbols are resolved lazily, so the `DynamicLibrary.open` calls only run
/// on Windows (the converter is only instantiated for `TargetPlatform.windows`).

// ---------------------------------------------------------------------------
// System libraries (COM + memory helpers)
// ---------------------------------------------------------------------------

final DynamicLibrary _ole32 = DynamicLibrary.open('ole32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

/// `S_OK`.
const int sOk = 0;

/// `S_FALSE` — a success HRESULT (`SUCCEEDED(S_FALSE)` is true). From
/// `CoInitializeEx` it means COM was already initialized on this thread with the
/// same apartment: the call still took a reference that must be balanced with
/// `CoUninitialize`.
const int sFalse = 1;

/// `WINCODEC_ERR_COMPONENTNOTFOUND` — returned by `CreateEncoder` when no codec
/// for the requested container is installed (e.g. HEIF without the HEVC codec).
const int wincodecErrComponentNotFound = 0x88982F50;

/// `WINCODEC_ERR_COMPONENTINITIALIZEFAILURE` — `CreateEncoder` found the codec's
/// registration but it failed to initialize. For HEIF this is what Windows
/// returns when the container handler is registered yet the underlying HEVC
/// codec is missing (seen on GitHub-hosted runners and any machine without the
/// Microsoft Store "HEVC Video Extensions"). The codec is unusable here, same
/// as [wincodecErrComponentNotFound].
const int wincodecErrComponentInitializeFailure = 0x88982F8B;

/// `COINIT_MULTITHREADED` (0) — the apartment requested from `CoInitializeEx`.
/// WIC's in-proc codecs are used synchronously on a single thread, so MTA is
/// sufficient (and is COM's default concurrency model).
const int coinitMultithreaded = 0;

/// `RPC_E_CHANGED_MODE` — `CoInitializeEx` when COM is already up on this thread
/// with a different apartment. COM is usable; we just must not balance-uninit.
const int rpcEChangedMode = 0x80010106;

/// `STREAM_SEEK_END` for `IStream::Seek`.
const int streamSeekEnd = 2;

/// `fDeleteOnRelease = TRUE` for `CreateStreamOnHGlobal` — the stream owns its
/// backing `HGLOBAL` and frees it when released.
const int fDeleteOnRelease = 1;

/// `CLSCTX_INPROC_SERVER`.
const int _clsctxInprocServer = 1;

// CoInitializeEx(NULL, COINIT_MULTITHREADED) / CoUninitialize.
final int Function(Pointer<Void>, int) coInitializeEx = _ole32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)
    >('CoInitializeEx');
final void Function() coUninitialize = _ole32
    .lookupFunction<Void Function(), void Function()>('CoUninitialize');

final int Function(
  Pointer<Uint8> rclsid,
  Pointer<Void> pUnkOuter,
  int dwClsContext,
  Pointer<Uint8> riid,
  Pointer<Pointer<Void>> ppv,
)
coCreateInstance = _ole32
    .lookupFunction<
      Int32 Function(
        Pointer<Uint8>,
        Pointer<Void>,
        Uint32,
        Pointer<Uint8>,
        Pointer<Pointer<Void>>,
      ),
      int Function(
        Pointer<Uint8>,
        Pointer<Void>,
        int,
        Pointer<Uint8>,
        Pointer<Pointer<Void>>,
      )
    >('CoCreateInstance');

/// `CreateStreamOnHGlobal(NULL, TRUE, &stream)` — a growable in-memory output
/// `IStream` whose backing `HGLOBAL` is freed when the stream is released.
final int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)
createStreamOnHGlobal = _ole32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Int32, Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)
    >('CreateStreamOnHGlobal');

/// `GetHGlobalFromStream` — recovers the `HGLOBAL` backing the output stream.
final int Function(Pointer<Void>, Pointer<Pointer<Void>>) getHGlobalFromStream =
    _ole32.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, Pointer<Pointer<Void>>)
    >('GetHGlobalFromStream');

final Pointer<Uint8> Function(Pointer<Void>) globalLock = _kernel32
    .lookupFunction<
      Pointer<Uint8> Function(Pointer<Void>),
      Pointer<Uint8> Function(Pointer<Void>)
    >('GlobalLock');
final int Function(Pointer<Void>) globalUnlock = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'GlobalUnlock',
    );

// ---------------------------------------------------------------------------
// GUIDs
// ---------------------------------------------------------------------------

/// Allocates a 16-byte Windows `GUID`/`CLSID` in [arena] from its canonical
/// components (`Data1` LE u32, `Data2`/`Data3` LE u16, `Data4` 8 raw bytes).
Pointer<Uint8> guid(Arena arena, int d1, int d2, int d3, List<int> d4) {
  final p = arena<Uint8>(16);
  p[0] = d1 & 0xff;
  p[1] = (d1 >> 8) & 0xff;
  p[2] = (d1 >> 16) & 0xff;
  p[3] = (d1 >> 24) & 0xff;
  p[4] = d2 & 0xff;
  p[5] = (d2 >> 8) & 0xff;
  p[6] = d3 & 0xff;
  p[7] = (d3 >> 8) & 0xff;
  for (var i = 0; i < 8; i++) {
    p[8 + i] = d4[i];
  }
  return p;
}

Pointer<Uint8> clsidWicImagingFactory(Arena a) => guid(
  a,
  0xCACAF262,
  0x9370,
  0x4615,
  const [0xA1, 0x3B, 0x9F, 0x55, 0x39, 0xDA, 0x4C, 0x0A],
);
Pointer<Uint8> iidWicImagingFactory(Arena a) => guid(
  a,
  0xEC5EC8A9,
  0xC395,
  0x4314,
  const [0x9C, 0x77, 0x54, 0xD7, 0xA9, 0x35, 0xFF, 0x70],
);

Pointer<Uint8> containerFormatJpeg(Arena a) => guid(
  a,
  0x19E4A5AA,
  0x5662,
  0x4FC5,
  const [0xA0, 0xC0, 0x17, 0x58, 0x02, 0x8E, 0x10, 0x57],
);
Pointer<Uint8> containerFormatPng(Arena a) => guid(
  a,
  0x1B7CFAF4,
  0x713F,
  0x473C,
  const [0xBB, 0xCD, 0x61, 0x37, 0x42, 0x5F, 0xAE, 0xAF],
);
Pointer<Uint8> containerFormatHeif(Arena a) => guid(
  a,
  0xE1E62521,
  0x6787,
  0x405B,
  const [0xA3, 0x39, 0x50, 0x07, 0x15, 0xB5, 0x76, 0x3F],
);

/// `GUID_WICPixelFormat32bppPBGRA` — 8-bit premultiplied alpha; the fixed
/// surface every source is normalized into. Premultiplied alpha is the correct
/// space to interpolate in when scaling, and makes fully-transparent pixels
/// carry RGB 0 so flattening to a no-alpha format (JPEG) drops to black rather
/// than leaking the source's stored RGB. The flatten color is backend-defined
/// and not guaranteed identical across platforms.
Pointer<Uint8> pixelFormat32bppPBGRA(Arena a) => guid(
  a,
  0x6FDDC324,
  0x4E03,
  0x4BFE,
  const [0xB1, 0x85, 0x3D, 0x77, 0x76, 0x8D, 0xC9, 0x10],
);

// ---------------------------------------------------------------------------
// Enum values (from wincodec.h)
// ---------------------------------------------------------------------------

const int wicDecodeMetadataCacheOnDemand = 0;
const int wicBitmapDitherTypeNone = 0;
const int wicBitmapPaletteTypeCustom = 0;
const int wicBitmapInterpolationModeHighQualityCubic = 4;
const int wicBitmapEncoderNoCache = 2;

// ---------------------------------------------------------------------------
// COM vtable dispatch
//
// Each wrapper reads the function pointer at the method's fixed vtable slot and
// invokes it. `asFunction` requires statically-known native/Dart signatures, so
// each call spells out its own concrete types.
// ---------------------------------------------------------------------------

/// Treats a signed `Int32` HRESULT as its unsigned 32-bit value, so it can be
/// compared against high-bit-set codes like [wincodecErrComponentNotFound].
int hresult(int raw) => raw & 0xFFFFFFFF;

/// Address of the function pointer at vtable [index] of COM object [obj]. Each
/// slot is one pointer wide (`sizeOf<IntPtr>()` — 8 on the 64-bit-only Windows
/// targets Flutter supports).
int _slot(Pointer<Void> obj, int index) => Pointer<IntPtr>.fromAddress(
  obj.cast<IntPtr>().value + index * sizeOf<IntPtr>(),
).value;

/// `IUnknown::Release` (vtable slot 2), on every WIC/COM object.
int comRelease(Pointer<Void> obj) =>
    Pointer<NativeFunction<Uint32 Function(Pointer<Void>)>>.fromAddress(
      _slot(obj, 2),
    ).asFunction<int Function(Pointer<Void>)>()(obj);

/// `IStream::Seek` (slot 5) — used with [streamSeekEnd] to size the output.
int comSeek(Pointer<Void> obj, int move, int origin, Pointer<Uint64> newPos) =>
    Pointer<
          NativeFunction<
            Int32 Function(Pointer<Void>, Int64, Uint32, Pointer<Uint64>)
          >
        >.fromAddress(_slot(obj, 5))
        .asFunction<int Function(Pointer<Void>, int, int, Pointer<Uint64>)>()(
      obj,
      move,
      origin,
      newPos,
    );

// ---- IWICImagingFactory ----

/// `CreateStream` (slot 14) → an empty `IWICStream`.
int wicCreateStream(Pointer<Void> factory, Pointer<Pointer<Void>> out) =>
    Pointer<
          NativeFunction<Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>)>
        >.fromAddress(_slot(factory, 14))
        .asFunction<int Function(Pointer<Void>, Pointer<Pointer<Void>>)>()(
      factory,
      out,
    );

/// `CreateDecoderFromStream` (slot 4). `pguidVendor` and options are null/0.
int wicCreateDecoderFromStream(
  Pointer<Void> factory,
  Pointer<Void> stream,
  Pointer<Pointer<Void>> out,
) =>
    Pointer<
          NativeFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Void>,
              Uint32,
              Pointer<Pointer<Void>>,
            )
          >
        >.fromAddress(_slot(factory, 4))
        .asFunction<
          int Function(
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Void>,
            int,
            Pointer<Pointer<Void>>,
          )
        >()(factory, stream, nullptr, wicDecodeMetadataCacheOnDemand, out);

/// `CreateFormatConverter` (slot 10).
int wicCreateFormatConverter(
  Pointer<Void> factory,
  Pointer<Pointer<Void>> out,
) =>
    Pointer<
          NativeFunction<Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>)>
        >.fromAddress(_slot(factory, 10))
        .asFunction<int Function(Pointer<Void>, Pointer<Pointer<Void>>)>()(
      factory,
      out,
    );

/// `CreateBitmapScaler` (slot 11).
int wicCreateBitmapScaler(Pointer<Void> factory, Pointer<Pointer<Void>> out) =>
    Pointer<
          NativeFunction<Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>)>
        >.fromAddress(_slot(factory, 11))
        .asFunction<int Function(Pointer<Void>, Pointer<Pointer<Void>>)>()(
      factory,
      out,
    );

/// `CreateEncoder` (slot 8). Reports a missing or unusable codec for
/// [containerGuid] via [wincodecErrComponentNotFound] (not registered) or
/// [wincodecErrComponentInitializeFailure] (registered but fails to initialize).
int wicCreateEncoder(
  Pointer<Void> factory,
  Pointer<Uint8> containerGuid,
  Pointer<Pointer<Void>> out,
) =>
    Pointer<
          NativeFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Pointer<Void>,
              Pointer<Pointer<Void>>,
            )
          >
        >.fromAddress(_slot(factory, 8))
        .asFunction<
          int Function(
            Pointer<Void>,
            Pointer<Uint8>,
            Pointer<Void>,
            Pointer<Pointer<Void>>,
          )
        >()(factory, containerGuid, nullptr, out);

// ---- IWICStream ----

/// `InitializeFromMemory` (slot 16). Does NOT copy — [buffer] must outlive use.
int wicStreamInitializeFromMemory(
  Pointer<Void> stream,
  Pointer<Uint8> buffer,
  int size,
) =>
    Pointer<
          NativeFunction<Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32)>
        >.fromAddress(_slot(stream, 16))
        .asFunction<int Function(Pointer<Void>, Pointer<Uint8>, int)>()(
      stream,
      buffer,
      size,
    );

// ---- IWICBitmapDecoder ----

/// `GetFrame` (slot 13).
int wicDecoderGetFrame(
  Pointer<Void> decoder,
  int index,
  Pointer<Pointer<Void>> out,
) =>
    Pointer<
          NativeFunction<
            Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Void>>)
          >
        >.fromAddress(_slot(decoder, 13))
        .asFunction<int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)>()(
      decoder,
      index,
      out,
    );

// ---- IWICBitmapSource (frame / converter / scaler) ----

/// `GetSize` (slot 3).
int wicGetSize(Pointer<Void> src, Pointer<Uint32> w, Pointer<Uint32> h) =>
    Pointer<
          NativeFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>)
          >
        >.fromAddress(_slot(src, 3))
        .asFunction<
          int Function(Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>)
        >()(src, w, h);

// ---- IWICFormatConverter ----

/// `Initialize` (slot 8): convert [source] into [dstFormat] (no dither/palette).
int wicConverterInitialize(
  Pointer<Void> converter,
  Pointer<Void> source,
  Pointer<Uint8> dstFormat,
) =>
    Pointer<
          NativeFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Uint8>,
              Int32,
              Pointer<Void>,
              Double,
              Int32,
            )
          >
        >.fromAddress(_slot(converter, 8))
        .asFunction<
          int Function(
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Uint8>,
            int,
            Pointer<Void>,
            double,
            int,
          )
        >()(
      converter,
      source,
      dstFormat,
      wicBitmapDitherTypeNone,
      nullptr,
      0.0,
      wicBitmapPaletteTypeCustom,
    );

// ---- IWICBitmapScaler ----

/// `Initialize` (slot 8): scale [source] to [w]x[h] with high-quality cubic.
int wicScalerInitialize(
  Pointer<Void> scaler,
  Pointer<Void> source,
  int w,
  int h,
) =>
    Pointer<
          NativeFunction<
            Int32 Function(Pointer<Void>, Pointer<Void>, Uint32, Uint32, Int32)
          >
        >.fromAddress(_slot(scaler, 8))
        .asFunction<
          int Function(Pointer<Void>, Pointer<Void>, int, int, int)
        >()(scaler, source, w, h, wicBitmapInterpolationModeHighQualityCubic);

// ---- IWICBitmapEncoder ----

/// `Initialize` (slot 3): bind the encoder to an output [stream].
int wicEncoderInitialize(Pointer<Void> encoder, Pointer<Void> stream) =>
    Pointer<
          NativeFunction<Int32 Function(Pointer<Void>, Pointer<Void>, Int32)>
        >.fromAddress(_slot(encoder, 3))
        .asFunction<int Function(Pointer<Void>, Pointer<Void>, int)>()(
      encoder,
      stream,
      wicBitmapEncoderNoCache,
    );

/// `CreateNewFrame` (slot 10). Out-params: the frame encode and its property
/// bag (the latter receives encoder options like JPEG/HEIF `ImageQuality`).
int wicEncoderCreateNewFrame(
  Pointer<Void> encoder,
  Pointer<Pointer<Void>> frame,
  Pointer<Pointer<Void>> propertyBag,
) =>
    Pointer<
          NativeFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Pointer<Void>>,
              Pointer<Pointer<Void>>,
            )
          >
        >.fromAddress(_slot(encoder, 10))
        .asFunction<
          int Function(
            Pointer<Void>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
          )
        >()(encoder, frame, propertyBag);

/// `Commit` (slot 11).
int wicEncoderCommit(Pointer<Void> encoder) =>
    Pointer<NativeFunction<Int32 Function(Pointer<Void>)>>.fromAddress(
      _slot(encoder, 11),
    ).asFunction<int Function(Pointer<Void>)>()(encoder);

// ---- IWICBitmapFrameEncode ----

/// `Initialize` (slot 3) with the (optional) configured property bag.
int wicFrameInitialize(Pointer<Void> frame, Pointer<Void> propertyBag) =>
    Pointer<
          NativeFunction<Int32 Function(Pointer<Void>, Pointer<Void>)>
        >.fromAddress(_slot(frame, 3))
        .asFunction<int Function(Pointer<Void>, Pointer<Void>)>()(
      frame,
      propertyBag,
    );

/// `SetSize` (slot 4).
int wicFrameSetSize(Pointer<Void> frame, int w, int h) =>
    Pointer<
          NativeFunction<Int32 Function(Pointer<Void>, Uint32, Uint32)>
        >.fromAddress(_slot(frame, 4))
        .asFunction<int Function(Pointer<Void>, int, int)>()(frame, w, h);

/// `WriteSource` (slot 11): draw [source] into the frame (full rect → null).
int wicFrameWriteSource(Pointer<Void> frame, Pointer<Void> source) =>
    Pointer<
          NativeFunction<
            Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
          >
        >.fromAddress(_slot(frame, 11))
        .asFunction<
          int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
        >()(frame, source, nullptr);

/// `Commit` (slot 12).
int wicFrameCommit(Pointer<Void> frame) =>
    Pointer<NativeFunction<Int32 Function(Pointer<Void>)>>.fromAddress(
      _slot(frame, 12),
    ).asFunction<int Function(Pointer<Void>)>()(frame);

// ---- IPropertyBag2 ----

/// `Write` (slot 4): set [count] properties described by [propBag2]/[variant].
int propertyBagWrite(
  Pointer<Void> bag,
  int count,
  Pointer<Uint8> propBag2,
  Pointer<Uint8> variant,
) =>
    Pointer<
          NativeFunction<
            Int32 Function(
              Pointer<Void>,
              Uint32,
              Pointer<Uint8>,
              Pointer<Uint8>,
            )
          >
        >.fromAddress(_slot(bag, 4))
        .asFunction<
          int Function(Pointer<Void>, int, Pointer<Uint8>, Pointer<Uint8>)
        >()(bag, count, propBag2, variant);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates the `IWICImagingFactory`. Returns null on failure (caller throws).
Pointer<Void> createImagingFactory(Arena arena) {
  final pp = arena<Pointer<Void>>();
  final hr = coCreateInstance(
    clsidWicImagingFactory(arena),
    nullptr,
    _clsctxInprocServer,
    iidWicImagingFactory(arena),
    pp,
  );
  return hr == sOk ? pp.value : nullptr;
}

/// Writes a single `ImageQuality` float (0..1) into [bag] via a `PROPBAG2` +
/// `VARIANT` pair allocated in [arena]. Used for JPEG and HEIF (lossy) encoders.
int writeImageQuality(Arena arena, Pointer<Void> bag, double quality) {
  // VT_R4 == 4 (32-bit float), PROPBAG2_TYPE_DATA == 1.
  const vtR4 = 4;
  const propbag2TypeData = 1;

  // PROPBAG2 (64-bit layout, 40 bytes — identical on x64 and arm64 Windows):
  // dwType@0, vt@4, cfType@6, dwHint@8, pstrName@16, clsid@24. Zero it, then
  // set the fields the encoder reads.
  final pb = arena<Uint8>(40);
  pb.asTypedList(40).fillRange(0, 40, 0);
  pb.cast<Uint32>().value = propbag2TypeData; // dwType
  (pb + 4).cast<Uint16>().value = vtR4; // vt
  final name = 'ImageQuality'.toNativeUtf16(allocator: arena);
  (pb + 16).cast<IntPtr>().value = name.address; // pstrName

  // VARIANT (64-bit, 24 bytes): vt@0, fltVal@8.
  final v = arena<Uint8>(24);
  v.asTypedList(24).fillRange(0, 24, 0);
  v.cast<Uint16>().value = vtR4; // vt
  (v + 8).cast<Float>().value = quality;

  return propertyBagWrite(bag, 1, pb, v);
}
