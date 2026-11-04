// Vommet: crop a picture attachment before sending.
import 'dart:typed_data';

import 'package:commet/client/attachment.dart';
import 'package:commet/ui/molecules/attachment_icon.dart';
import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _png(int w, int h) => img.encodePng(
    img.Image(width: w, height: h)..clear(img.ColorRgb8(200, 40, 40)));

void main() {
  test("GIFs and non-pictures can't be cropped", () {
    expect(
        AttachmentCrop.canCrop(PendingFileAttachment(
            name: "a.png", data: _png(4, 4), mimeType: "image/png")),
        isTrue);
    expect(
        AttachmentCrop.canCrop(PendingFileAttachment(
            name: "a.gif", data: Uint8List(4), mimeType: "image/gif")),
        isFalse);
    expect(
        AttachmentCrop.canCrop(PendingFileAttachment(
            name: "a.txt", data: Uint8List(4), mimeType: "text/plain")),
        isFalse);
  });

  testWidgets("cropped JPEG stays JPEG, other formats become PNG",
      (tester) async {
    await tester.runAsync(() async {
      final image = await decodeImageFromList(_png(30, 20));

      final jpg = await AttachmentCrop.encodeCropped(image, "Photo.JPG");
      expect(jpg.mimeType, "image/jpeg");
      expect(jpg.name, "Photo.JPG");
      final decodedJpg = img.decodeJpg(jpg.data)!;
      expect([decodedJpg.width, decodedJpg.height], [30, 20]);

      final webp = await AttachmentCrop.encodeCropped(image, "sticker.webp");
      expect(webp.mimeType, "image/png");
      expect(webp.name, "sticker.png");
      expect(img.decodePng(webp.data)!.width, 30);

      final unnamed = await AttachmentCrop.encodeCropped(image, null);
      expect(unnamed.name, "picture.png");
      image.dispose();
    });
  });

  Future<void> pump(WidgetTester tester, PendingFileAttachment a,
      void Function() onRemove) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 40,
                    height: 40,
                    child: AttachmentIcon(a, removeAttachment: onRemove))))));
  }

  testWidgets("a picture shows remove and crop buttons; X removes it",
      (tester) async {
    var removed = 0;
    await pump(
        tester,
        PendingFileAttachment(
            name: "a.png", data: _png(4, 4), mimeType: "image/png"),
        () => removed++);
    expect(find.byIcon(Icons.crop), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    expect(removed, 1);
  });

  testWidgets("a file has no crop button", (tester) async {
    await pump(
        tester,
        PendingFileAttachment(
            name: "a.txt", data: Uint8List(4), mimeType: "text/plain"),
        () {});
    expect(find.byIcon(Icons.crop), findsNothing);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
