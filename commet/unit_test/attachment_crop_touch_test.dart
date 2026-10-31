import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:crop_image/crop_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Touch drags in the picture editor's crop tool (Vommet issue 942). The
// cropper sits inside the editor's zoom view, so its drag has to win the
// gesture arena and only starts once the finger has moved past the touch
// slop. crop_image looked for the corner there, outside its touch area.
Future<CropController> pumpEditor(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = CropController();
  addTearDown(controller.dispose);
  final png = img.encodePng(img.Image(width: 400, height: 200));
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AttachmentCropView(png, controller, 2, onDone: (_) {}))));
  // Let CropImage decode the picture.
  await tester
      .runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
  return controller;
}

Rect pictureRect(WidgetTester tester) => tester.getRect(find.descendant(
    of: find.byType(CropImage), matching: find.byType(GestureDetector)));

/// Drags a finger from [from] by [by] in small steps, like a real touch.
Future<void> touchDrag(WidgetTester tester, Offset from, Offset by) async {
  final gesture =
      await tester.startGesture(from, kind: PointerDeviceKind.touch);
  const steps = 20;
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(from + by * (i / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("a touch drag on a corner handle resizes the crop box",
      (tester) async {
    final controller = await pumpEditor(tester);
    final picture = pictureRect(tester);

    await touchDrag(tester, picture.bottomRight - const Offset(5, 5),
        const Offset(-100, -100));

    final crop = controller.crop;
    expect(crop.left, closeTo(0, 0.001));
    expect(crop.top, closeTo(0, 0.001));
    expect(crop.right * picture.width, closeTo(picture.width - 100, 0.5));
    expect(crop.bottom * picture.height, closeTo(picture.height - 100, 0.5));
  });

  testWidgets("a touch drag on the upper left handle resizes the crop box",
      (tester) async {
    final controller = await pumpEditor(tester);
    final picture = pictureRect(tester);

    await touchDrag(
        tester, picture.topLeft + const Offset(5, 5), const Offset(80, 60));

    final crop = controller.crop;
    expect(crop.left * picture.width, closeTo(80, 0.5));
    expect(crop.top * picture.height, closeTo(60, 0.5));
    expect(crop.right, closeTo(1, 0.001));
    expect(crop.bottom, closeTo(1, 0.001));
  });

  testWidgets("a touch drag inside a smaller crop box moves it",
      (tester) async {
    final controller = await pumpEditor(tester);
    controller.crop = const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75);
    await tester.pumpAndSettle();
    final picture = pictureRect(tester);

    await touchDrag(tester, picture.center, const Offset(-60, 40));

    final crop = controller.crop;
    expect(crop.left * picture.width, closeTo(picture.width / 4 - 60, 0.5));
    expect(crop.top * picture.height, closeTo(picture.height / 4 + 40, 0.5));
    expect(crop.width, closeTo(0.5, 0.001));
    expect(crop.height, closeTo(0.5, 0.001));
  });
}
