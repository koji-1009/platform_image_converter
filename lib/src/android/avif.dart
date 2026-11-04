import 'dart:io' as io;
import 'dart:typed_data';

import 'package:jni/jni.dart';
import 'package:platform_image_converter/src/android/bindings.g.dart';
import 'package:platform_image_converter/src/image_conversion_exception.dart';
import 'package:platform_image_converter/src/output_format.dart';

/// The API level that added the AV1 encoder and `image/avif` tracks in
/// `MediaMuxer`: AVIF can only be written from Android 14 on.
const sdkAvifEncoding = 34;

/// `Build.VERSION_CODES_FULL.BAKLAVA_1`: Android 16 QPR2 (SDK 36.1).
const _sdkFullAndroid16Qpr2 = 3600001;

/// Whether `MediaMuxer` can write AVIF on a device at API level [sdkInt].
///
/// Android 16 before QPR2 (SDK 36.0) applies the minimum `hvcC` size of HEVC
/// to every HEIF image track, so it drops the 4-byte `av1C` of an AVIF track
/// and writes no image items. `SDK_INT_FULL` (API 36+) tells the releases
/// apart.
bool canEncodeAvif(int sdkInt) =>
    sdkInt >= sdkAvifEncoding &&
    (sdkInt != 36 || Build$VERSION.SDK_INT_FULL >= _sdkFullAndroid16Qpr2);

/// Side of the square tiles a larger image is split into, as `AvifWriter`
/// (androidx.heifwriter) does: every AV1 encoder supports frames this size.
const _tileSize = 512;

/// How long one dequeue call waits for the codec.
const _dequeueTimeoutUs = 10000;

/// How long the codec may go without accepting input or producing output
/// before the encode is abandoned.
const _stallTimeout = Duration(seconds: 10);

const _mimeAv1 = 'video/av01';
const _mimeAvif = 'image/avif';

/// Encodes [bitmap] as AVIF with the platform's AV1 encoder and `MediaMuxer`,
/// which writes the HEIF container. Every JNI object is registered in [arena].
///
/// The image is always stored as a HEIF grid of AV1 tiles: [_tileSize] tiles
/// for a larger image, or one tile rounded up to even dimensions (AV1 4:2:0
/// frames have even sizes) for a smaller one. The grid's output size crops
/// the tiles back to the image, so any image size is stored exactly.
///
/// Pixels are converted to 8-bit BT.601 full-range YUV 4:2:0. AVIF written
/// this way has no alpha channel: premultiplied transparent pixels become
/// black, as for JPEG output.
Uint8List encodeAvif(Arena arena, Bitmap bitmap, int quality) {
  final width = bitmap.width;
  final height = bitmap.height;
  final useTiles = width > _tileSize || height > _tileSize;
  final tileWidth = useTiles ? _tileSize : _roundUpToEven(width);
  final tileHeight = useTiles ? _tileSize : _roundUpToEven(height);
  final layout = _TileLayout(
    width: width,
    height: height,
    tileWidth: tileWidth,
    tileHeight: tileHeight,
  );

  final encoder = _findEncoder(arena, tileWidth, tileHeight);
  if (encoder == null) {
    throw UnsupportedFormatException(
      OutputFormat.avif,
      .codecUnavailable,
      'AVIF encoding is unavailable on this device: no AV1 encoder supports '
      '${tileWidth}x$tileHeight frames.',
    );
  }

  final pixels = _rgbaPixels(arena, bitmap);

  final codec = MediaCodec.createByCodecName(
    encoder.name.toJString()..releasedBy(arena),
  )?..releasedBy(arena);
  if (codec == null) {
    throw ImageEncodingException(
      OutputFormat.avif,
      'Failed to create AV1 encoder ${encoder.name}.',
    );
  }

  final tempFile = File.createTempFile(
    'platform_image_converter'.toJString()..releasedBy(arena),
    '.avif'.toJString()..releasedBy(arena),
  )?..releasedBy(arena);
  final tempPath = tempFile?.absolutePath?.toDartString(releaseOriginal: true);
  if (tempPath == null) {
    codec.release$1();
    throw ImageEncodingException(
      OutputFormat.avif,
      'Failed to create a temporary file for the AVIF output.',
    );
  }

  MediaMuxer? muxer;
  var codecStarted = false;
  var muxerStarted = false;
  try {
    codec.configure(
      _codecFormat(arena, encoder, layout, quality),
      null,
      null,
      MediaCodec.CONFIGURE_FLAG_ENCODE,
    );
    codec.start();
    codecStarted = true;

    muxer = MediaMuxer.new$1(
      tempPath.toJString()..releasedBy(arena),
      MediaMuxer$OutputFormat.MUXER_OUTPUT_HEIF,
    )..releasedBy(arena);

    muxerStarted = _encodeTiles(arena, codec, muxer, layout, pixels);
    muxer.stop();
    muxerStarted = false;
    return io.File(tempPath).readAsBytesSync();
  } on JThrowable catch (e) {
    // MediaCodec and MediaMuxer report failures as Java exceptions
    // (e.g. MediaCodec.CodecException, IllegalStateException).
    throw ImageEncodingException(
      OutputFormat.avif,
      'Failed to encode AVIF: ${e.message}',
    );
  } finally {
    if (muxerStarted) {
      try {
        muxer?.stop();
      } on JThrowable {
        // Already failing; the original error is the one to report.
      }
    }
    muxer?.release$1();
    if (codecStarted) codec.stop();
    codec.release$1();
    tempFile?.delete();
  }
}

/// The grid an image of [width]x[height] is split into.
final class _TileLayout {
  _TileLayout({
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
  }) : columns = (width + tileWidth - 1) ~/ tileWidth,
       rows = (height + tileHeight - 1) ~/ tileHeight;

  final int width;
  final int height;
  final int tileWidth;
  final int tileHeight;
  final int columns;
  final int rows;

  int get tileCount => columns * rows;
}

/// An AV1 encoder chosen by [_findEncoder].
final class _Encoder {
  _Encoder(this.name, this.capabilities);

  final String name;
  final MediaCodecInfo$CodecCapabilities capabilities;

  MediaCodecInfo$EncoderCapabilities get _encoderCapabilities =>
      capabilities.encoderCapabilities!;

  bool get supportsConstantQuality =>
      _encoderCapabilities.isBitrateModeSupported(
        MediaCodecInfo$EncoderCapabilities.BITRATE_MODE_CQ,
      );
}

/// Finds an AV1 encoder that accepts [tileWidth]x[tileHeight] frames,
/// preferring one with a constant-quality bitrate mode (as `AvifWriter` does),
/// or `null` when the device has none.
_Encoder? _findEncoder(Arena arena, int tileWidth, int tileHeight) {
  final mime = _mimeAv1.toJString()..releasedBy(arena);
  final list = MediaCodecList(MediaCodecList.REGULAR_CODECS)..releasedBy(arena);
  final infos = list.codecInfos?..releasedBy(arena);
  if (infos == null) return null;

  _Encoder? fallback;
  for (var i = 0; i < infos.length; i++) {
    final info = infos[i]?..releasedBy(arena);
    if (info == null || !info.isEncoder || !_supportsType(arena, info)) {
      continue;
    }
    final capabilities = info.getCapabilitiesForType(mime)?..releasedBy(arena);
    final video = capabilities?.videoCapabilities?..releasedBy(arena);
    if (capabilities == null ||
        video == null ||
        !video.isSizeSupported(tileWidth, tileHeight)) {
      continue;
    }
    final name = info.name?.toDartString(releaseOriginal: true);
    if (name == null) continue;
    final encoder = _Encoder(name, capabilities);
    if (encoder.supportsConstantQuality) return encoder;
    fallback ??= encoder;
  }
  return fallback;
}

/// Whether [info] lists the AV1 type, checked before asking for its
/// capabilities (which throws for an unsupported type).
bool _supportsType(Arena arena, MediaCodecInfo info) {
  final types = info.supportedTypes?..releasedBy(arena);
  if (types == null) return false;
  for (var i = 0; i < types.length; i++) {
    final type = types[i]?.toDartString(releaseOriginal: true);
    if (type != null && type.toLowerCase() == _mimeAv1) return true;
  }
  return false;
}

/// The encoder configuration: one tile per frame, 8-bit BT.601 full-range
/// YUV input, and [quality] (1-100) mapped onto the encoder's
/// constant-quality range, or onto a bitrate when it has no such mode.
MediaFormat _codecFormat(
  Arena arena,
  _Encoder encoder,
  _TileLayout layout,
  int quality,
) {
  JString key(JString? Function() field) => field()!..releasedBy(arena);

  final format = MediaFormat.createVideoFormat(
    _mimeAv1.toJString()..releasedBy(arena),
    layout.tileWidth,
    layout.tileHeight,
  )!..releasedBy(arena);
  format
    ..setInteger(
      key(() => MediaFormat.KEY_COLOR_FORMAT),
      MediaCodecInfo$CodecCapabilities.COLOR_FormatYUV420Flexible,
    )
    // Every tile is a key frame: each is a separate image item.
    ..setInteger(key(() => MediaFormat.KEY_I_FRAME_INTERVAL), 0)
    ..setInteger(key(() => MediaFormat.KEY_FRAME_RATE), layout.tileCount)
    ..setInteger(
      key(() => MediaFormat.KEY_COLOR_STANDARD),
      MediaFormat.COLOR_STANDARD_BT601_NTSC,
    )
    ..setInteger(
      key(() => MediaFormat.KEY_COLOR_RANGE),
      MediaFormat.COLOR_RANGE_FULL,
    )
    ..setInteger(
      key(() => MediaFormat.KEY_COLOR_TRANSFER),
      MediaFormat.COLOR_TRANSFER_SDR_VIDEO,
    );

  final encoderCapabilities = encoder.capabilities.encoderCapabilities!
    ..releasedBy(arena);
  if (encoder.supportsConstantQuality) {
    final range = encoderCapabilities.qualityRange!..releasedBy(arena);
    final lower = range.lower!..releasedBy(arena);
    final upper = range.upper!..releasedBy(arena);
    final low = lower.intValue();
    final high = upper.intValue();
    format
      ..setInteger(
        key(() => MediaFormat.KEY_BITRATE_MODE),
        MediaCodecInfo$EncoderCapabilities.BITRATE_MODE_CQ,
      )
      ..setInteger(
        key(() => MediaFormat.KEY_QUALITY),
        low + (high - low) * quality ~/ 100,
      );
  } else {
    // The bits for one image, as `AvifWriter` computes them: the frame rate
    // is the tile count, so this is the budget for the whole grid.
    final video = encoder.capabilities.videoCapabilities!..releasedBy(arena);
    final range = video.bitrateRange!..releasedBy(arena);
    final lower = range.lower!..releasedBy(arena);
    final upper = range.upper!..releasedBy(arena);
    final bitrate =
        (layout.width * layout.height * 1.5 * 8 * 0.25 * quality / 100)
            .round()
            .clamp(lower.intValue(), upper.intValue());
    format
      ..setInteger(
        key(() => MediaFormat.KEY_BITRATE_MODE),
        MediaCodecInfo$EncoderCapabilities.BITRATE_MODE_VBR,
      )
      ..setInteger(key(() => MediaFormat.KEY_BIT_RATE), bitrate);
  }
  return format;
}

/// Feeds every tile of [pixels] to [codec], then end of stream, and writes
/// the encoded tiles to [muxer] as one grid image. Returns whether the muxer
/// was started (it is, once the encoder reports its output format).
bool _encodeTiles(
  Arena arena,
  MediaCodec codec,
  MediaMuxer muxer,
  _TileLayout layout,
  Uint8List pixels,
) {
  final info = MediaCodec$BufferInfo()..releasedBy(arena);
  var nextTile = 0;
  var inputDone = false;
  var muxerStarted = false;
  var track = -1;
  var written = 0;
  var lastProgress = DateTime.now();

  while (true) {
    if (!inputDone) {
      final index = codec.dequeueInputBuffer(_dequeueTimeoutUs);
      if (index >= 0) {
        lastProgress = DateTime.now();
        // Presentation times only order the tiles; one image spans 1 s.
        final timeUs = nextTile * 1000000 ~/ layout.tileCount;
        if (nextTile < layout.tileCount) {
          final image = codec.getInputImage(index)!..releasedBy(arena);
          _writeTile(arena, image, layout, nextTile, pixels);
          image.close();
          final buffer = codec.getInputBuffer(index)!..releasedBy(arena);
          codec.queueInputBuffer(index, 0, buffer.capacity, timeUs, 0);
          nextTile++;
        } else {
          codec.queueInputBuffer(
            index,
            0,
            0,
            timeUs,
            MediaCodec.BUFFER_FLAG_END_OF_STREAM,
          );
          inputDone = true;
        }
      }
    }

    final index = codec.dequeueOutputBuffer(info, _dequeueTimeoutUs);
    if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
      lastProgress = DateTime.now();
      final format = codec.outputFormat!..releasedBy(arena);
      _describeGrid(arena, format, layout);
      track = muxer.addTrack(format);
      muxer.start();
      muxerStarted = true;
    } else if (index >= 0) {
      lastProgress = DateTime.now();
      final isConfig = info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0;
      if (info.size > 0 && !isConfig) {
        if (!muxerStarted) {
          throw ImageEncodingException(
            OutputFormat.avif,
            'The AV1 encoder produced data before its output format.',
          );
        }
        if (written < layout.tileCount) {
          final buffer = codec.getOutputBuffer(index)!..releasedBy(arena);
          muxer.writeSampleData(track, buffer, info);
          written++;
        }
      }
      codec.releaseOutputBuffer(index, false);
      if (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break;
    } else if (DateTime.now().difference(lastProgress) > _stallTimeout) {
      throw ImageEncodingException(
        OutputFormat.avif,
        'The AV1 encoder stopped responding.',
      );
    }
  }

  if (written != layout.tileCount) {
    throw ImageEncodingException(
      OutputFormat.avif,
      'The AV1 encoder produced $written of ${layout.tileCount} tiles.',
    );
  }
  return muxerStarted;
}

/// Turns the encoder's output format into the AVIF image track `MediaMuxer`
/// expects, as `AvifWriter` does: the `image/avif` type, the image's size,
/// and the grid of tiles that make it up.
void _describeGrid(Arena arena, MediaFormat format, _TileLayout layout) {
  JString key(JString? Function() field) => field()!..releasedBy(arena);

  format
    ..setString(
      key(() => MediaFormat.KEY_MIME),
      _mimeAvif.toJString()..releasedBy(arena),
    )
    ..setInteger(key(() => MediaFormat.KEY_WIDTH), layout.width)
    ..setInteger(key(() => MediaFormat.KEY_HEIGHT), layout.height)
    ..setInteger(key(() => MediaFormat.KEY_TILE_WIDTH), layout.tileWidth)
    ..setInteger(key(() => MediaFormat.KEY_TILE_HEIGHT), layout.tileHeight)
    ..setInteger(key(() => MediaFormat.KEY_GRID_ROWS), layout.rows)
    ..setInteger(key(() => MediaFormat.KEY_GRID_COLUMNS), layout.columns)
    // The single image is the primary item.
    ..setInteger(key(() => MediaFormat.KEY_IS_DEFAULT), 1);
}

/// Copies [bitmap]'s pixels out as tightly packed 8-bit RGBA, converting it to
/// `ARGB_8888` first when it has another configuration. `ARGB_8888` stores
/// R, G, B, A bytes in that order, premultiplied by alpha.
Uint8List _rgbaPixels(Arena arena, Bitmap bitmap) {
  final argb8888 = Bitmap$Config.ARGB_8888..releasedBy(arena);
  final config = bitmap.config?..releasedBy(arena);
  var source = bitmap;
  if (config == null || config != argb8888) {
    source = bitmap.copy(argb8888, false)!..releasedBy(arena);
  }
  final rowBytes = source.width * 4;
  final buffer = JByteBuffer.allocateDirect(rowBytes * source.height)
    ..releasedBy(arena);
  source.copyPixelsToBuffer(buffer);
  return Uint8List.fromList(buffer.asUint8List());
}

/// Writes tile [tileIndex] (row-major) of [pixels] into the encoder input
/// [image] as YUV 4:2:0. Samples past the image's right and bottom edges
/// repeat the edge pixels; the grid crops them away.
void _writeTile(
  Arena arena,
  Image image,
  _TileLayout layout,
  int tileIndex,
  Uint8List pixels,
) {
  final planes = image.planes!..releasedBy(arena);
  final yPlane = planes[0]!..releasedBy(arena);
  final uPlane = planes[1]!..releasedBy(arena);
  final vPlane = planes[2]!..releasedBy(arena);
  final y = (yPlane.buffer!..releasedBy(arena)).asUint8List();
  final u = (uPlane.buffer!..releasedBy(arena)).asUint8List();
  final v = (vPlane.buffer!..releasedBy(arena)).asUint8List();
  final yRowStride = yPlane.rowStride;
  final yPixelStride = yPlane.pixelStride;
  final uRowStride = uPlane.rowStride;
  final uPixelStride = uPlane.pixelStride;
  final vRowStride = vPlane.rowStride;
  final vPixelStride = vPlane.pixelStride;

  final left = (tileIndex % layout.columns) * layout.tileWidth;
  final top = (tileIndex ~/ layout.columns) * layout.tileHeight;
  final maxX = layout.width - 1;
  final maxY = layout.height - 1;
  final stride = layout.width * 4;

  int offset(int x, int y) {
    final sx = left + x > maxX ? maxX : left + x;
    final sy = top + y > maxY ? maxY : top + y;
    return sy * stride + sx * 4;
  }

  // Luma: one sample per pixel. BT.601 full range (JFIF), fixed point.
  for (var ty = 0; ty < layout.tileHeight; ty++) {
    final row = ty * yRowStride;
    for (var tx = 0; tx < layout.tileWidth; tx++) {
      final p = offset(tx, ty);
      final r = pixels[p];
      final g = pixels[p + 1];
      final b = pixels[p + 2];
      y[row + tx * yPixelStride] = (77 * r + 150 * g + 29 * b + 128) >> 8;
    }
  }

  // Chroma: one sample per 2x2 block, from the block's average color.
  for (var cy = 0; cy < layout.tileHeight ~/ 2; cy++) {
    for (var cx = 0; cx < layout.tileWidth ~/ 2; cx++) {
      var r = 0;
      var g = 0;
      var b = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final p = offset(cx * 2 + dx, cy * 2 + dy);
          r += pixels[p];
          g += pixels[p + 1];
          b += pixels[p + 2];
        }
      }
      r = (r + 2) >> 2;
      g = (g + 2) >> 2;
      b = (b + 2) >> 2;
      u[cy * uRowStride + cx * uPixelStride] = _clamp(
        ((-43 * r - 85 * g + 128 * b + 128) >> 8) + 128,
      );
      v[cy * vRowStride + cx * vPixelStride] = _clamp(
        ((128 * r - 107 * g - 21 * b + 128) >> 8) + 128,
      );
    }
  }
}

int _clamp(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);

int _roundUpToEven(int value) => (value + 1) & ~1;
