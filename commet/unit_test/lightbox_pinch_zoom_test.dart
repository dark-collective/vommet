import 'dart:async';
import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/atoms/lightbox_full_screen.dart';
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

  double zoomOf(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  // Two fingers down a little apart around the middle of the screen, then
  // spread along [direction] the way a thumb and finger do on a phone.
  Future<void> pinchOut(WidgetTester tester, Offset direction,
      {Duration secondFinger = const Duration(milliseconds: 8),
      Duration hold = Duration.zero}) async {
    final center = tester.getCenter(find.byType(InteractiveViewer).first);
    final a = await tester.startGesture(center - direction * 20, pointer: 1);
    await tester.pump(secondFinger);
    final b = await tester.startGesture(center + direction * 20, pointer: 2);
    if (hold > Duration.zero) await tester.pump(hold);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await a.moveBy(-direction * 10);
      await b.moveBy(direction * 10);
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  }

  for (final (name, direction) in [
    ("sideways", const Offset(1, 0)),
    ("diagonal", const Offset(0.7, 0.7)),
    ("up and down", const Offset(0, 1)),
  ]) {
    // Operator report 10-15: on a phone, pinching a picture opened from the
    // timeline didn't zoom it (Telegram does).
    testWidgets("pinching $name zooms the picture in the gallery",
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      final timeline = _Timeline()
        ..events.addAll([_picture(r"$2"), _picture(r"$1"), _picture(r"$0")]);
      await tester.pumpWidget(MaterialApp(
          home: LightboxGallery(timeline: timeline, initialKey: r"$1/0")));
      await tester.pump();

      final shown = find.byKey(const ValueKey(r"$1/0"));
      await pinchOut(tester, direction);

      expect(zoomOf(tester), greaterThan(1.5));
      // ... and stays on the same picture.
      expect(tester.getTopLeft(shown).dx, 0);
      expect(find.textContaining("2 / 3"), findsOneWidget);
    });
  }

  // Operator 10-15: "it's just easy to start moving to the next image
  // instead of zooming". The first finger often slides a little before the
  // second one lands; that head start used to win the race for the page.
  for (final (name, step) in [
    ("left", const Offset(-8, 0)),
    ("right", const Offset(8, 0)),
  ]) {
    testWidgets("a pinch whose first finger already slid $name still zooms",
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      final timeline = _Timeline()
        ..events.addAll([_picture(r"$2"), _picture(r"$1"), _picture(r"$0")]);
      await tester.pumpWidget(MaterialApp(
          home: LightboxGallery(timeline: timeline, initialKey: r"$1/0")));
      await tester.pump();

      final center = tester.getCenter(find.byType(InteractiveViewer).first);
      final a = await tester.startGesture(center, pointer: 1);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await a.moveBy(step);
      }
      final b =
          await tester.startGesture(center + const Offset(60, 60), pointer: 2);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await a.moveBy(step);
        await b.moveBy(const Offset(10, 10));
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      expect(zoomOf(tester), greaterThan(1.2));
      expect(tester.getTopLeft(find.byKey(const ValueKey(r"$1/0"))).dx, 0);
      expect(find.textContaining("2 / 3"), findsOneWidget);
    });
  }

  testWidgets("a zoomed picture pans instead of turning the page",
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final timeline = _Timeline()
      ..events.addAll([_picture(r"$2"), _picture(r"$1"), _picture(r"$0")]);
    await tester.pumpWidget(MaterialApp(
        home: LightboxGallery(timeline: timeline, initialKey: r"$1/0")));
    await tester.pump();

    await pinchOut(tester, const Offset(0, 1));
    expect(zoomOf(tester), greaterThan(1.5));
    await tester.drag(
        find.byType(InteractiveViewer).first, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining("2 / 3"), findsOneWidget);
  });

  // Vommet issue 685: zoomed in, only the picture is left on screen.
  testWidgets("the counter and strip fade out while zoomed in", (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final timeline = _Timeline()
      ..events.addAll([_picture(r"$2"), _picture(r"$1"), _picture(r"$0")]);
    await tester.pumpWidget(MaterialApp(
        home: LightboxGallery(timeline: timeline, initialKey: r"$1/0")));
    await tester.pump();

    double opacityOf(Finder finder) => tester
        .widget<AnimatedOpacity>(find
            .ancestor(of: finder, matching: find.byType(AnimatedOpacity))
            .first)
        .opacity;
    final counter = find.textContaining("2 / 3");
    final strip = find.byKey(const ValueKey("lightbox-gallery-strip"));
    // Vommet issue 694: the room behind the viewer fades out too.
    final backdrop =
        find.byKey(const ValueKey("lightbox-gallery-zoom-backdrop"));
    PageView pageView() => tester.widget<PageView>(find.byType(PageView));
    expect(opacityOf(counter), 1);
    expect(opacityOf(strip), 1);
    expect(opacityOf(backdrop), 0);
    expect(pageView().clipBehavior, Clip.hardEdge);

    await pinchOut(tester, const Offset(0, 1));
    expect(zoomOf(tester), greaterThan(1.5));
    expect(opacityOf(counter), 0);
    expect(opacityOf(strip), 0);
    expect(opacityOf(backdrop), 1);
    // The zoomed picture may spread over the faded strip.
    expect(pageView().clipBehavior, Clip.none);
    // The strip keeps its space, so the picture doesn't jump.
    expect(tester.getSize(strip).height, greaterThan(0));

    tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
        .transformationController!
        .value = Matrix4.identity();
    await tester.pumpAndSettle();
    expect(opacityOf(counter), 1);
    expect(opacityOf(strip), 1);
    expect(opacityOf(backdrop), 0);
  });

  // Vommet issue 755: zoomed in on a phone, the status and navigation bars
  // hide too, and come back at fit or when the viewer closes.
  testWidgets("the system bars hide while zoomed in", (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    tester.view.padding = const FakeViewPadding(top: 110, bottom: 66);
    addTearDown(tester.view.reset);
    final bars = <bool>[];
    LightboxSystemBars.supported = () => true;
    LightboxSystemBars.setHidden = (hidden) async => bars.add(hidden);
    addTearDown(() {
      LightboxSystemBars.supported =
          () => PlatformUtils.isAndroid || PlatformUtils.isIOS;
    });

    final timeline = _Timeline()
      ..events.addAll([_picture(r"$2"), _picture(r"$1"), _picture(r"$0")]);
    await tester.pumpWidget(MaterialApp(
        home: LightboxGallery(timeline: timeline, initialKey: r"$1/0")));
    await tester.pump();
    final strip = find.byKey(const ValueKey("lightbox-gallery-strip"));
    final stripTop = tester.getTopLeft(strip).dy;

    await pinchOut(tester, const Offset(0, 1));
    expect(zoomOf(tester), greaterThan(1.5));
    expect(LightboxSystemBars.hidden, isTrue);
    expect(bars, [true]);

    // The bars are gone; the gallery keeps their padding, so nothing jumps.
    tester.view.padding = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(strip).dy, stripTop);

    tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
        .transformationController!
        .value = Matrix4.identity();
    await tester.pumpAndSettle();
    expect(LightboxSystemBars.hidden, isFalse);
    expect(bars, [true, false]);

    // Closing while zoomed brings them back too.
    tester.view.padding = const FakeViewPadding(top: 110, bottom: 66);
    await tester.pumpAndSettle();
    await pinchOut(tester, const Offset(0, 1));
    expect(bars, [true, false, true]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(LightboxSystemBars.hidden, isFalse);
    expect(bars, [true, false, true, false]);
  });

  testWidgets("a one-finger swipe still turns the page", (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final timeline = _Timeline()
      ..events.addAll([_picture(r"$2"), _picture(r"$1"), _picture(r"$0")]);
    await tester.pumpWidget(MaterialApp(
        home: LightboxGallery(timeline: timeline, initialKey: r"$1/0")));
    await tester.pump();

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.textContaining("3 / 3"), findsOneWidget);
  });

  // The viewer as it opens with the gallery experiment off (the default).
  for (final (name, secondFinger, hold) in [
    ("quick", const Duration(milliseconds: 8), Duration.zero),
    ("second finger late", const Duration(milliseconds: 150), Duration.zero),
    (
      "fingers rest first",
      const Duration(milliseconds: 40),
      const Duration(milliseconds: 300)
    ),
  ]) {
    testWidgets("pinching zooms the single picture viewer ($name)",
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Center(
                  child: TextButton(
                      onPressed: () => Lightbox.show(context,
                          image: MemoryImage(Uint8List.fromList(_png))),
                      child: const Text("open"))))));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();

      for (final direction in [const Offset(1, 0), const Offset(0.7, 0.7)]) {
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value = Matrix4.identity();
        await pinchOut(tester, direction,
            secondFinger: secondFinger, hold: hold);
        expect(zoomOf(tester), greaterThan(1.5), reason: "$direction");
      }
    });
  }
}
