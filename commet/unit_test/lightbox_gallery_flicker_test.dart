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
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:flutter/material.dart';
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

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  // Operator report 10-11: the newest picture, opened while the room was
  // still loading, flickered through other pictures as each batch of older
  // ones arrived. Every frame must keep showing the opened picture.
  testWidgets("older pictures loading in front don't move the shown one",
      (tester) async {
    final timeline = _Timeline()
      ..events.addAll([_picture(r"$3"), _picture(r"$2")]); // newest first

    await tester.pumpWidget(MaterialApp(
        home: LightboxGallery(timeline: timeline, initialKey: r"$3/0")));
    await tester.pump();

    final shown = find.byKey(const ValueKey(r"$3/0"));
    expect(tester.getTopLeft(shown).dx, 0);
    expect(find.text("2 / 2 · Someone"), findsOneWidget);

    // A batch of older pictures lands at the old end of the timeline, as
    // in the app: between two frames, with the next one already scheduled.
    tester.binding.scheduleFrame();
    timeline.events.addAll([_picture(r"$1"), _picture(r"$0")]);
    timeline.onEventAdded.add(2);

    // The very next frame, not one later, is already on the opened picture.
    await tester.pump();
    expect(tester.getTopLeft(shown).dx, 0);
    expect(find.text("4 / 4 · Someone"), findsOneWidget);

    await tester.pump();
    expect(tester.getTopLeft(shown).dx, 0);
  });
}
