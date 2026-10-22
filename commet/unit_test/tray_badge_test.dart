import 'dart:ui' as ui;

import 'package:commet/utils/tray/linux_tray.dart';
import 'package:commet/utils/tray/tray_badge.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// A plain green [size]×[size] square standing in for the app icon.
Future<ui.Image> _icon(int size) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = const Color(0xFF00FF00));
  return recorder.endRecording().toImage(size, size);
}

/// [x], [y]'s (alpha, red, green, blue).
List<int> _pixel(LinuxTrayPixmap pixmap, int x, int y) {
  final i = (y * pixmap.width + x) * 4;
  return pixmap.argb.sublist(i, i + 4);
}

void main() {
  test("the label counts to 9, then says 9+", () {
    expect(trayBadgeLabel(1), "1");
    expect(trayBadgeLabel(9), "9");
    expect(trayBadgeLabel(10), "9+");
    expect(trayBadgeLabel(250), "9+");
  });

  testWidgets("draws a red badge in the lower right with a clear ring",
      (tester) async {
    await tester.runAsync(() async {
      final icon = await _icon(128);
      final pixmap = await drawTrayBadge(icon, 64, "3");
      icon.dispose();

      expect(pixmap.width, 64);
      expect(pixmap.height, 64);
      expect(pixmap.argb, hasLength(64 * 64 * 4));

      // The icon, scaled down, away from the badge.
      expect(_pixel(pixmap, 5, 5), [255, 0, 255, 0]);

      // The badge is 32 px tall at 64 px; its top edge, above the text.
      final badge = _pixel(pixmap, 48, 34);
      expect(badge[0], 255);
      expect(badge[1], greaterThan(200));
      expect(badge[2], lessThan(100));

      // The ring cut out of the icon just above the badge.
      expect(_pixel(pixmap, 48, 30)[0], 0);
    });
  });
}
