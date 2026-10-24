// Vommet: the Add File dialog offers "Edit picture" for pictures.
import 'dart:typed_data';

import 'package:commet/client/attachment.dart';
import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:commet/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _png(int w, int h) => img.encodePng(
    img.Image(width: w, height: h)..clear(img.ColorRgb8(200, 40, 40)));

Future<void> _pump(WidgetTester tester, PendingFileAttachment a) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AttachmentProcessor(attachment: a)))));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

void main() {
  testWidgets("pictures get an Edit picture row that opens the editor",
      (tester) async {
    await _pump(
        tester,
        PendingFileAttachment(
            name: "house.png", data: _png(40, 30), mimeType: "image/png"));
    expect(find.text("Edit picture"), findsOneWidget);

    await tester.tap(find.text("Edit picture"));
    // Decoding the picture runs off the fake clock; wait for the editor
    // with real time (slow when the whole suite runs). Its title matches
    // the row's label, so look for the editor itself.
    for (var i = 0;
        i < 100 && find.byType(AttachmentCropView).evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(AttachmentCropView), findsOneWidget);
    // The dialog's title, plus the row still under the dialog.
    expect(find.text("Edit picture"), findsWidgets);
  });

  testWidgets("GIFs and other files get no crop row", (tester) async {
    await _pump(
        tester,
        PendingFileAttachment(
            name: "a.gif",
            data: img.encodeGif(img.Image(width: 4, height: 4)),
            mimeType: "image/gif"));
    expect(find.text("Edit picture"), findsNothing);

    await _pump(
        tester,
        PendingFileAttachment(
            name: "notes.txt",
            data: Uint8List.fromList("hi".codeUnits),
            mimeType: "text/plain"));
    expect(find.text("Edit picture"), findsNothing);
  });
}
