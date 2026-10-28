// Vommet: ImageSeedColor's scoring matches what fromImageProvider derives:
// the dominant colour of the image, from RGBA bytes read as ABGR words.
import 'dart:isolate';
import 'dart:typed_data';

import 'package:commet/utils/image/image_seed_color.dart';
import 'package:flutter_test/flutter_test.dart';

/// [n] pixels of one opaque colour, laid out like `toByteData()` (RGBA).
Uint32List _pixels(int r, int g, int b, int n) {
  final bytes = Uint8List(n * 4);
  for (var i = 0; i < n; i++) {
    bytes.setAll(i * 4, [r, g, b, 0xff]);
  }
  return bytes.buffer.asUint32List();
}

void main() {
  test("a mostly blue image seeds blue, not red", () async {
    final pixels = Uint32List.fromList(
        [..._pixels(20, 60, 220, 900), ..._pixels(220, 30, 30, 100)]);
    final argb = await ImageSeedColor.seedFromAbgrPixels(pixels);
    expect(argb, isNotNull);
    final r = (argb! >> 16) & 0xff, g = (argb >> 8) & 0xff, b = argb & 0xff;
    expect(b, greaterThan(r), reason: "blue dominates");
    expect(b, greaterThan(g));
  });

  test("runs in a background isolate", () async {
    final pixels = _pixels(30, 160, 60, 400);
    final argb =
        await Isolate.run(() => ImageSeedColor.seedFromAbgrPixels(pixels));
    expect(argb, isNotNull);
    final g = (argb! >> 8) & 0xff, r = (argb >> 16) & 0xff;
    expect(g, greaterThan(r), reason: "green dominates");
  });
}
