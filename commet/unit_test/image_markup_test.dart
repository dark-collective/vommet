// Vommet: draw on or redact a picture before sending it (Vommet issue 383).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:commet/ui/organisms/attachment_crop/image_markup.dart';
import 'package:crop_image/crop_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _red = [200, 40, 40, 255];
const _green = [40, 200, 40, 255];
const _black = [0, 0, 0, 255];

/// Left half red, right half green, with per-pixel noise in the red channel
/// so a redaction that only tinted the area would still show a pattern.
Uint8List _png(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = x < w ~/ 2 ? _red : _green;
      image.setPixelRgb(x, y, c[0] + (x * 7 + y * 3) % 2, c[1], c[2]);
    }
  }
  return img.encodePng(image);
}

Future<Uint8List> _rgba(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();

List<int> _px(Uint8List rgba, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return rgba.sublist(i, i + 4);
}

/// Allows the red channel noise of [_png].
Matcher _about(List<int> c) => predicate<List<int>>(
    (p) =>
        (p[0] - c[0]).abs() <= 1 &&
        p[1] == c[1] &&
        p[2] == c[2] &&
        p[3] == c[3],
    "about $c");

void main() {
  test("unrotate maps the rotated view back to the picture", () {
    const p = Offset(0.25, 0.1);
    expect(ImageMarkup.unrotate(p, CropRotation.up), p);
    // Rotated right, the picture's top-left corner is at the top right.
    expect(ImageMarkup.unrotate(const Offset(1, 0), CropRotation.right),
        Offset.zero);
    expect(ImageMarkup.unrotate(const Offset(1, 1), CropRotation.down),
        Offset.zero);
    expect(ImageMarkup.unrotate(const Offset(0, 1), CropRotation.left),
        Offset.zero);
  });

  test("undo removes the last edit; an empty stroke list is empty", () {
    final markup = ImageMarkup();
    expect(markup.isEmpty, isTrue);
    markup.add(MarkupStroke(
        ImageMarkup.penColors.first, 0.01, [Offset.zero, const Offset(1, 1)]));
    markup.add(MarkupRedaction(Rect.fromLTRB(0, 0, 0.5, 0.5)));
    markup.undo();
    expect(markup.edits.single, isA<MarkupStroke>());
    markup.addPoint(const Offset(0.5, 0));
    expect((markup.edits.single as MarkupStroke).points, hasLength(3));
    markup.clear();
    expect(markup.isEmpty, isTrue);
    markup.undo();
    markup.dispose();
  });

  testWidgets("a redaction replaces every pixel under it with black",
      (tester) async {
    await tester.runAsync(() async {
      final source = await decodeImageFromList(_png(40, 20));
      final flat = await ImageMarkup.flatten(source, [
        MarkupRedaction(Rect.fromLTRB(0.1, 0.2, 0.43, 0.81)),
      ]);
      expect([flat.width, flat.height], [40, 20]);
      final px = await _rgba(flat);
      final before = await _rgba(source);

      // Snapped outwards to whole pixels: x 4..18, y 4..17.
      for (var y = 4; y < 17; y++) {
        for (var x = 4; x < 18; x++) {
          expect(_px(px, 40, x, y), _black, reason: "($x, $y)");
        }
      }
      expect(_px(px, 40, 3, 10), _about(_red));
      expect(_px(px, 40, 10, 2), _about(_red));
      expect(_px(px, 40, 30, 10), _about(_green));
      // The source picture is left alone.
      expect(_px(before, 40, 10, 10), _about(_red));
      source.dispose();
      flat.dispose();
    });
  });

  testWidgets("a pen stroke is painted into the pixels", (tester) async {
    await tester.runAsync(() async {
      final source = await decodeImageFromList(_png(40, 20));
      const blue = Color(0xFF1E88E5);
      final flat = await ImageMarkup.flatten(source, [
        MarkupStroke(blue, 0.2, [const Offset(0, 0.5), const Offset(1, 0.5)]),
      ]);
      final px = await _rgba(flat);
      // 4 px wide (0.2 of the 20 px side) along y = 10.
      expect(_px(px, 40, 5, 10), [0x1E, 0x88, 0xE5, 255]);
      expect(_px(px, 40, 30, 9), [0x1E, 0x88, 0xE5, 255]);
      expect(_px(px, 40, 5, 2), _about(_red));
      expect(_px(px, 40, 30, 18), _about(_green));
      source.dispose();
      flat.dispose();
    });
  });

  testWidgets("render redacts, then rotates and crops the picture",
      (tester) async {
    await tester.runAsync(() async {
      final source = await decodeImageFromList(_png(40, 20));
      // Black out the red left half, rotate right: the left half ends up on
      // top. Keep the top three quarters of the rotated picture.
      final out = await AttachmentCrop.render(
          source,
          [
            MarkupRedaction(Rect.fromLTRB(0, 0, 0.5, 1)),
          ],
          crop: const Rect.fromLTRB(0, 0, 1, 0.75),
          rotation: CropRotation.right);
      expect([out.width, out.height], [20, 30]);
      final px = await _rgba(out);
      // Row 19 sits on the seam, where the crop's resampling blends in green.
      for (var y = 0; y < 19; y++) {
        for (var x = 0; x < 20; x++) {
          expect(_px(px, 20, x, y), _black, reason: "($x, $y)");
        }
      }
      expect(_px(px, 20, 10, 25), _about(_green));

      // No red survives anywhere in the encoded file either.
      final encoded = await AttachmentCrop.encodeCropped(out, "shot.png");
      final decoded = img.decodePng(encoded.data)!;
      for (final p in decoded) {
        expect(p.r > 150 && p.g < 100, isFalse);
      }
      source.dispose();
      out.dispose();
    });
  });

  testWidgets("render without edits only crops", (tester) async {
    await tester.runAsync(() async {
      final source = await decodeImageFromList(_png(40, 20));
      final out = await AttachmentCrop.render(source, [],
          crop: const Rect.fromLTRB(0, 0, 0.5, 1), rotation: CropRotation.up);
      expect([out.width, out.height], [20, 20]);
      expect(_px(await _rgba(out), 20, 10, 10), _about(_red));
      source.dispose();
      out.dispose();
    });
  });

  /// Odd channel values everywhere, so no pixel of it can survive the
  /// scramble's quantization (whose levels are all even).
  Uint8List oddNoise(int w, int h) {
    final rgba = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      rgba[i * 4] = (i * 37 % 128) * 2 + 1;
      rgba[i * 4 + 1] = (i * 11 % 128) * 2 + 1;
      rgba[i * 4 + 2] = (i * 5 % 128) * 2 + 1;
      rgba[i * 4 + 3] = 255;
    }
    return rgba;
  }

  test("pixelate: opaque, quantized blocks; no source pixel survives", () {
    const w = 64, h = 32;
    final src = oddNoise(w, h);
    final out = ImageMarkup.scramble(
        src, w, 0, 0, w, h, RedactionStyle.pixelate, math.Random(1));
    final b = ImageMarkup.blockSize(w, h);
    expect(b, 8);
    final colors = <int>{};
    for (var i = 0; i < w * h; i++) {
      expect(out[i * 4 + 3], 255);
      for (var c = 0; c < 3; c++) {
        expect(out[i * 4 + c] % 16, 8);
      }
      colors.add(out[i * 4] << 16 | out[i * 4 + 1] << 8 | out[i * 4 + 2]);
    }
    // At most one colour per block of the (offset) grid.
    expect(colors.length, lessThanOrEqualTo((w ~/ b + 1) * (h ~/ b + 1)));
  });

  test("scramble adds fresh noise each time", () {
    const w = 32, h = 32;
    final src = oddNoise(w, h);
    for (final style in [RedactionStyle.pixelate, RedactionStyle.blur]) {
      final a = ImageMarkup.scramble(src, w, 0, 0, w, h, style, math.Random(1));
      final b = ImageMarkup.scramble(src, w, 0, 0, w, h, style, math.Random(2));
      expect(a, isNot(equals(b)), reason: "$style");
    }
  });

  test("blur: opaque and smooth, made from the mosaic only", () {
    const w = 48, h = 24;
    final src = oddNoise(w, h);
    final out = ImageMarkup.scramble(
        src, w, 0, 0, w, h, RedactionStyle.blur, math.Random(3));
    var maxStep = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        expect(out[i + 3], 255);
        if (x > 0) maxStep = math.max(maxStep, (out[i] - out[i - 4]).abs());
      }
    }
    // The source jumps by up to 254 between neighbours; the blur doesn't.
    expect(maxStep, lessThan(40));
  });

  testWidgets("render with a blur redaction scrambles only that area",
      (tester) async {
    await tester.runAsync(() async {
      final source = await decodeImageFromList(_png(40, 20));
      final edits = <MarkupEdit>[
        MarkupRedaction(const Rect.fromLTRB(0, 0, 0.5, 1),
            style: RedactionStyle.blur)
      ];
      await ImageMarkup.ensurePatches(source, edits, random: math.Random(4));
      final patch = (edits.single as MarkupRedaction).patch!;
      expect([patch.width, patch.height], [20, 20]);
      final out = await AttachmentCrop.render(source, edits,
          crop: const Rect.fromLTRB(0, 0, 1, 1), rotation: CropRotation.up);
      final px = await _rgba(out);
      expect(px.sublist(0, 20 * 4),
          isNot(equals((await _rgba(source)).sublist(0, 20 * 4))));
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 20; x++) {
          expect(_px(px, 40, x, y)[3], 255);
        }
        expect(_px(px, 40, 30, y), _about(_green));
      }
      source.dispose();
      out.dispose();
      patch.dispose();
    });
  });

  testWidgets("a pixelate redaction without a patch is black in the output",
      (tester) async {
    await tester.runAsync(() async {
      final source = await decodeImageFromList(_png(40, 20));
      final flat = await ImageMarkup.flatten(source, [
        MarkupRedaction(const Rect.fromLTRB(0, 0, 0.5, 1),
            style: RedactionStyle.pixelate)
      ]);
      expect(_px(await _rgba(flat), 40, 5, 5), _black);
      source.dispose();
      flat.dispose();
    });
  });

  Future<ui.Image?> pumpEditor(WidgetTester tester,
      {required Future<void> Function() edit}) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ui.Image? result;
    final controller = CropController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AttachmentCropView(_png(40, 20), controller, 2,
                onDone: (image) => result = image))));
    // Let CropImage decode the picture.
    await tester
        .runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await edit();
    await tester.tap(find.text("Done"));
    // Pixelate and blur patches are made with real async work (reading and
    // decoding pixels) whose callbacks land in the test's fake zone, so
    // alternate real waits with pumps until Done hands over the result.
    for (var i = 0; i < 50 && result == null; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    controller.dispose();
    return result;
  }

  testWidgets("redact tool: dragging a box blacks it out in the result",
      (tester) async {
    final result = await pumpEditor(tester, edit: () async {
      await tester.tap(find.text("Redact"));
      await tester.pumpAndSettle();
      final box = tester.getRect(find.descendant(
          of: find.byType(AttachmentMarkupCanvas),
          matching: find.byType(GestureDetector)));
      // Drag over the left half of the picture.
      final gesture =
          await tester.startGesture(box.topLeft + const Offset(1, 1));
      await gesture.moveTo(box.center.translate(-box.width / 4, 0));
      await gesture.moveTo(box.bottomCenter - const Offset(1, 1));
      await gesture.up();
      await tester.pump();
      expect(find.byTooltip("Undo"), findsOneWidget);
    });
    expect(result, isNotNull);
    await tester.runAsync(() async {
      final px = await _rgba(result!);
      expect(_px(px, 40, 5, 10), _black);
      expect(_px(px, 40, 18, 18), _black);
      expect(_px(px, 40, 30, 10), _about(_green));
      result.dispose();
    });
  });

  testWidgets("draw tool: undo removes the stroke", (tester) async {
    final result = await pumpEditor(tester, edit: () async {
      await tester.tap(find.text("Draw"));
      await tester.pumpAndSettle();
      final box = tester.getRect(find.descendant(
          of: find.byType(AttachmentMarkupCanvas),
          matching: find.byType(GestureDetector)));
      await tester.dragFrom(
          box.centerLeft + const Offset(5, 0), Offset(box.width - 10, 0));
      await tester.pump();
      final undo = find.byTooltip("Undo");
      expect(
          tester
              .widget<IconButton>(find.ancestor(
                  of: find.byIcon(Icons.undo),
                  matching: find.byType(IconButton)))
              .onPressed,
          isNotNull);
      await tester.tap(undo);
      await tester.pump();
      expect(
          tester
              .widget<IconButton>(find.ancestor(
                  of: find.byIcon(Icons.undo),
                  matching: find.byType(IconButton)))
              .onPressed,
          isNull);
    });
    await tester.runAsync(() async {
      final px = await _rgba(result!);
      expect(_px(px, 40, 5, 10), _about(_red));
      expect(_px(px, 40, 30, 10), _about(_green));
      result.dispose();
    });
  });

  testWidgets(
      "redacting a rotated picture covers what was shown; back to Crop works",
      (tester) async {
    final result = await pumpEditor(tester, edit: () async {
      await tester.tap(find.byTooltip("Rotate right"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Redact"));
      await tester.pumpAndSettle();
      final box = tester.getRect(find.descendant(
          of: find.byType(AttachmentMarkupCanvas),
          matching: find.byType(GestureDetector)));
      // Rotated right, the red left half is the top half on screen.
      expect(box.height, greaterThan(box.width));
      final gesture =
          await tester.startGesture(box.topLeft + const Offset(1, 1));
      await gesture.moveTo(box.center);
      await gesture.moveTo(box.centerRight - const Offset(1, 0));
      await gesture.up();
      await tester.pump();
      // Switching back to Crop re-attaches the crop view to the controller.
      await tester.tap(find.text("Crop"));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CropImage), findsOneWidget);
    });
    await tester.runAsync(() async {
      expect([result!.width, result.height], [20, 40]);
      final px = await _rgba(result);
      expect(_px(px, 20, 2, 2), _black);
      expect(_px(px, 20, 17, 17), _black);
      expect(_px(px, 20, 10, 30), _about(_green));
      result.dispose();
    });
  });

  testWidgets("redact tool: pixelate scrambles the dragged area",
      (tester) async {
    final result = await pumpEditor(tester, edit: () async {
      await tester.tap(find.text("Redact"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Pixelate"));
      await tester.pumpAndSettle();
      final box = tester.getRect(find.descendant(
          of: find.byType(AttachmentMarkupCanvas),
          matching: find.byType(GestureDetector)));
      final gesture =
          await tester.startGesture(box.topLeft + const Offset(1, 1));
      await gesture.moveTo(box.center.translate(-box.width / 4, 0));
      await gesture.moveTo(box.bottomCenter - const Offset(1, 1));
      await gesture.up();
      await tester.pump();
    });
    expect(result, isNotNull);
    await tester.runAsync(() async {
      final px = await _rgba(result!);
      // The crop step resamples, so exact mosaic colours aren't checked here
      // (the scramble tests do that); the area just must have changed.
      var changed = 0;
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 20; x++) {
          final p = _px(px, 40, x, y);
          expect(p[3], 255);
          if (!_about(_red).matches(p, {})) changed++;
        }
      }
      expect(changed, greaterThan(0));
      expect(_px(px, 40, 30, 10), _about(_green));
      result.dispose();
    });
  });
}
