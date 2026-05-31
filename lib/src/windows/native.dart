import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:platform_image_converter/src/image_conversion_exception.dart';
import 'package:platform_image_converter/src/image_converter_platform_interface.dart';
import 'package:platform_image_converter/src/output_format.dart';
import 'package:platform_image_converter/src/output_resize.dart';
import 'package:platform_image_converter/src/windows/wic.dart';

extension on Pointer<Void> {
  /// Registers this COM object to be released (`IUnknown::Release`) when [arena]
  /// is released, mirroring the Darwin backend's `releasedBy` (CFRelease).
  ///
  /// The arena tears down when the enclosing `using` returns — which is *before*
  /// the outer `CoUninitialize` — so every Release runs before COM is torn down,
  /// without a manual cleanup list. Skips `nullptr`; the create call's own
  /// null/HRESULT check surfaces the failure.
  void releasedBy(Arena arena) {
    if (this != nullptr) arena.onReleaseAll(() => comRelease(this));
  }
}

/// Windows image converter built on the Windows Imaging Component (WIC), the
/// modern COM imaging stack in `windowscodecs.dll`.
///
/// Mirrors the other backends' strategy: decode with the platform stack, always
/// re-render through a fixed 8-bit-per-channel BGRA surface (normalizing
/// 16-bit / grayscale / indexed / CMYK sources) and scale in the same pass,
/// then encode.
///
/// **Pipeline:**
/// - `IWICStream::InitializeFromMemory`: wrap the input bytes
/// - `CreateDecoderFromStream` → `GetFrame`: decode
/// - `IWICFormatConverter`: normalize to 32bpp BGRA
/// - `IWICBitmapScaler` (high-quality cubic): resize when needed
/// - `CreateEncoder` → `IWICBitmapFrameEncode::WriteSource`: encode into memory
///
/// **Output formats:**
/// - JPEG and PNG: always available (built-in WIC codecs).
/// - HEIC: available where the OS ships the HEVC/HEIF codec — Windows 11 22H2+
///   out of the box, older Windows via the Store "HEVC Video Extensions". When
///   the codec is missing or fails to initialize, `CreateEncoder` reports it and
///   we throw an [UnsupportedFormatException] with reason `codecUnavailable`
///   (graceful degradation rather than a hard crash).
/// - WebP: not supported — Windows ships a WebP *decoder* but no encoder.
final class ImageConverterWindows implements ImageConverterPlatform {
  const ImageConverterWindows();

  @override
  Uint8List convert({
    required Uint8List inputData,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 100,
    ResizeMode resizeMode = const OriginalResizeMode(),
  }) {
    // Reject unsupported output before any native side effect (CoInitialize)
    if (format == .webp) {
      throw UnsupportedFormatException(
        format,
        UnsupportedFormatReason.platformUnsupported,
        'WebP output is not supported on Windows: the OS provides a WebP '
        'decoder but no encoder.',
      );
    }

    // WIC is COM; initialize it on the calling thread (an isolate worker when
    // run via `compute`), then balance it according to the HRESULT. `hresult`
    // normalizes the signed Int32 so high-bit codes (rpcEChangedMode) compare.
    final initHr = hresult(coInitializeEx(nullptr, coinitMultithreaded));
    final mustUninitialize = switch (initHr) {
      sOk || sFalse => true,
      rpcEChangedMode => false,
      _ => throw ImageConversionException(
        'Failed to initialize COM (0x${initHr.toRadixString(16)}).',
      ),
    };

    try {
      return using((arena) {
        final (lossy, container) = switch (format) {
          .jpeg => (true, containerFormatJpeg(arena)),
          .png => (false, containerFormatPng(arena)),
          .heic => (true, containerFormatHeif(arena)),
          .webp => throw StateError(
            'unreachable: WebP is rejected before COM init',
          ),
        };

        // InitializeFromMemory references (does not copy) the buffer, so it must
        // outlive the decode — the arena keeps it alive for the whole call.
        final inputPtr = arena<Uint8>(inputData.length);
        inputPtr.asTypedList(inputData.length).setAll(0, inputData);

        final factory = createImagingFactory(arena)..releasedBy(arena);
        if (factory == nullptr) {
          throw const ImageConversionException(
            'Failed to create WIC imaging factory.',
          );
        }

        // Create the encoder up front. A missing or unusable codec (notably
        // HEVC/HEIF, which not every Windows ships) is reported by CreateEncoder,
        // so checking it here — before any decode/normalize/resize — rejects an
        // unsupported format without wasting work, matching the other backends
        // which reject unsupported output before touching the image.
        final pEncoder = arena<Pointer<Void>>();
        final encoderHr = hresult(
          wicCreateEncoder(factory, container, pEncoder),
        );
        if (encoderHr == wincodecErrComponentNotFound ||
            encoderHr == wincodecErrComponentInitializeFailure) {
          throw UnsupportedFormatException(
            format,
            UnsupportedFormatReason.codecUnavailable,
            '${format.name.toUpperCase()} encoding is unavailable on this '
            'Windows: the required codec is not available. HEIC needs the '
            'HEVC/HEIF codec (Windows 11 22H2+ ships it; older Windows can '
            'install "HEVC Video Extensions" from the Microsoft Store).',
          );
        }
        if (encoderHr != sOk) {
          throw ImageEncodingException(
            format,
            'Failed to create ${format.name} encoder '
            '(0x${encoderHr.toRadixString(16)}).',
          );
        }
        final encoder = pEncoder.value..releasedBy(arena);

        // Wrap the input bytes in an IWICStream.
        final pStream = arena<Pointer<Void>>();
        if (wicCreateStream(factory, pStream) != sOk) {
          throw const ImageConversionException(
            'Failed to create input stream.',
          );
        }
        final inStream = pStream.value..releasedBy(arena);
        if (wicStreamInitializeFromMemory(
              inStream,
              inputPtr,
              inputData.length,
            ) !=
            sOk) {
          throw const ImageConversionException(
            'Failed to initialize input stream from image data.',
          );
        }

        // Decode the first frame.
        final pDecoder = arena<Pointer<Void>>();
        if (wicCreateDecoderFromStream(factory, inStream, pDecoder) != sOk) {
          throw const ImageDecodingException('Invalid image data.');
        }
        final decoder = pDecoder.value..releasedBy(arena);
        final pFrame = arena<Pointer<Void>>();
        if (wicDecoderGetFrame(decoder, 0, pFrame) != sOk) {
          throw const ImageDecodingException();
        }
        final frame = pFrame.value..releasedBy(arena);

        final widthPtr = arena<Uint32>();
        final heightPtr = arena<Uint32>();
        if (wicGetSize(frame, widthPtr, heightPtr) != sOk) {
          throw const ImageDecodingException('Failed to read image size.');
        }
        final (newWidth, newHeight) = resizeMode.calculateSize(
          widthPtr.value,
          heightPtr.value,
        );

        // Normalize to a fixed 32bpp premultiplied-BGRA surface: output no
        // longer depends on the source pixel format, and alpha is interpolated
        // in the correct (premultiplied) space when scaling. Premultiplied
        // transparent pixels carry RGB 0, so flattening to a no-alpha format
        // (JPEG) drops to black instead of leaking the source's stored RGB.
        // The flatten color is backend-defined and not guaranteed identical
        // across platforms. The PNG/HEIC encoders restore straight alpha.
        final pConverter = arena<Pointer<Void>>();
        if (wicCreateFormatConverter(factory, pConverter) != sOk) {
          throw const ImageConversionException(
            'Failed to create pixel-format converter.',
          );
        }
        final converter = pConverter.value..releasedBy(arena);
        if (wicConverterInitialize(
              converter,
              frame,
              pixelFormat32bppPBGRA(arena),
            ) !=
            sOk) {
          throw const ImageConversionException(
            'Failed to normalize source pixel format.',
          );
        }

        // Scale only when the target size differs (high-quality cubic).
        var source = converter;
        if (newWidth != widthPtr.value || newHeight != heightPtr.value) {
          final pScaler = arena<Pointer<Void>>();
          if (wicCreateBitmapScaler(factory, pScaler) != sOk) {
            throw const ImageConversionException(
              'Failed to create bitmap scaler.',
            );
          }
          final scaler = pScaler.value..releasedBy(arena);
          if (wicScalerInitialize(scaler, converter, newWidth, newHeight) !=
              sOk) {
            throw const ImageConversionException('Failed to resize image.');
          }
          source = scaler;
        }

        // Growable in-memory output stream.
        final pOut = arena<Pointer<Void>>();
        if (createStreamOnHGlobal(nullptr, fDeleteOnRelease, pOut) != sOk ||
            pOut.value == nullptr) {
          throw const ImageConversionException(
            'Failed to create output stream.',
          );
        }
        final outStream = pOut.value..releasedBy(arena);
        if (wicEncoderInitialize(encoder, outStream) != sOk) {
          throw ImageEncodingException(format, 'Failed to initialize encoder.');
        }

        // Create the frame and (for lossy formats) set the quality.
        final pFrameEncode = arena<Pointer<Void>>();
        final pPropertyBag = arena<Pointer<Void>>();
        if (wicEncoderCreateNewFrame(encoder, pFrameEncode, pPropertyBag) !=
            sOk) {
          throw ImageEncodingException(format, 'Failed to create frame.');
        }
        final frameEncode = pFrameEncode.value..releasedBy(arena);
        final propertyBag = pPropertyBag.value..releasedBy(arena);

        if (lossy) {
          // quality is validated 1..100 by the public API; WIC wants 0..1.
          if (propertyBag == nullptr) {
            throw ImageEncodingException(
              format,
              'Encoder did not provide an options bag to set quality.',
            );
          }
          if (writeImageQuality(arena, propertyBag, quality / 100.0) != sOk) {
            throw ImageEncodingException(
              format,
              'Failed to set ${format.name} encoder quality.',
            );
          }
        }
        if (wicFrameInitialize(frameEncode, propertyBag) != sOk) {
          throw ImageEncodingException(format, 'Failed to initialize frame.');
        }
        if (wicFrameSetSize(frameEncode, newWidth, newHeight) != sOk) {
          throw ImageEncodingException(format, 'Failed to set output size.');
        }
        if (wicFrameWriteSource(frameEncode, source) != sOk) {
          throw ImageEncodingException(
            format,
            'Failed to encode image to ${format.name}.',
          );
        }
        if (wicFrameCommit(frameEncode) != sOk ||
            wicEncoderCommit(encoder) != sOk) {
          throw ImageEncodingException(
            format,
            'Failed to finalize ${format.name} output.',
          );
        }

        return _readStreamBytes(arena, outStream, format);
      });
    } finally {
      if (mustUninitialize) coUninitialize();
    }
  }

  /// Reads every byte written to [stream] back into a Dart [Uint8List]. The
  /// exact length comes from seeking to the end (the backing `HGLOBAL` is
  /// rounded up, so its allocated size cannot be trusted).
  Uint8List _readStreamBytes(
    Arena arena,
    Pointer<Void> stream,
    OutputFormat format,
  ) {
    final sizePtr = arena<Uint64>();
    if (comSeek(stream, 0, streamSeekEnd, sizePtr) != sOk) {
      throw ImageEncodingException(format, 'Failed to size encoded output.');
    }
    final length = sizePtr.value;

    final hGlobalPtr = arena<Pointer<Void>>();
    if (getHGlobalFromStream(stream, hGlobalPtr) != sOk) {
      throw ImageEncodingException(format, 'Failed to read encoded output.');
    }

    final dataPtr = globalLock(hGlobalPtr.value);
    if (dataPtr == nullptr) {
      throw ImageEncodingException(format, 'Failed to lock encoded output.');
    }
    try {
      return Uint8List.fromList(dataPtr.asTypedList(length));
    } finally {
      globalUnlock(hGlobalPtr.value);
    }
  }
}
