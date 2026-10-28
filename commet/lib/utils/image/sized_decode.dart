import 'dart:typed_data';
import 'dart:ui' hide ImageDecoderCallback;

import 'package:commet/utils/image/engine_crops_target_size.dart';
import 'package:commet/utils/image/heif_decode.dart';
import 'package:commet/utils/platform_image_types.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/painting.dart' show ImageDecoderCallback;

/// Vommet: decodes [bytes] with [decode] at the size [getTargetSize] picks
/// for the image's intrinsic size, never larger than the image itself.
/// Where the engine would crop instead of resize (see
/// [engineCropsTargetSize]) the image is decoded at its own size and scaled
/// down here, the way the engine does it on the other paths.
Future<Codec> decodeAtTargetSize(
  ImageDecoderCallback decode,
  Uint8List bytes,
  TargetImageSize Function(int intrinsicWidth, int intrinsicHeight)
      getTargetSize,
) async {
  // Vommet issue 813: HEIC on Linux/Windows, via the system's decoder.
  if (PlatformImageTypes.transcodesHeif && looksLikeHeif(bytes)) {
    bytes = await compute(decodeHeifToBmp, bytes) ?? bytes;
  }
  final buffer = await ImmutableBuffer.fromUint8List(exactBytes(bytes));
  if (!engineCropsTargetSize) {
    return decode(buffer, getTargetSize: getTargetSize);
  }

  TargetImageSize? target;
  final codec = await decode(buffer, getTargetSize: (width, height) {
    target = getTargetSize(width, height);
    return const TargetImageSize();
  });
  return _ScalingCodec(codec, target);
}

/// Vommet: [bytes] in a buffer of their own on the web. Outside Chromium the
/// engine decodes through an <img> element fed with a Blob of `bytes.buffer`,
/// the whole underlying buffer rather than the view, so a download that is a
/// view into a larger buffer gave the browser extra bytes around the image.
Uint8List exactBytes(Uint8List bytes) {
  if (!kIsWeb) return bytes;
  if (bytes.offsetInBytes == 0 && bytes.buffer.lengthInBytes == bytes.length) {
    return bytes;
  }
  return Uint8List.fromList(bytes);
}

/// The size [target] asks for an image of [width] x [height], or null to
/// keep the image as it is (no target, the same size, or larger: the
/// engine's decoders don't upscale either).
(int, int)? scaledSize(int width, int height, TargetImageSize? target) {
  var targetWidth = target?.width;
  var targetHeight = target?.height;
  if (targetWidth == null && targetHeight == null) return null;
  targetWidth ??= (width * targetHeight! / height).round();
  targetHeight ??= (height * targetWidth / width).round();
  if (targetWidth == width && targetHeight == height) return null;
  if (targetWidth > width || targetHeight > height) return null;
  if (targetWidth <= 0 || targetHeight <= 0) return null;
  return (targetWidth, targetHeight);
}

class _ScalingCodec implements Codec {
  _ScalingCodec(this._codec, this._target);

  final Codec _codec;
  final TargetImageSize? _target;

  @override
  int get frameCount => _codec.frameCount;

  @override
  int get repetitionCount => _codec.repetitionCount;

  @override
  void dispose() => _codec.dispose();

  @override
  Future<FrameInfo> getNextFrame() async {
    final frame = await _codec.getNextFrame();
    final image = frame.image;
    final size = scaledSize(image.width, image.height, _target);
    if (size == null) return frame;

    final (width, height) = size;
    final recorder = PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final scaled = picture.toImageSync(width, height);
    picture.dispose();
    image.dispose();
    return _ScaledFrame(frame.duration, scaled);
  }
}

class _ScaledFrame implements FrameInfo {
  _ScaledFrame(this.duration, this.image);

  @override
  final Duration duration;

  @override
  final Image image;
}
