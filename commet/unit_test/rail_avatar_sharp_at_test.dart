import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/utils/image/lod_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 PNG
final png = base64Decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==");

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // reports the image's own size like the real decoder does
  Future<ui.Codec> sizedDecode(ui.ImmutableBuffer buffer,
      {ui.TargetImageSize Function(int, int)? getTargetSize}) {
    getTargetSize?.call(1, 1);
    return PaintingBinding.instance.instantiateImageCodecWithSize(buffer);
  }

  LODImageCompleter avatar() => LODImageCompleter(
        callback: sizedDecode,
        autoLoadFullres: false,
        loadThumbnail: () async => Uint8List.fromList(png),
        loadFullRes: () async => Uint8List.fromList(png),
      );

  // Vommet: room avatars on the sidebar rail stayed blurry on a phone: the
  // shared avatar only ever showed the room list's small thumbnail.
  group("sharpAt", () {
    test("asked before the thumbnail: full image once it's too small",
        () async {
      final completer = avatar()..sharpAt(2);
      await completer.fetchThumbnail();
      await completer.fullResLoading;
      expect(completer.thumbnailPixels, 1);
      expect(completer.currentlyLoadedImage, LODImageType.fullres);
    });

    test("asked after the thumbnail loaded", () async {
      final completer = avatar();
      await completer.fetchThumbnail();
      expect(completer.currentlyLoadedImage, LODImageType.thumbnail);
      completer.sharpAt(2);
      await completer.fullResLoading;
      expect(completer.currentlyLoadedImage, LODImageType.fullres);
    });

    test("a thumbnail big enough stays", () async {
      final completer = avatar()..sharpAt(1);
      await completer.fetchThumbnail();
      await completer.fullResLoading;
      expect(completer.currentlyLoadedImage, LODImageType.thumbnail);
    });
  });
}
