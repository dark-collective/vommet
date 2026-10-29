// Vommet issue 880: turning part of a video into a GIF.
import 'dart:typed_data';

import 'package:commet/ui/organisms/attachment_processor/video_gif_trim.dart';
import 'package:commet/utils/video_gif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A [w]×[h] BGRA frame, rows padded to [stride], all one color.
Uint8List _bgra(int w, int h, int stride, int r, int g, int b) {
  final bytes = Uint8List(stride * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * stride + x * 4;
      bytes[i] = b;
      bytes[i + 1] = g;
      bytes[i + 2] = r;
      bytes[i + 3] = 0;
    }
  }
  return bytes;
}

void main() {
  test("frame times step at 12 fps and stop at 10 s", () {
    final times =
        VideoGif.frameTimes(Duration.zero, const Duration(seconds: 1));
    expect(times.length, 12);
    expect(times.first, Duration.zero);
    expect(times[1].inMicroseconds, 83333);

    final long = VideoGif.frameTimes(
        const Duration(seconds: 5), const Duration(seconds: 60));
    expect(long.length, 120);
    expect(long.last < const Duration(seconds: 15), isTrue);

    expect(
        VideoGif.frameTimes(
            const Duration(seconds: 3), const Duration(seconds: 3)),
        [const Duration(seconds: 3)]);
  });

  test("target size keeps the shape, at most 480 px, never larger", () {
    expect(VideoGif.targetSize(1920, 1080), (480, 270));
    expect(VideoGif.targetSize(1080, 1920), (270, 480));
    expect(VideoGif.targetSize(320, 240), (320, 240));
  });

  test("raw screenshot layout picks the size whose rows fit", () {
    // The first size whose rows fit wins.
    expect(VideoGif.rawLayout(1080 * 4 * 1920, [(1000, 1000), (1080, 1920)]),
        (1080, 1920, 4320));
    // Padded rows.
    expect(
        VideoGif.rawLayout((100 * 4 + 16) * 50, [(100, 50)]), (100, 50, 416));
    expect(VideoGif.rawLayout(123, [(100, 50)]), isNull);
  });

  test("raw BGRA frames shrink to the GIF size with the right colors", () {
    final frame = VideoGif.downscaleBgra(
        _bgra(40, 20, 176, 200, 100, 50), 40, 20, 176, 10, 5);
    expect(frame.width, 10);
    expect(frame.height, 5);
    final p = frame.getPixel(3, 2);
    expect([p.r, p.g, p.b], [200, 100, 50]);
  });

  test("encoded screenshots shrink to at most 480 px", () {
    final jpeg = img.encodeJpg(img.Image(width: 960, height: 540));
    final small = VideoGif.shrinkEncoded(jpeg)!;
    expect((small.width, small.height), (480, 270));
    expect(small.numChannels, 3);
  });

  test("the GIF loops through every frame", () {
    final frames = [
      for (final c in [0, 120, 240])
        img.Image(width: 8, height: 6)..clear(img.ColorRgb8(c, 0, 255 - c)),
    ];
    var done = 0;
    final gif = VideoGif.encode(frames, onFrame: (n) => done = n);
    expect(done, 3);
    final decoded = img.decodeGif(gif)!;
    expect(decoded.numFrames, 3);
    expect(decoded.width, 8);
    expect(decoded.frames.first.frameDuration, 80);
  });

  test("the GIF is named after the video", () {
    expect(VideoGif.gifName("clip.mp4"), "clip.gif");
    expect(VideoGif.gifName("my.holiday.webm"), "my.holiday.gif");
    expect(VideoGif.gifName(null), "video.gif");
    expect(VideoGif.gifName(""), "video.gif");
  });

  test("trim times read as minutes, seconds and tenths", () {
    expect(
        VideoGifTrim.formatTime(const Duration(milliseconds: 4230)), "0:04.2");
    expect(VideoGifTrim.formatTime(const Duration(seconds: 75)), "1:15.0");
  });
}
