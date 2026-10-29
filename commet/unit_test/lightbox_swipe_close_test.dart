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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 701: an up or down swipe on the picture closes the viewer.

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

void _single(BuildContext context) => Lightbox.show(context, image: _image());

void _gallery(BuildContext context) => showGeneralDialog(
    context: context,
    pageBuilder: (_, __, ___) => LightboxGallery(
        timeline: _Timeline()
          ..events.addAll([_picture(r"$2"), _picture(r"$1"), _picture(r"$0")]),
        initialKey: r"$1/0"));

Finder get _picture0 => find.byType(InteractiveViewer).first;

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  for (final (name, viewer) in [("viewer", _single), ("gallery", _gallery)]) {
    for (final (direction, offset) in [
      ("down", const Offset(0, 250)),
      ("up", const Offset(0, -250)),
    ]) {
      testWidgets("swiping $direction closes the $name", (tester) async {
        await _open(tester, viewer);
        await tester.drag(_picture0, offset);
        await tester.pumpAndSettle();
        expect(find.byType(Lightbox), findsNothing);
      });
    }

    testWidgets("a short slow swipe springs the $name back", (tester) async {
      await _open(tester, viewer);
      final start = tester.getCenter(_picture0);
      final finger = await tester.startGesture(start);
      for (var i = 0; i < 10; i++) {
        await finger.moveBy(const Offset(0, 6));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await finger.up();
      await tester.pumpAndSettle();
      expect(find.byType(Lightbox), findsWidgets);
      expect(tester.getCenter(_picture0), start);
    });

    testWidgets("a mouse drag doesn't close the $name", (tester) async {
      await _open(tester, viewer);
      await tester.drag(_picture0, const Offset(0, 250),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byType(Lightbox), findsWidgets);
    });
  }

  testWidgets("zoomed in, a vertical drag pans instead of closing",
      (tester) async {
    await _open(tester, _gallery);
    final controller =
        tester.widget<InteractiveViewer>(_picture0).transformationController!;
    controller.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pumpAndSettle();

    await tester.drag(_picture0, const Offset(0, 250));
    await tester.pumpAndSettle();
    expect(find.byType(Lightbox), findsWidgets);
  });

  testWidgets("a sideways swipe in the gallery still turns the page",
      (tester) async {
    await _open(tester, _gallery);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.textContaining("3 / 3"), findsOneWidget);
  });
}
