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
import 'package:flutter/gestures.dart';
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

/// Vommet issue 700: a room with [older] more events further back, loaded
/// three at a time.
class _HistoryTimeline extends _Timeline {
  _HistoryTimeline(this.older);

  final List<TimelineEvent> older;
  int loads = 0;

  @override
  bool get canLoadHistory => older.isNotEmpty;

  @override
  Future<void> loadMoreHistory() async {
    loads++;
    final next = older.take(3).toList();
    older.removeRange(0, next.length);
    events.addAll(next);
  }
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

/// Thirty pictures, on the fifteenth: the strip is longer than the screen.
Future<void> _openMany(WidgetTester tester, {required bool newestFirst}) async {
  final timeline = _Timeline()
    ..events.addAll([for (var i = 30; i >= 1; i--) _picture("\$$i")]);
  await tester.pumpWidget(MaterialApp(
      home: LightboxGallery(
          timeline: timeline, initialKey: r"$15/0", newestFirst: newestFirst)));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void _expectShown(WidgetTester tester, String key) =>
    expect(tester.getTopLeft(find.byKey(ValueKey(key))).dx, 0);

Finder _thumb(String key) =>
    find.byKey(ValueKey("lightbox-gallery-strip-$key"));

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  // Vommet issue 629: a strip of thumbnails along the bottom of the viewer.
  testWidgets("the strip shows every item, older to the left", (tester) async {
    await _open(tester, newestFirst: false);
    expect(_thumb(r"$1/0"), findsOneWidget);
    expect(_thumb(r"$2/0"), findsOneWidget);
    expect(_thumb(r"$3/0"), findsOneWidget);
    expect(tester.getCenter(_thumb(r"$1/0")).dx,
        lessThan(tester.getCenter(_thumb(r"$3/0")).dx));
  });

  testWidgets("from the Media tab, the strip runs newest first",
      (tester) async {
    await _open(tester, newestFirst: true);
    expect(tester.getCenter(_thumb(r"$3/0")).dx,
        lessThan(tester.getCenter(_thumb(r"$1/0")).dx));
  });

  testWidgets("tapping a thumbnail shows that item", (tester) async {
    await _open(tester, newestFirst: false);
    await tester.tap(_thumb(r"$1/0"));
    await _settle(tester);
    _expectShown(tester, r"$1/0");
    expect(find.text("1 / 3 · Someone"), findsOneWidget);
  });

  // Vommet issue 742: the wheel and a drag only scroll the strip; a click
  // on a thumbnail is what shows another item.
  for (final newestFirst in [false, true]) {
    testWidgets(
        "the wheel over the strip only scrolls it"
        "${newestFirst ? " (newest first)" : ""}", (tester) async {
      await _openMany(tester, newestFirst: newestFirst);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester
          .sendEventToBinding(mouse.hover(tester.getCenter(_thumb(r"$15/0"))));
      final before = tester.getCenter(_thumb(r"$15/0")).dx;

      // Down moves the thumbnails to the left, whichever way the strip runs.
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
      await _settle(tester);
      _expectShown(tester, r"$15/0");
      expect(tester.getCenter(_thumb(r"$15/0")).dx, before - 100);

      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -300)));
      await _settle(tester);
      _expectShown(tester, r"$15/0");
      expect(tester.getCenter(_thumb(r"$15/0")).dx, before + 200);

      // The hover showed the arrows; let their hide timer run out.
      await tester.pump(const Duration(seconds: 3));
    });
  }

  // Vommet issue 660: on desktop the mouse drags the strip like a finger.
  testWidgets("a mouse drag on the strip only scrolls it", (tester) async {
    await _openMany(tester, newestFirst: false);
    final before = tester.getCenter(_thumb(r"$15/0")).dx;

    // Three thumbnails to the left, held still before letting go so the
    // strip doesn't fling on.
    final drag = await tester.startGesture(tester.getCenter(_thumb(r"$15/0")),
        kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await drag.up();
    await _settle(tester);
    _expectShown(tester, r"$15/0");
    expect(tester.getCenter(_thumb(r"$15/0")).dx, lessThan(before - 150));

    // A click on a thumbnail shows it (once the strip has stopped: a
    // scrolling list ignores clicks).
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(_thumb(r"$17/0"), kind: PointerDeviceKind.mouse);
    await _settle(tester);
    _expectShown(tester, r"$17/0");

    await tester.pump(const Duration(seconds: 3));
  });

  // Vommet issue 700: the strip loads older pictures until it is full.
  testWidgets("the strip fills itself from older history", (tester) async {
    final timeline = _HistoryTimeline(
        [for (var i = 57; i >= 1; i--) _picture("\$$i")])
      ..events.addAll([_picture(r"$60"), _picture(r"$59"), _picture(r"$58")]);
    await tester.pumpWidget(MaterialApp(
        home: LightboxGallery(timeline: timeline, initialKey: r"$60/0")));
    for (var i = 0; i < 30; i++) {
      await tester.pump();
    }

    final strip = tester
        .widget<ListView>(find.byKey(const ValueKey("lightbox-gallery-strip")))
        .controller!
        .position;
    expect(strip.maxScrollExtent, greaterThan(0));
    expect(strip.pixels, greaterThanOrEqualTo(3 * 64));
    // Only as much as the strip needs.
    expect(timeline.older, isNotEmpty);
    _expectShown(tester, r"$60/0");
  });

  testWidgets("a room without older pictures stops loading after a few batches",
      (tester) async {
    final timeline = _HistoryTimeline(
        [for (var i = 0; i < 100; i++) _Message("\$text$i", null)])
      ..events.addAll([_picture(r"$2"), _picture(r"$1")]);
    await tester.pumpWidget(MaterialApp(
        home: LightboxGallery(timeline: timeline, initialKey: r"$2/0")));
    for (var i = 0; i < 30; i++) {
      await tester.pump();
    }
    expect(timeline.loads, 5);
  });
}
