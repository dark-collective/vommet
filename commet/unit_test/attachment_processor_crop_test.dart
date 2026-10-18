// Vommet: the Add File dialog offers "Crop or rotate" for pictures.
import 'dart:typed_data';

import 'package:commet/client/attachment.dart';
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
  testWidgets("pictures get a Crop or rotate row that opens the editor",
      (tester) async {
    await _pump(
        tester,
        PendingFileAttachment(
            name: "house.png", data: _png(40, 30), mimeType: "image/png"));
    expect(find.text("Crop or rotate"), findsOneWidget);

    await tester.tap(find.text("Crop or rotate"));
    // Decoding the picture runs off the fake clock; wait for the editor
    // with real time (slow when the whole suite runs).
    for (var i = 0;
        i < 100 && find.text("Crop picture").evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text("Crop picture"), findsOneWidget);
  });

  testWidgets("GIFs and other files get no crop row", (tester) async {
    await _pump(
        tester,
        PendingFileAttachment(
            name: "a.gif",
            data: img.encodeGif(img.Image(width: 4, height: 4)),
            mimeType: "image/gif"));
    expect(find.text("Crop or rotate"), findsNothing);

    await _pump(
        tester,
        PendingFileAttachment(
            name: "notes.txt",
            data: Uint8List.fromList("hi".codeUnits),
            mimeType: "text/plain"));
    expect(find.text("Crop or rotate"), findsNothing);
  });
}
