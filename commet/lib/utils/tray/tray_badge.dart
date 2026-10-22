import 'dart:math';
import 'dart:ui' as ui;

import 'package:commet/utils/tray/linux_tray.dart';
import 'package:flutter/painting.dart';

/// The text of the tray icon's unread badge (Vommet issue 536): the count up
/// to 9, then "9+" so it still reads at 22 px.
String trayBadgeLabel(int count) => count > 9 ? "9+" : "$count";

/// [icon] fitted into a [size]×[size] square with a red unread badge showing
/// [label] in the lower right corner. A thin ring around the badge is cut
/// out of the icon, so the badge stays clear on light and dark panels alike.
Future<LinuxTrayPixmap> drawTrayBadge(
    ui.Image icon, int size, String label) async {
  final s = size.toDouble();
  final square = Rect.fromLTWH(0, 0, s, s);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, square);

  final scale = s / max(icon.width, icon.height);
  final w = icon.width * scale, h = icon.height * scale;

  final badgeHeight = s * 0.5;
  final badgeWidth = label.length > 1 ? s * 0.68 : badgeHeight;
  final badge = RRect.fromRectAndRadius(
      Rect.fromLTWH(s - badgeWidth, s - badgeHeight, badgeWidth, badgeHeight),
      Radius.circular(badgeHeight / 2));

  canvas.saveLayer(square, Paint());
  canvas.drawImageRect(
      icon,
      Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
      Rect.fromLTWH((s - w) / 2, (s - h) / 2, w, h),
      Paint()..filterQuality = FilterQuality.medium);
  canvas.drawRRect(
      badge.inflate(s * 0.06), Paint()..blendMode = BlendMode.clear);
  canvas.drawRRect(badge, Paint()..color = const Color(0xFFE5372B));
  canvas.restore();

  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
    textAlign: TextAlign.center,
    fontFamily: "NunitoSans",
    fontWeight: FontWeight.w800,
    fontSize: badgeHeight * 0.78,
    height: 1,
  ))
    ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
    ..addText(label);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: badgeWidth));
  canvas.drawParagraph(
      paragraph,
      Offset(s - badgeWidth,
          s - badgeHeight + (badgeHeight - paragraph.height) / 2));

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  try {
    final bytes =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (bytes == null) throw StateError("Could not read the tray badge image");
    return LinuxTrayPixmap.fromRgba(size, size, bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
