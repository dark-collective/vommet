// Vommet issue 880: turning part of a video into a GIF; Vommet issue 936:
// the faster encoder.
import 'dart:math';
import 'dart:typed_data';

import 'package:commet/ui/organisms/attachment_processor/video_gif_trim.dart';
import 'package:commet/utils/gif_writer.dart';
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

/// A [w]×[h] packed RGB frame, all one color.
Uint8List _rgb(int w, int h, int r, int g, int b) {
  final bytes = Uint8List(w * h * 3);
  for (var i = 0; i < bytes.length; i += 3) {
    bytes[i] = r;
    bytes[i + 1] = g;
    bytes[i + 2] = b;
  }
  return bytes;
}

/// The 216 web colors and 39 between them: far enough apart that the
/// dither never moves a pixel that is one of them to another.
Uint8List _webPalette() {
  final p = <int>[];
  for (var r = 0; r < 6; r++) {
    for (var g = 0; g < 6; g++) {
      for (var b = 0; b < 6; b++) {
        p.addAll([r * 51, g * 51, b * 51]);
      }
    }
  }
  for (var i = 0; p.length < GifWriter.colors * 3; i++) {
    p.addAll([25 + 51 * (i ~/ 25), 25 + 51 * (i ~/ 5 % 5), 25 + 51 * (i % 5)]);
  }
  return Uint8List.fromList(p);
}

/// The frames as shown: each GIF frame drawn over the one before.
/// (package:image's own decode doesn't keep the frame before under a
/// partial or transparent frame; Flutter, browsers and ffmpeg do.)
List<(img.Image, int)> _shown(Uint8List gif) {
  final decoder = img.GifDecoder()..startDecode(gif);
  final info = decoder.info!;
  final canvas = img.Image(width: info.width, height: info.height);
  final shown = <(img.Image, int)>[];
  for (var i = 0; i < info.numFrames; i++) {
    final frame = info.frames[i];
    final part = decoder.decodeFrame(i)!;
    for (final p in part) {
      if (p.a != 0) canvas.setPixel(p.x + frame.x, p.y + frame.y, p);
    }
    shown.add((canvas.clone(), frame.duration * 10));
  }
  return shown;
}

void _expectFrame(img.Image decoded, Uint8List rgb) {
  for (var y = 0; y < decoded.height; y++) {
    for (var x = 0; x < decoded.width; x++) {
      final p = decoded.getPixel(x, y);
      final i = (y * decoded.width + x) * 3;
      if (p.r != rgb[i] || p.g != rgb[i + 1] || p.b != rgb[i + 2]) {
        fail("pixel ($x, $y) is ${[p.r, p.g, p.b]}, "
            "not ${rgb.sublist(i, i + 3)}");
      }
    }
  }
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
    expect(frame.length, 10 * 5 * 3);
    final i = (2 * 10 + 3) * 3;
    expect(frame.sublist(i, i + 3), [200, 100, 50]);
  });

  test("frame delays keep 12 fps in GIF's 1/100 s", () {
    final delays = VideoGif.frameDelays(12);
    expect(delays.reduce((a, b) => a + b), 100);
    expect(delays.toSet(), {8, 9});
    expect(VideoGif.clipLength(120), const Duration(seconds: 10));
  });

  test("encoded screenshots shrink to at most 480 px", () {
    final jpeg = img.encodeJpg(img.Image(width: 960, height: 540));
    final small = VideoGif.shrinkEncoded(jpeg)!;
    expect((small.width, small.height), (480, 270));
    expect(small.numChannels, 3);
  });

  test("the GIF loops through every frame", () {
    final frames = [
      for (final c in [0, 120, 240]) _rgb(8, 6, c, 0, 255 - c),
    ];
    final gif = VideoGif.encode(frames, 8, 6);
    final decoded = img.decodeGif(gif)!;
    expect(decoded.numFrames, 3);
    expect(decoded.width, 8);
    expect(decoded.loopCount, 0);
    expect([for (final f in decoded.frames) f.frameDuration], [80, 90, 80]);
    for (var i = 0; i < 3; i++) {
      final p = decoded.frames[i].getPixel(4, 3);
      final c = [0, 120, 240][i];
      expect((p.r - c).abs() < 12 && p.g < 12 && (p.b - (255 - c)).abs() < 12,
          isTrue,
          reason: "frame $i is ${[p.r, p.g, p.b]}");
    }
  });

  test("the GIF's pixels survive LZW exactly, through every code width", () {
    // Noise from 255 colors: thousands of codes, so the dictionary fills
    // and starts over many times.
    final palette = _webPalette();
    final random = Random(936);
    const w = 257, h = 199;
    Uint8List noise() {
      final f = Uint8List(w * h * 3);
      for (var i = 0; i < w * h; i++) {
        final c = random.nextInt(GifWriter.colors) * 3;
        f.setRange(i * 3, i * 3 + 3, palette, c);
      }
      return f;
    }

    // Then frames that change only in a box, and long flat runs.
    final first = noise();
    final second = Uint8List.fromList(first);
    for (var y = 50; y < 90; y++) {
      for (var x = 100; x < 180; x++) {
        if ((x + y) % 3 == 0)
          second.setRange(
              (y * w + x) * 3, (y * w + x) * 3 + 3, const [255, 0, 0]);
      }
    }
    final flat = _rgb(w, h, 0, 51, 102);
    final frames = [first, second, flat, noise()];

    final writer = GifWriter(w, h, palette);
    for (final f in frames) {
      writer.addFrame(f, 8);
    }
    final shown = _shown(writer.finish());
    expect(shown.length, frames.length);
    for (var i = 0; i < frames.length; i++) {
      _expectFrame(shown[i].$1, frames[i]);
    }
  });

  test("an unchanged frame makes the one before it longer", () {
    final palette = _webPalette();
    final a = _rgb(16, 16, 255, 255, 255), b = _rgb(16, 16, 0, 0, 0);
    final writer = GifWriter(16, 16, palette)
      ..addFrame(a, 8)
      ..addFrame(a, 9)
      ..addFrame(b, 8)
      ..addFrame(b, 8);
    final shown = _shown(writer.finish());
    expect([for (final f in shown) f.$2], [170, 160]);
    _expectFrame(shown[0].$1, a);
    _expectFrame(shown[1].$1, b);
  });

  test("the GIF carries no metadata", () {
    final gif = VideoGif.encode([_rgb(4, 4, 10, 20, 30)], 4, 4);
    // Extensions are 0x21 then a label: only graphic control (0xF9) and
    // the looping application block (0xFF NETSCAPE2.0) may appear.
    final text = String.fromCharCodes(gif);
    expect(text.contains("NETSCAPE2.0"), isTrue);
    for (var i = 0; i + 1 < gif.length; i++) {
      if (gif[i] == 0x21)
        expect(gif[i + 1] != 0xFE && gif[i + 1] != 0x01, isTrue);
    }
  });

  test("a clip's palette follows its colors", () {
    final frames = [
      for (var i = 0; i < 4; i++) _rgb(32, 32, 200, 30 + i * 40, 10),
    ];
    final palette = GifWriter.learnPalette(frames, 32, 32);
    expect(palette.length, GifWriter.colors * 3);
    bool near(int r, int g, int b) {
      for (var c = 0; c < palette.length; c += 3) {
        if ((palette[c] - r).abs() +
                (palette[c + 1] - g).abs() +
                (palette[c + 2] - b).abs() <
            12) return true;
      }
      return false;
    }

    for (var i = 0; i < 4; i++) {
      expect(near(200, 30 + i * 40, 10), isTrue, reason: "color $i");
    }
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
