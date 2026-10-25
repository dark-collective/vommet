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

/// Opens the gallery on a phone-sized screen, on the middle of five
/// pictures.
Future<void> _open(WidgetTester tester, {bool newestFirst = false}) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final timeline = _Timeline()
    ..events.addAll([for (var i = 5; i >= 1; i--) _picture("\$$i")]);
  await tester.pumpWidget(MaterialApp(
      home: LightboxGallery(
          timeline: timeline, initialKey: r"$3/0", newestFirst: newestFirst)));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

final _stripHandle =
    find.byKey(const ValueKey("lightbox-gallery-strip-handle"));
final _gridHandle = find.byKey(const ValueKey("lightbox-gallery-grid-handle"));
final _grid = find.byKey(const ValueKey("lightbox-gallery-grid"));

Finder _cell(String key) => find.byKey(ValueKey("lightbox-gallery-grid-$key"));

Future<void> _openGrid(WidgetTester tester) async {
  await tester.drag(_stripHandle, const Offset(0, -120));
  await _settle(tester);
  expect(_grid, findsOneWidget);
}

bool _glows(WidgetTester tester, String key) {
  final box = tester.widget<AnimatedContainer>(find.descendant(
      of: _cell(key), matching: find.byType(AnimatedContainer)));
  return (box.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false;
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  // Vommet issue 684: the grid is a phone thing.
  setUp(() => preferences.layoutOverride.set("mobile"));
  tearDown(() => preferences.layoutOverride.set(null));

  testWidgets("a swipe up on the strip's handle opens the grid",
      (tester) async {
    await _open(tester);
    expect(_stripHandle, findsOneWidget);
    expect(_grid, findsNothing);
    await _openGrid(tester);
    for (var i = 1; i <= 5; i++) {
      expect(_cell("\$$i/0"), findsOneWidget);
    }
    expect(_glows(tester, r"$3/0"), isTrue);
    expect(_glows(tester, r"$2/0"), isFalse);
  });

  testWidgets("a swipe up on the strip itself opens the grid too",
      (tester) async {
    await _open(tester);
    await tester.drag(find.byKey(const ValueKey("lightbox-gallery-strip")),
        const Offset(0, -120));
    await _settle(tester);
    expect(_grid, findsOneWidget);
  });

  testWidgets("the grid never covers the picture", (tester) async {
    await _open(tester);
    await _openGrid(tester);
    expect(tester.getRect(find.byType(PageView)).bottom,
        lessThanOrEqualTo(tester.getRect(_grid).top));
  });

  for (final newestFirst in [false, true]) {
    testWidgets(
        "older pictures sit above newer ones"
        "${newestFirst ? ", from the Media tab too" : ""}", (tester) async {
      await _open(tester, newestFirst: newestFirst);
      await _openGrid(tester);
      expect(tester.getCenter(_cell(r"$1/0")).dy,
          lessThan(tester.getCenter(_cell(r"$5/0")).dy));
    });
  }

  testWidgets("tapping a thumbnail shows it and keeps the grid open",
      (tester) async {
    await _open(tester);
    await _openGrid(tester);
    await tester.tap(_cell(r"$5/0"));
    await _settle(tester);
    expect(find.text("5 / 5 · Someone"), findsOneWidget);
    expect(_grid, findsOneWidget);
    expect(_glows(tester, r"$5/0"), isTrue);
    expect(_glows(tester, r"$3/0"), isFalse);
  });

  testWidgets("dragging the grid's handle down closes it", (tester) async {
    await _open(tester);
    await _openGrid(tester);
    await tester.drag(_gridHandle, const Offset(0, 120));
    await _settle(tester);
    expect(_grid, findsNothing);
    expect(_stripHandle, findsOneWidget);
  });

  testWidgets("on desktop the strip has no handle", (tester) async {
    await preferences.layoutOverride.set("desktop");
    await _open(tester);
    expect(_stripHandle, findsNothing);
    expect(
        find.byKey(const ValueKey("lightbox-gallery-strip")), findsOneWidget);
  });
}
