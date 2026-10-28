// Vommet issue 746: the shared 1:1 chat wallpaper's event parsing, Recent
// list, adjustments and upload preparation.

import 'dart:typed_data';

import 'package:commet/client/matrix/components/chat_wallpaper/matrix_chat_wallpaper_component.dart';
import 'package:commet/ui/organisms/chat_wallpaper/chat_wallpaper_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

typedef C = MatrixChatWallpaperComponent;

void main() {
  test("the state event only points at the wallpaper's event", () {
    expect(C.currentEventId({"event_id": "\$abc:x"}), "\$abc:x");
    expect(C.currentEventId({}), isNull);
    expect(C.currentEventId(null), isNull);
    expect(C.currentEventId({"event_id": "abc"}), isNull);
    expect(C.currentEventId({"event_id": 5}), isNull);
  });

  test("Recent ignores junk", () {
    expect(
        C.recentIds({
          "recent": ["\$a", 3, "b", "\$c"]
        }),
        ["\$a", "\$c"]);
    expect(C.recentIds({"recent": "x"}), isEmpty);
    expect(C.recentIds({}), isEmpty);
  });

  test("a new entry goes first and replaces the same picture's entries", () {
    expect(C.withRecent(["\$a", "\$b", "\$c"], "\$n", replaces: {"\$b"}),
        ["\$n", "\$a", "\$c"]);
    expect(C.withRecent(["\$a", "\$b"], "\$b"), ["\$b", "\$a"]);
    final many = [for (var i = 0; i < 40; i++) "\$$i"];
    expect(C.withRecent(many, "\$n").length, C.maxRecent);
  });

  test("adjustments are clamped and default to 0", () {
    expect(C.adjustment(-3), -1);
    expect(C.adjustment(0.25), 0.25);
    expect(C.adjustment("x"), 0);
    expect(C.adjustment(double.nan), 0);
    expect(C.adjustment(-0.5, min: 0), 0);
  });

  test("darker is black, lighter is white, 0 is no overlay", () {
    expect(ChatWallpaperView.tintFor(0), isNull);
    final dark = ChatWallpaperView.tintFor(-1)!;
    expect(dark.r, Colors.black.r);
    expect(dark.a, closeTo(ChatWallpaperView.maxTint, 0.01));
    final light = ChatWallpaperView.tintFor(0.5)!;
    expect(light.r, Colors.white.r);
    expect(light.a, closeTo(ChatWallpaperView.maxTint / 2, 0.01));
  });

  test("uploads are scaled down, JPEG, without metadata", () {
    final big = img.Image(width: 3000, height: 1000);
    big.exif.imageIfd["Make"] = "TestCam";
    final prepared =
        prepareWallpaperImage(Uint8List.fromList(img.encodeJpg(big)));
    expect(prepared.width, C.maxSide);
    expect(prepared.height, closeTo(853, 1));
    final decoded = img.decodeJpg(prepared.bytes)!;
    expect(decoded.width, C.maxSide);
    expect(decoded.exif.imageIfd["Make"], isNull);
  });

  test("small pictures keep their size", () {
    final small = img.Image(width: 800, height: 600);
    final prepared =
        prepareWallpaperImage(Uint8List.fromList(img.encodePng(small)));
    expect((prepared.width, prepared.height), (800, 600));
  });

  test("not a picture throws", () {
    expect(() => prepareWallpaperImage(Uint8List.fromList([1, 2, 3])),
        throwsUnsupportedError);
  });
}
