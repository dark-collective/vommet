import 'dart:typed_data';

import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 802: Forward in the media viewer's ⋮ menu.

const _png = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];

MemoryImage _image() => MemoryImage(Uint8List.fromList(_png));

Future<void> _open(
    WidgetTester tester, void Function(BuildContext context) open) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => open(context),
          child: const Text("room"),
        ),
      ),
    ),
  ));
  await tester.tap(find.text("room"));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey("lightbox_menu_button")));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets("no Forward without a message to forward", (tester) async {
    await _open(tester, (context) => Lightbox.show(context, image: _image()));
    expect(find.text("Save as…"), findsOneWidget);
    expect(find.text("Forward"), findsNothing);
  });

  testWidgets("Forward closes the viewer, then forwards", (tester) async {
    var forwards = 0;
    await _open(
        tester,
        (context) => Lightbox.show(context,
            image: _image(), onForward: () => forwards++));
    await tester.tap(find.text("Forward"));
    await tester.pumpAndSettle();
    expect(forwards, 1);
    expect(find.byType(Lightbox), findsNothing);
  });
}
