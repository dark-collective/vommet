// Vommet issue 128: sending pictures smaller.
import 'dart:typed_data';

import 'package:commet/client/attachment.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:commet/utils/picture_shrink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

/// A [w]×[h] picture with grain, so PNG can't squeeze it much (like a
/// photo) and a smaller JPEG saves a lot.
img.Image _picture(int w, int h, {int channels = 3, int alpha = 255}) {
  final image = img.Image(width: w, height: h, numChannels: channels);
  for (final p in image) {
    final grain = ((p.x * 73856093) ^ (p.y * 19349663)) & 0x3f;
    p
      ..r = p.x * 190 ~/ w + grain
      ..g = p.y * 190 ~/ h + grain
      ..b = ((p.x * 2654435761 + p.y * 40503) >> 7) & 0xff;
    if (channels == 4) p.a = alpha;
  }
  return image;
}

Future<void> _usePrefs(Map<String, Object> values) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(values);
  Preference.preferences = await SharedPreferences.getInstance();
}

void main() {
  test("target size fits the longest side and never upscales", () {
    expect(PictureShrink.targetSize(4032, 3024, 2048), (2048, 1536));
    expect(PictureShrink.targetSize(3024, 4032, 2048), (1536, 2048));
    expect(PictureShrink.targetSize(800, 600, 2048), (800, 600));
    expect(PictureShrink.targetSize(2048, 10, 1280), (1280, 6));
    expect(PictureShrink.targetSize(5000, 1, 1280), (1280, 1));
  });

  test("settings keys fall back to the defaults", () {
    expect(SendSmallerMode.fromKey("always"), SendSmallerMode.always);
    expect(SendSmallerMode.fromKey("mobile"), SendSmallerMode.mobileData);
    expect(SendSmallerMode.fromKey("nope"), SendSmallerMode.mobileData);
    expect(SendSmallerSize.fromKey("large").longestEdge, 2560);
    expect(SendSmallerSize.fromKey(null), SendSmallerSize.standard);
  });

  test("GIFs and non-pictures are never shrunk", () {
    expect(PictureShrink.canShrink("image/jpeg"), isTrue);
    expect(PictureShrink.canShrink("image/png"), isTrue);
    expect(PictureShrink.canShrink("image/gif"), isFalse);
    expect(PictureShrink.canShrink("video/mp4"), isFalse);
    expect(PictureShrink.canShrink(null), isFalse);
  });

  test("a big PNG photo becomes a smaller JPEG without hidden info", () {
    final source = _picture(400, 300);
    source.exif.imageIfd["Make"] = "Phone Co";
    final data = img.encodePng(source);
    final small = PictureShrink.shrink(data, longestEdge: 200, name: "a.png");
    expect(small, isNotNull);
    expect(small!.mimeType, "image/jpeg");
    expect(small.name, "a.jpg");
    expect((small.width, small.height), (200, 150));
    expect((small.originalWidth, small.originalHeight), (400, 300));
    expect(small.data.length, lessThan(data.length * 0.9));
    expect(small.percentSmaller, greaterThan(10));
    final back = img.decodeJpg(small.data)!;
    expect(back.exif.isEmpty, isTrue);
  });

  test("see-through PNGs stay PNG; opaque RGBA ones become JPEG", () {
    final clear = img.encodePng(_picture(400, 300, channels: 4, alpha: 100));
    final kept = PictureShrink.shrink(clear, longestEdge: 100, name: "s.png");
    expect(kept?.mimeType, "image/png");
    expect(kept?.name, "s.png");

    final opaque = img.encodePng(_picture(400, 300, channels: 4));
    expect(
        PictureShrink.shrink(opaque, longestEdge: 100)?.mimeType, "image/jpeg");
  });

  test("a sideways phone photo comes out the right way up", () {
    final source = _picture(400, 200);
    source.exif.imageIfd.orientation = 6; // rotate 90° to show
    final data = img.encodeJpg(source, quality: 100);
    final small = PictureShrink.shrink(data, longestEdge: 100);
    expect(small, isNotNull);
    expect((small!.width, small.height), (50, 100));
    expect(img.decodeJpg(small.data)!.exif.imageIfd.hasOrientation, isFalse);
  });

  test("no saving, animated or broken pictures are sent as they are", () {
    final tiny = img.encodeJpg(_picture(40, 30),
        quality: 50, chroma: img.JpegChroma.yuv420);
    expect(PictureShrink.shrink(tiny, longestEdge: 2048), isNull);

    final animated = _picture(64, 64)..addFrame(_picture(64, 64));
    expect(
        PictureShrink.shrink(img.encodePng(animated), longestEdge: 16), isNull);

    expect(PictureShrink.shrink(Uint8List.fromList([1, 2, 3]), longestEdge: 16),
        isNull);
  });

  group("attachment dialog", () {
    Future<void> pump(WidgetTester tester) async {
      final a = PendingFileAttachment(
          name: "view.png",
          data: img.encodePng(_picture(2400, 1200)),
          mimeType: "image/png");
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: AttachmentProcessor(attachment: a)))));
      });
      // The smaller picture is made off the fake clock.
      for (var i = 0;
          i < 600 && find.textContaining("\u2192 2048").evaluate().isEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    testWidgets("shows the saving; off by default on Wi-Fi", (tester) async {
      await _usePrefs({});
      MediaAutoDownload.resetForTest(network: MediaNetwork.wifi);
      await pump(tester);
      expect(find.text("Send smaller"), findsOneWidget);
      expect(find.textContaining("2400×1200 → 2048×1024"), findsOneWidget);
      expect(find.text("Always removed from smaller pictures"), findsNothing);
      expect(find.text("On because you're on mobile data"), findsNothing);
    });

    testWidgets("on by default on mobile data, hidden info locked off",
        (tester) async {
      await _usePrefs({});
      MediaAutoDownload.resetForTest(network: MediaNetwork.mobile);
      await pump(tester);
      expect(find.text("On because you're on mobile data"), findsOneWidget);
      expect(find.text("Always removed from smaller pictures"), findsOneWidget);
    });

    testWidgets("Never keeps it off even on mobile data", (tester) async {
      await _usePrefs({"send_smaller_pictures": "never"});
      MediaAutoDownload.resetForTest(network: MediaNetwork.mobile);
      await pump(tester);
      expect(find.text("Send smaller"), findsOneWidget);
      expect(find.text("Always removed from smaller pictures"), findsNothing);
    });
  });
}
