import 'dart:math';
import 'dart:typed_data';

import 'package:commet/utils/gif_writer.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

/// Vommet issue 880: turning part of a video into a GIF in the attachment
/// dialog. Fixed limits, no settings: at most [maxClip] long, the longest
/// side at most [longestEdge] px, [fps] frames a second, no sound.
class VideoGif {
  static const maxClip = Duration(seconds: 10);
  static const minClip = Duration(milliseconds: 500);
  static const longestEdge = 480;
  static const fps = 12;

  /// How long each of [count] frames shows, in 1/100 s (GIF's unit).
  /// 12 fps doesn't divide evenly, so it's 8, 8, 9, 8, 8, 9… to keep time.
  static List<int> frameDelays(int count) => [
        for (var i = 0; i < count; i++)
          ((i + 1) * 100 / fps).round() - (i * 100 / fps).round()
      ];

  /// How long [count] frames play for.
  static Duration clipLength(int count) =>
      Duration(milliseconds: (count * 1000 / fps).round());

  /// The times to grab a frame at, from [start] up to (not including) [end],
  /// at most [maxClip] worth.
  static List<Duration> frameTimes(Duration start, Duration end) {
    if (end > start + maxClip) end = start + maxClip;
    final step = 1000000 / fps;
    final times = <Duration>[];
    for (var i = 0;; i++) {
      final t = start + Duration(microseconds: (i * step).round());
      if (t >= end) break;
      times.add(t);
    }
    if (times.isEmpty) times.add(start);
    return times;
  }

  /// The size a [width]×[height] video becomes, never larger than it was.
  static (int, int) targetSize(int width, int height,
      {int edge = longestEdge}) {
    final longest = max(width, height);
    if (longest <= edge) return (width, height);
    final scale = edge / longest;
    return (max(1, (width * scale).round()), max(1, (height * scale).round()));
  }

  /// The (width, height, stride) of a raw BGRA screenshot of [length]
  /// bytes. libmpv doesn't say, so try each size the player reported
  /// (pixel size, display size, either way round for rotated videos) and
  /// take the first whose rows fit. Null when none does.
  static (int, int, int)? rawLayout(int length, List<(int, int)> candidates) {
    for (final (w, h) in candidates) {
      if (w <= 0 || h <= 0 || length % h != 0) continue;
      final stride = length ~/ h;
      if (stride >= w * 4 && stride <= w * 4 + 256) return (w, h, stride);
    }
    return null;
  }

  /// A raw BGRA frame (as libmpv's screenshot-raw gives it, alpha ignored)
  /// shrunk to [targetWidth]×[targetHeight] packed RGB by averaging each
  /// block.
  static Uint8List downscaleBgra(Uint8List bytes, int width, int height,
      int stride, int targetWidth, int targetHeight) {
    final out = Uint8List(targetWidth * targetHeight * 3);
    var o = 0;
    for (var y = 0; y < targetHeight; y++) {
      final y0 = y * height ~/ targetHeight;
      final y1 = max(y0 + 1, (y + 1) * height ~/ targetHeight);
      for (var x = 0; x < targetWidth; x++) {
        final x0 = x * width ~/ targetWidth;
        final x1 = max(x0 + 1, (x + 1) * width ~/ targetWidth);
        var r = 0, g = 0, b = 0, n = 0;
        for (var yy = y0; yy < y1; yy++) {
          var i = yy * stride + x0 * 4;
          for (var xx = x0; xx < x1; xx++, i += 4) {
            b += bytes[i];
            g += bytes[i + 1];
            r += bytes[i + 2];
            n++;
          }
        }
        out[o++] = r ~/ n;
        out[o++] = g ~/ n;
        out[o++] = b ~/ n;
      }
    }
    return out;
  }

  /// [image] as packed RGB, resized to [width]×[height] if it isn't.
  static Uint8List rgbBytes(img.Image image, int width, int height) {
    if (image.width != width || image.height != height) {
      image = img.copyResize(image,
          width: width,
          height: height,
          interpolation: img.Interpolation.average);
    }
    return image
        .convert(format: img.Format.uint8, numChannels: 3)
        .getBytes(order: img.ChannelOrder.rgb);
  }

  /// An encoded picture (the web player's JPEG screenshot) at most
  /// [edge] px on its longest side, without alpha.
  static img.Image? shrinkEncoded(Uint8List data, {int edge = longestEdge}) {
    final decoded = img.decodeImage(data);
    if (decoded == null) return null;
    final (w, h) = targetSize(decoded.width, decoded.height, edge: edge);
    final resized = w == decoded.width && h == decoded.height
        ? decoded
        : img.copyResize(decoded,
            width: w, height: h, interpolation: img.Interpolation.average);
    return resized.convert(numChannels: 3);
  }

  /// A looping GIF of [frames], packed RGB at [width]×[height], at [fps].
  static Uint8List encode(List<Uint8List> frames, int width, int height) =>
      GifWriter.encodeClip(frames, width, height, frameDelays(frames.length));

  /// "clip.mp4" becomes "clip.gif".
  static String gifName(String? videoName) {
    final base = path.basenameWithoutExtension(videoName?.trim() ?? "");
    return "${base.isEmpty ? "video" : base}.gif";
  }
}
