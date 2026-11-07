// Vommet issue 703: closing the Edit picture dialog with Done must not use
// the CropController after it was disposed while the dialog slides out.
import 'dart:typed_data';

import 'package:commet/client/attachment.dart';
import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List picturePng() {
  final image = img.Image(width: 320, height: 200);
  img.fill(image, color: img.ColorRgb8(90, 90, 120));
  return img.encodePng(image);
}

void main() {
  testWidgets('Done closes the editor without using a disposed CropController',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final att = PendingFileAttachment(
        name: "shot.png", data: picturePng(), mimeType: "image/png");
    Future<bool>? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () =>
                        result = AttachmentCrop.cropAttachment(context, att),
                    child: const Text("open"))))));

    await tester.tap(find.text("open"));
    for (var i = 0; i < 20; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text("Edit picture"), findsOneWidget);

    final before = att.data;
    await tester.tap(find.text("Done"));
    for (var i = 0; i < 100 && identical(att.data, before); i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    // Run through the 300 ms exit slide.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("Edit picture"), findsNothing);
    expect(await result, isTrue);
    expect(identical(att.data, before), isFalse,
        reason: "Done replaced the picture");
    final decoded = img.decodePng(att.data!)!;
    expect([decoded.width, decoded.height], [320, 200]);
    expect(att.mimeType, "image/png");
  });
}
