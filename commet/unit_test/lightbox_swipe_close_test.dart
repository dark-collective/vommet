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
import 'package:commet/ui/atoms/lightbox_full_screen.dart';
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
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

class _VideoController extends VideoPlayerController {
  @override
  Future<Size?> getSize() async => const Size(640, 360);
}

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
    WidgetTester tester, void Function(BuildContext context) open,
    {bool video = false, Duration? openingTime}) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: LightboxGalleryScope(
      timeline: _Timeline()
        ..events.addAll(video
            ? [
                _Message(r"$video", [
                  VideoAttachment(_File(),
                      mimeType: "video/mp4", thumbnail: _image())
                ]),
                _picture(r"$poster")
              ]
            : [_picture(r"$2"), _picture(r"$1"), _picture(r"$0")]),
      child: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => open(context),
            child: const Text("room"),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text("room"));
  await tester.pump();
  if (openingTime == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(openingTime);
  }
  expect(find.byType(Lightbox), findsWidgets);
}

void _single(BuildContext context) => Lightbox.show(context, image: _image());

void _gallery(BuildContext context) {
  final item = LightboxGalleryScope.maybeOf(context)!.source.items[1];
  LightboxGallery.showIfInTimeline(context,
      image: (item.attachment as ImageAttachment).image);
}

void _video(BuildContext context) => Lightbox.show(context,
    video: _File(),
    thumbnail: _image(),
    aspectRatio: 16 / 9,
    videoController: _VideoController());

void _galleryVideo(BuildContext context) {
  final item = LightboxGalleryScope.maybeOf(context)!
      .source
      .items
      .singleWhere((item) => item.attachment is VideoAttachment);
  LightboxGallery.showIfInTimeline(context,
      video: (item.attachment as VideoAttachment).file,
      videoController: _VideoController());
}

Finder get _picture0 {
  final galleryPage = find.byKey(const ValueKey(r"$1/0"));
  return galleryPage.evaluate().isEmpty
      ? find.byType(InteractiveViewer).first
      : find.descendant(
          of: galleryPage, matching: find.byType(InteractiveViewer));
}

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
        final finger = await tester.startGesture(tester.getCenter(_picture0));
        await finger.moveBy(Offset(0, 24 * offset.dy.sign));
        await tester.pump();
        await finger.moveBy(offset);
        await tester.pump();
        final dragged = tester.getCenter(_picture0).dy;
        await finger.up();
        await tester.pump();
        // The first closing frame stays where the finger released it.
        expect(tester.getCenter(_picture0).dy, closeTo(dragged, 0.01));
        for (var i = 0; i < 3; i++) {
          final before = tester.getCenter(_picture0).dy;
          await tester.pump(const Duration(milliseconds: 60));
          final after = tester.getCenter(_picture0).dy;
          expect((after - before) * offset.dy.sign, greaterThan(0));
        }
        await tester.pumpAndSettle();
        expect(find.byType(Lightbox), findsNothing);
      });
      testWidgets("a short fling $direction closes the $name in that direction",
          (tester) async {
        await _open(tester, viewer);
        await tester.fling(_picture0, offset * 0.3, 1500);
        await tester.pump();
        final released = tester.getCenter(_picture0).dy;
        await tester.pump(const Duration(milliseconds: 120));
        expect((tester.getCenter(_picture0).dy - released) * offset.dy.sign,
            greaterThan(0));
        await tester.pumpAndSettle();
        expect(find.byType(Lightbox), findsNothing);
      });
    }

    testWidgets("an upward swipe during opening keeps the $name continuous",
        (tester) async {
      await _open(tester, viewer,
          openingTime: const Duration(milliseconds: 100));
      final finger = await tester.startGesture(tester.getCenter(_picture0));
      await finger.moveBy(const Offset(0, -24));
      await tester.pump();
      await finger.moveBy(const Offset(0, -140));
      await tester.pump();
      final released = tester.getCenter(_picture0).dy;
      await finger.up();
      await tester.pump();
      expect(tester.getCenter(_picture0).dy, closeTo(released, 0.01));
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.getCenter(_picture0).dy, lessThan(released));
      await tester.pumpAndSettle();
      expect(find.byType(Lightbox), findsNothing);
    });

    for (final direction in [-1.0, 1.0]) {
      testWidgets("a short slow swipe ($direction) springs the $name back",
          (tester) async {
        await _open(tester, viewer);
        final start = tester.getCenter(_picture0);
        final finger = await tester.startGesture(start);
        for (var i = 0; i < 10; i++) {
          await finger.moveBy(Offset(0, 6 * direction));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await finger.up();
        await tester.pumpAndSettle();
        expect(find.byType(Lightbox), findsWidgets);
        expect(tester.getCenter(_picture0), start);
      });
    }

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

  for (final (name, viewer) in [
    ("viewer", _video),
    ("gallery", _galleryVideo)
  ]) {
    for (final direction in [-1.0, 1.0]) {
      testWidgets(
          "a swipe ($direction) leaves mobile video full screen in $name",
          (tester) async {
        final supported = LightboxSystemBars.supported;
        final setHidden = LightboxSystemBars.setHidden;
        final bars = <bool>[];
        LightboxSystemBars.supported = () => true;
        LightboxSystemBars.setHidden = (hidden) async => bars.add(hidden);
        addTearDown(() {
          LightboxFullScreen.exit();
          LightboxSystemBars.supported = supported;
          LightboxSystemBars.setHidden = setHidden;
        });
        await _open(tester, viewer, video: true);
        final media = name == "gallery"
            ? find.descendant(
                of: find.byKey(const ValueKey(r"$video/0")),
                matching: find.byType(InteractiveViewer))
            : _picture0;
        LightboxFullScreen.enter();
        await tester.pumpAndSettle();
        expect(LightboxFullScreen.active.value, isTrue);

        await tester.drag(media, Offset(0, 250 * direction));
        await tester.pumpAndSettle();
        expect(LightboxFullScreen.active.value, isFalse);
        expect(find.byType(Lightbox), findsWidgets);
        expect(bars, [true, false]);
        if (name == "gallery") {
          expect(find.byKey(const ValueKey("lightbox-gallery-strip")),
              findsOneWidget);
        }

        // A second swipe in the normal viewer closes it as before.
        await tester.drag(media, Offset(0, 250 * direction));
        await tester.pumpAndSettle();
        expect(find.byType(Lightbox), findsNothing);
      });
    }
  }

  testWidgets("a short slow swipe keeps mobile video in full screen",
      (tester) async {
    final supported = LightboxSystemBars.supported;
    final setHidden = LightboxSystemBars.setHidden;
    LightboxSystemBars.supported = () => true;
    LightboxSystemBars.setHidden = (_) async {};
    addTearDown(() {
      LightboxFullScreen.exit();
      LightboxSystemBars.supported = supported;
      LightboxSystemBars.setHidden = setHidden;
    });
    await _open(tester, _video, video: true);
    LightboxFullScreen.enter();
    await tester.pumpAndSettle();
    final start = tester.getCenter(_picture0);
    final finger = await tester.startGesture(start);
    for (var i = 0; i < 10; i++) {
      await finger.moveBy(const Offset(0, -6));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await finger.up();
    await tester.pumpAndSettle();
    expect(LightboxFullScreen.active.value, isTrue);
    expect(tester.getCenter(_picture0), start);
  });

  testWidgets("a full-screen desktop video ignores touch swipes",
      (tester) async {
    final supported = LightboxSystemBars.supported;
    final isWindowFullScreen = LightboxFullScreen.isWindowFullScreen;
    final setWindowFullScreen = LightboxFullScreen.setWindowFullScreen;
    LightboxSystemBars.supported = () => false;
    LightboxFullScreen.isWindowFullScreen = () async => false;
    LightboxFullScreen.setWindowFullScreen = (_) async {};
    addTearDown(() {
      LightboxFullScreen.exit();
      LightboxSystemBars.supported = supported;
      LightboxFullScreen.isWindowFullScreen = isWindowFullScreen;
      LightboxFullScreen.setWindowFullScreen = setWindowFullScreen;
    });
    await _open(tester, _video, video: true);
    LightboxFullScreen.enter();
    await tester.pumpAndSettle();
    await tester.drag(_picture0, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(LightboxFullScreen.active.value, isTrue);
    expect(find.byType(Lightbox), findsOneWidget);
    LightboxFullScreen.exit();
    await tester.pumpAndSettle();
  });
}
