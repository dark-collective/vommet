import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/utils/image/decode_limits.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Vommet: a tall screenshot (the operator's was 800x19600) was decoded at a
// fixed 1440 px height on Linux, i.e. 59 px wide, and stayed unreadable in
// the image viewer too.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tall = Uint8List.fromList(img.encodePng(
      img.Image(width: 800, height: 19600)..clear(img.ColorRgb8(200, 30, 30)),
      level: 1));

  Future<ui.Codec> decode(ui.ImmutableBuffer buffer,
          {ui.TargetImageSize Function(int, int)? getTargetSize}) =>
      PaintingBinding.instance
          .instantiateImageCodecWithSize(buffer, getTargetSize: getTargetSize);

  Future<ui.Image> load(LODImageCompleter completer) async {
    ui.Image? shown;
    completer.addListener(ImageStreamListener((info, _) => shown = info.image));
    await completer.fetchFullRes();
    return shown!;
  }

  test("a height cap squashes a tall image (the old Linux behaviour)",
      () async {
    final image = await load(LODImageCompleter(
        callback: decode,
        autoLoadFullres: false,
        fullResHeight: 1440,
        loadFullRes: () async => tall));
    expect(image.height, 1440);
    expect(image.width, lessThan(60));
  });

  test("timeline limits keep the aspect ratio and a readable width", () async {
    final image = await load(LODImageCompleter(
        callback: decode,
        autoLoadFullres: false,
        fullResLimits: ImageDecodeLimits.linuxTimeline,
        loadFullRes: () async => tall));
    expect(image.width, greaterThan(300));
    expect(image.width * image.height, lessThanOrEqualTo(1920 * 1440));
  });

  test("the viewer decodes the same image much larger", () async {
    final timeline = LODImageProvider(
        id: "decode-size-test",
        autoLoadFullRes: false,
        loadFullRes: () async => tall)
      ..fullResLimits = ImageDecodeLimits.linuxTimeline;
    final viewer = timeline.forViewer();
    expect(viewer, isNot(same(timeline)));
    expect((viewer as LODImageProvider).fullResLimits,
        ImageDecodeLimits.linuxViewer);

    final image = await load(LODImageCompleter(
        callback: decode,
        autoLoadFullres: false,
        fullResLimits: viewer.fullResLimits,
        loadFullRes: viewer.loadFullRes));
    expect(image.width, greaterThanOrEqualTo(660));
    expect(image.height, lessThanOrEqualTo(16384));
  });

  test("images without limits open in the viewer unchanged", () {
    final provider =
        LODImageProvider(id: "decode-size-test-2", fullResHeight: 128);
    expect(provider.forViewer(), same(provider));
  });
}
