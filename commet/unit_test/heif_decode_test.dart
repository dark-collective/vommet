import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/utils/image/heif_decode.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 813: HEIC pictures on Linux/Windows are decoded by the
// system and handed to the engine as a BMP.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("HEIF files are recognized by their ftyp brand", () {
    expect(looksLikeHeif(heifProbeSample), isTrue);
    final png = Uint8List.fromList(
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]);
    expect(looksLikeHeif(png), isFalse);
    expect(looksLikeHeif(Uint8List(4)), isFalse);
  });

  test("the RGBA BMP decodes in the engine, rows and channels intact",
      () async {
    // 2x2 pixels, rows padded to 12 bytes.
    final pixels = Uint8List.fromList([
      255, 0, 0, 255, 0, 255, 0, 255, 9, 9, 9, 9, //
      0, 0, 255, 255, 255, 255, 255, 128, 9, 9, 9, 9,
    ]);
    final bmp = bmpFromRgba(pixels, 2, 2, 12);

    final codec = await ui.instantiateImageCodec(bmp);
    final image = (await codec.getNextFrame()).image;
    expect((image.width, image.height), (2, 2));
    final data =
        (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
    expect(data.buffer.asUint8List(), [
      255, 0, 0, 255, 0, 255, 0, 255, //
      0, 0, 255, 255, 255, 255, 255, 128,
    ]);
  });

  test("where the system decodes HEIC, the probe picture is 16x8", () async {
    final bmp = decodeHeifToBmp(heifProbeSample);
    if (bmp == null) return; // no system decoder here: nothing to check
    final codec = await ui.instantiateImageCodec(bmp);
    final image = (await codec.getNextFrame()).image;
    expect((image.width, image.height), (16, 8));
  });
}
