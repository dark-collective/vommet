import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:crop_image/crop_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets("crop box shrinks to the small minimum, not crop_image's 100 px",
      (tester) async {
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

    expect(tester.widget<CropImage>(find.byType(CropImage)).minimumImageSize,
        attachmentMinimumCropSize);
    expect(attachmentMinimumCropSize, lessThan(100));

    // Drag the lower right corner past the upper left one: the box stops at
    // the minimum size. A mouse keeps the drag slop small, so the drag starts
    // on the corner.
    final picture = tester.getRect(find.descendant(
        of: find.byType(CropImage), matching: find.byType(GestureDetector)));
    final gesture = await tester.startGesture(
        picture.bottomRight - const Offset(2, 2),
        kind: PointerDeviceKind.mouse);
    await gesture.moveTo(picture.bottomRight - const Offset(6, 6));
    await gesture.moveTo(picture.center);
    await gesture.moveTo(picture.topLeft);
    await gesture.up();
    await tester.pumpAndSettle();

    final crop = controller.crop;
    expect(crop.left, closeTo(0, 0.001));
    expect(crop.top, closeTo(0, 0.001));
    expect(crop.width * picture.width, closeTo(attachmentMinimumCropSize, 0.5));
    expect(
        crop.height * picture.height, closeTo(attachmentMinimumCropSize, 0.5));
  });
}
