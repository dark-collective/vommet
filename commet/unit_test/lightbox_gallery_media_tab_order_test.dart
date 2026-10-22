import 'dart:async';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

_Message _picture(String id) => _Message(id, [
      ImageAttachment(MemoryImage(Uint8List.fromList(_png)), _File(),
          name: "$id.png", mimeType: "image/png")
    ]);

Future<void> _open(WidgetTester tester, {required bool newestFirst}) async {
  final timeline = _Timeline()
    ..events.addAll([_picture(r"$3"), _picture(r"$2"), _picture(r"$1")]);
  await tester.pumpWidget(MaterialApp(
      home: LightboxGallery(
          timeline: timeline, initialKey: r"$2/0", newestFirst: newestFirst)));
  await tester.pump();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void _expectShown(WidgetTester tester, String key) =>
    expect(tester.getTopLeft(find.byKey(ValueKey(key))).dx, 0);

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  // In the chat, newer pictures are further down, so going right goes to a
  // newer one.
  testWidgets("from the chat, right goes to the newer picture", (tester) async {
    await _open(tester, newestFirst: false);
    expect(find.text("2 / 3 · Someone"), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectShown(tester, r"$3/0");
    expect(find.text("3 / 3 · Someone"), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    _expectShown(tester, r"$1/0");
    expect(find.text("1 / 3 · Someone"), findsOneWidget);
  });

  // Operator report 10-21: the Media tab lists the newest picture first
  // (top left), but the viewer's arrows went the other way round. Opened
  // from there, right must go to the next (older) thumbnail and the count
  // must match the grid's order.
  testWidgets("from the Media tab, right goes to the older picture",
      (tester) async {
    await _open(tester, newestFirst: true);
    expect(find.text("2 / 3 · Someone"), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectShown(tester, r"$1/0");
    expect(find.text("3 / 3 · Someone"), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    _expectShown(tester, r"$3/0");
    expect(find.text("1 / 3 · Someone"), findsOneWidget);
  });
}
