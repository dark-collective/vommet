import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Vommet issue 936: a fast GIF encoder for a video clip.
///
/// package:image's GifEncoder learns a new palette for every frame and
/// error-diffuses it, which took ~20 s for a 10 s clip on a phone. This one
/// learns a single palette from the whole clip, maps pixels through a lookup
/// table with a fixed ordered dither (the same pixel gives the same index in
/// every frame, so still areas don't shimmer), and only stores the part of
/// each frame that changed, with unchanged pixels left transparent.
///
/// Frames are packed RGB bytes, [width]×[height]×3 each. Nothing but the
/// pictures and their timing is written: no comments or other metadata.
class GifWriter {
  GifWriter(this.width, this.height, this.palette)
      : assert(palette.length == colors * 3),
        _previous = Uint8List(width * height),
        _current = Uint8List(width * height);

  final int width;
  final int height;

  /// [colors] RGB triples; index [transparent] is kept for unchanged pixels.
  final Uint8List palette;

  static const colors = 255;
  static const transparent = 255;

  /// How far the ordered dither may move a channel (±half of this).
  static const ditherSpread = 12;

  /// Learns the palette from up to [samples] pixels spread over [frames].
  static Uint8List learnPalette(List<Uint8List> frames, int width, int height,
      {int samples = 120000}) {
    final pixels = width * height;
    final total = pixels * frames.length;
    final step = total <= samples ? 1 : total ~/ samples;
    final count = (total + step - 1) ~/ step;
    // NeuQuant reads an image; give it the samples as a strip.
    const stripWidth = 256;
    final strip = img.Image(
        width: stripWidth, height: (count + stripWidth - 1) ~/ stripWidth);
    final bytes = strip.buffer.asUint8List();
    var o = 0;
    for (var s = 0; s < total; s += step) {
      final f = frames[s ~/ pixels];
      final i = (s % pixels) * 3;
      bytes[o++] = f[i];
      bytes[o++] = f[i + 1];
      bytes[o++] = f[i + 2];
    }
    // Fill the strip's tail with the last sample so it doesn't pull the
    // palette towards black.
    while (o < bytes.length) {
      bytes[o] = bytes[o - 3];
      o++;
    }
    final quantizer =
        img.NeuralQuantizer(strip, numberOfColors: colors, samplingFactor: 1);
    final out = Uint8List(colors * 3);
    for (var c = 0; c < colors; c++) {
      out[c * 3] = quantizer.palette.getRed(c).toInt();
      out[c * 3 + 1] = quantizer.palette.getGreen(c).toInt();
      out[c * 3 + 2] = quantizer.palette.getBlue(c).toInt();
    }
    return out;
  }

  /// A whole clip at once, [delays] in 1/100 s (one per frame).
  static Uint8List encodeClip(
      List<Uint8List> frames, int width, int height, List<int> delays) {
    final writer =
        GifWriter(width, height, learnPalette(frames, width, height));
    for (var i = 0; i < frames.length; i++) {
      writer.addFrame(frames[i], delays[i]);
    }
    return writer.finish();
  }

  final _out = _ByteSink();
  final Uint8List _previous;
  final Uint8List _current;
  final _lut = Int16List(1 << 18)..fillRange(0, 1 << 18, -1);
  int _frames = 0;

  /// The last frame, held back until we know how long it shows for (an
  /// unchanged frame only makes the one before it longer).
  Uint8List? _pending;
  int _pendingDelay = 0;

  /// 4×4 Bayer matrix, centered on zero and scaled to [ditherSpread].
  static final Int8List _bayer = Int8List.fromList([
    for (final row in const [
      [0, 8, 2, 10],
      [12, 4, 14, 6],
      [3, 11, 1, 9],
      [15, 7, 13, 5],
    ])
      for (final v in row) ((v - 7.5) * ditherSpread / 16).round()
  ]);

  int _nearest(int r, int g, int b) {
    var best = 0, bestDistance = 1 << 30;
    for (var c = 0, p = 0; c < colors; c++, p += 3) {
      final dr = palette[p] - r,
          dg = palette[p + 1] - g,
          db = palette[p + 2] - b;
      // Weighted a little towards green, which the eye sees best.
      final d = 2 * dr * dr + 4 * dg * dg + 3 * db * db;
      if (d < bestDistance) {
        bestDistance = d;
        best = c;
        if (d == 0) break;
      }
    }
    return best;
  }

  void _map(Uint8List rgb) {
    final lut = _lut;
    final out = _current;
    for (var y = 0, i = 0, s = 0; y < height; y++) {
      final row = (y & 3) << 2;
      for (var x = 0; x < width; x++, i++, s += 3) {
        final d = _bayer[row | (x & 3)];
        final r = (rgb[s] + d).clamp(0, 255);
        final g = (rgb[s + 1] + d).clamp(0, 255);
        final b = (rgb[s + 2] + d).clamp(0, 255);
        final key = (r >> 2) << 12 | (g >> 2) << 6 | (b >> 2);
        var c = lut[key];
        if (c < 0) {
          // The middle of the 4×4×4 cell the key stands for.
          c = lut[key] = _nearest((r & ~3) | 2, (g & ~3) | 2, (b & ~3) | 2);
        }
        out[i] = c;
      }
    }
  }

  /// Adds a frame shown for [delay] 1/100 s.
  void addFrame(Uint8List rgb, int delay) {
    if (rgb.length < width * height * 3) {
      throw ArgumentError("frame is smaller than $width×$height");
    }
    _map(rgb);
    if (_frames == 0 && _pending == null) {
      _header();
      _pending = Uint8List.fromList(_current);
      _pendingDelay = delay;
      _previous.setAll(0, _current);
      return;
    }

    // The box around the pixels that changed since the shown frame.
    final cur = _current, prev = _previous;
    var left = width, right = -1, top = height, bottom = -1;
    for (var y = 0, i = 0; y < height; y++) {
      var rowLeft = -1, rowRight = -1;
      for (var x = 0; x < width; x++, i++) {
        if (cur[i] != prev[i]) {
          if (rowLeft < 0) rowLeft = x;
          rowRight = x;
        }
      }
      if (rowLeft >= 0) {
        if (rowLeft < left) left = rowLeft;
        if (rowRight > right) right = rowRight;
        if (top == height) top = y;
        bottom = y;
      }
    }
    if (right < 0) {
      // Nothing changed: show the previous frame for longer.
      _pendingDelay += delay;
      return;
    }

    _flush();
    final w = right - left + 1, h = bottom - top + 1;
    final part = Uint8List(w * h);
    for (var y = 0, o = 0; y < h; y++) {
      var i = (top + y) * width + left;
      for (var x = 0; x < w; x++, i++, o++) {
        final c = cur[i];
        if (c == prev[i]) {
          part[o] = transparent;
        } else {
          part[o] = c;
          prev[i] = c;
        }
      }
    }
    _pendingBox = (left, top, w, h);
    _pending = part;
    _pendingDelay = delay;
  }

  (int, int, int, int)? _pendingBox;

  void _flush() {
    final pixels = _pending;
    if (pixels == null) return;
    final (left, top, w, h) = _pendingBox ?? (0, 0, width, height);
    final first = _frames == 0;
    // Graphic control: leave the frame in place, transparency after the
    // first frame, and the delay.
    _out
      ..add(0x21)
      ..add(0xF9)
      ..add(4)
      ..add(1 << 2 | (first ? 0 : 1))
      ..addUint16(_pendingDelay.clamp(2, 65535))
      ..add(transparent)
      ..add(0)
      // Image descriptor, no local palette.
      ..add(0x2C)
      ..addUint16(left)
      ..addUint16(top)
      ..addUint16(w)
      ..addUint16(h)
      ..add(0);
    _lzw(pixels, _out);
    _frames++;
    _pending = null;
    _pendingBox = null;
  }

  void _header() {
    _out
      ..addAll(const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]) // GIF89a
      ..addUint16(width)
      ..addUint16(height)
      ..add(0xF7) // global palette, 256 entries
      ..add(0)
      ..add(0)
      ..addAll(palette)
      ..addAll(const [0, 0, 0]) // the transparent index
      // Loop forever (NETSCAPE2.0).
      ..addAll(const [0x21, 0xFF, 11])
      ..addAll("NETSCAPE2.0".codeUnits)
      ..addAll(const [3, 1, 0, 0, 0]);
  }

  /// The finished GIF. Throws when no frame was added.
  Uint8List finish() {
    if (_pending == null && _frames == 0) throw StateError("no frames");
    _flush();
    _out.add(0x3B);
    return _out.takeBytes();
  }

  static const _hashSize = 8192;
  static final _hashCodes = Int32List(_hashSize);
  static final _hashValues = Int32List(_hashSize);

  /// GIF's LZW with 8-bit pixels, in 255-byte sub-blocks.
  static void _lzw(Uint8List pixels, _ByteSink out) {
    const clear = 256, end = 257;
    final keys = _hashCodes, values = _hashValues;
    keys.fillRange(0, _hashSize, -1);

    out.add(8);
    final block = Uint8List(255);
    var blockLength = 0;
    var bits = 0, bitCount = 0;
    var codeSize = 9, next = 258;

    void write(int code) {
      bits |= code << bitCount;
      bitCount += codeSize;
      while (bitCount >= 8) {
        block[blockLength++] = bits & 0xFF;
        bits >>= 8;
        bitCount -= 8;
        if (blockLength == 255) {
          out
            ..add(255)
            ..addAll(block);
          blockLength = 0;
        }
      }
    }

    write(clear);
    var prefix = pixels[0];
    for (var p = 1; p < pixels.length; p++) {
      final c = pixels[p];
      final key = c << 12 | prefix;
      var h = (c << 5 ^ prefix) & (_hashSize - 1);
      var found = -1;
      while (keys[h] >= 0) {
        if (keys[h] == key) {
          found = values[h];
          break;
        }
        h = (h - 1) & (_hashSize - 1);
      }
      if (found >= 0) {
        prefix = found;
        continue;
      }
      write(prefix);
      if (next < 4096) {
        keys[h] = key;
        values[h] = next++;
        // The decoder adds this entry one code later, so it widens its
        // codes once it has used up the current width.
        if (next > 1 << codeSize && codeSize < 12) codeSize++;
      } else {
        write(clear);
        keys.fillRange(0, _hashSize, -1);
        codeSize = 9;
        next = 258;
      }
      prefix = c;
    }
    write(prefix);
    // The decoder adds an entry for this last code before reading the end
    // code, which can widen it by a bit.
    if (next < 4096 && next + 1 > 1 << codeSize && codeSize < 12) codeSize++;
    write(end);
    if (bitCount > 0) block[blockLength++] = bits & 0xFF;
    if (blockLength > 0) {
      out
        ..add(blockLength)
        ..addAll(Uint8List.sublistView(block, 0, blockLength));
    }
    out.add(0);
  }
}

class _ByteSink {
  Uint8List _bytes = Uint8List(1 << 16);
  int _length = 0;

  void _grow(int extra) {
    if (_length + extra <= _bytes.length) return;
    var size = _bytes.length * 2;
    while (size < _length + extra) {
      size *= 2;
    }
    _bytes = Uint8List(size)..setRange(0, _length, _bytes);
  }

  void add(int byte) {
    _grow(1);
    _bytes[_length++] = byte;
  }

  void addUint16(int v) {
    add(v & 0xFF);
    add(v >> 8 & 0xFF);
  }

  void addAll(List<int> bytes) {
    _grow(bytes.length);
    _bytes.setRange(_length, _length + bytes.length, bytes);
    _length += bytes.length;
  }

  Uint8List takeBytes() => Uint8List.sublistView(_bytes, 0, _length);
}
