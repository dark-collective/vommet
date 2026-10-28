import 'dart:async';
import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 771: Jump to message in the viewer opened from the Media tab.

class _Message extends Fake implements TimelineEventMessage {
  _Message(this.eventId, this.attachments);

  @override
  final String eventId;

  @override
  final List<Attachment>? attachments;

  @override
  String get senderId => "@someone:example.org";
}

class _File extends Fake implements FileProvider {}

class _Member extends Fake implements Member {
  @override
  String get displayName => "Someone";
}

class _Room extends Fake implements Room {
  @override
  Member getMemberOrFallback(String id) => _Member();
}

class _Timeline extends Fake implements Timeline {
  @override
  List<TimelineEvent> events = [];

  @override
  StreamController<int> onEventAdded = StreamController.broadcast(sync: true);
  @override
  StreamController<int> onChange = StreamController.broadcast(sync: false);
  @override
  StreamController<int> onRemove = StreamController.broadcast(sync: true);

  @override
  Room room = _Room();

  @override
  bool get canLoadHistory => false;
}

// A 1x1 PNG; each picture gets its own copy so they don't compare equal.
const _png = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];

MemoryImage _image() => MemoryImage(Uint8List.fromList(_png));

_Message _picture(String id) => _Message(id, [
      ImageAttachment(_image(), _File(), name: "$id.png", mimeType: "image/png")
    ]);

/// Opens a viewer over a page saying "room", the way the app does.
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
  expect(find.byType(Lightbox), findsWidgets);
}

Finder get _menuButton => find.byKey(const ValueKey("lightbox_menu_button"));

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(_menuButton);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets("the viewer has no Jump to message without a message",
      (tester) async {
    await _open(tester, (context) => Lightbox.show(context, image: _image()));
    await _openMenu(tester);
    expect(find.text("Save as…"), findsOneWidget);
    expect(find.text("Jump to message"), findsNothing);
  });

  testWidgets("Jump to message closes the viewer, then jumps", (tester) async {
    var jumps = 0;
    await _open(
        tester,
        (context) => Lightbox.show(context,
            image: _image(), onJumpToMessage: () => jumps++));
    await _openMenu(tester);
    await tester.tap(find.text("Jump to message"));
    await tester.pumpAndSettle();
    expect(jumps, 1);
    expect(find.byType(Lightbox), findsNothing);
  });

  testWidgets("the gallery jumps to the picture on screen", (tester) async {
    final jumped = <String>[];
    await _open(
        tester,
        (context) => showGeneralDialog(
            context: context,
            pageBuilder: (_, __, ___) => LightboxGallery(
                timeline: _Timeline()
                  ..events.addAll(
                      [_picture(r"$2"), _picture(r"$1"), _picture(r"$0")]),
                initialKey: r"$1/0",
                onJumpToEvent: jumped.add)));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await _openMenu(tester);
    await tester.tap(find.text("Jump to message"));
    await tester.pumpAndSettle();
    expect(jumped, [r"$2"]);
    expect(find.byType(LightboxGallery), findsNothing);
  });

  testWidgets("the gallery has no Jump to message without a handler",
      (tester) async {
    await _open(
        tester,
        (context) => showGeneralDialog(
            context: context,
            pageBuilder: (_, __, ___) => LightboxGallery(
                timeline: _Timeline()..events.add(_picture(r"$0")),
                initialKey: r"$0/0")));
    await _openMenu(tester);
    expect(find.text("Jump to message"), findsNothing);
  });
}
