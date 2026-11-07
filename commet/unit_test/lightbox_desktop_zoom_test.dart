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

// Vommet issue 1161: on desktop, zooming into media in the lightbox expands
// past the 100 px frame to fill the window, and surrounding UI fades out.
// Zooming via mouse wheel fades out everything including the zoom pill;
// zooming via the zoom pill's buttons keeps the pill visible.

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

Future<void> _openViewer(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => Lightbox.show(context, image: _image()),
          child: const Text("open"),
        ),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
}

Future<void> _openGallery(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final timeline = _Timeline()
    ..events.addAll([_picture(r"$2"), _picture(r"$1"), _picture(r"$0")]);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => showGeneralDialog(
            context: context,
            pageBuilder: (_, __, ___) =>
                LightboxGallery(timeline: timeline, initialKey: r"$1/0"),
          ),
          child: const Text("open"),
        ),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
}

InteractiveViewer _viewer(WidgetTester tester) =>
    tester.widget<InteractiveViewer>(find.byType(InteractiveViewer).first);

ClipRRect _outerClip(WidgetTester tester) => tester.widget<ClipRRect>(find
    .ancestor(
      of: find.byType(InteractiveViewer).first,
      matching: find.byType(ClipRRect),
    )
    .first);

double _menuOpacity(WidgetTester tester) {
  final button = find.byKey(const ValueKey("lightbox_menu_button"));
  return tester
      .widget<AnimatedOpacity>(find
          .ancestor(of: button, matching: find.byType(AnimatedOpacity))
          .first)
      .opacity;
}

double _pillOpacity(WidgetTester tester) {
  final inButton = find.byKey(const ValueKey("lightbox_zoom_in"));
  return tester
      .widget<AnimatedOpacity>(find
          .ancestor(of: inButton, matching: find.byType(AnimatedOpacity))
          .first)
      .opacity;
}

bool _pillIgnoring(WidgetTester tester) {
  final inButton = find.byKey(const ValueKey("lightbox_zoom_in"));
  return tester
      .widget<IgnorePointer>(find
          .ancestor(of: inButton, matching: find.byType(IgnorePointer))
          .first)
      .ignoring;
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets(
      "desktop media viewer unclips and expands past frame when zoomed via wheel/matrix",
      (tester) async {
    await _openViewer(tester);

    // Initially at original size (<= 1.01):
    expect(_viewer(tester).clipBehavior, Clip.hardEdge);
    expect(_outerClip(tester).clipBehavior, Clip.antiAlias);
    expect(_pillOpacity(tester), 1.0);
    expect(_pillIgnoring(tester), isFalse);
    expect(_menuOpacity(tester), 1.0);

    // Zoom in (scale = 2.0, e.g. from mouse wheel):
    final controller = _viewer(tester).transformationController!;
    controller.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pumpAndSettle();

    // Media unclips past the 100 px frame:
    expect(_viewer(tester).clipBehavior, Clip.none);
    expect(_outerClip(tester).clipBehavior, Clip.none);
    // Surrounding controls fade out:
    expect(_menuOpacity(tester), 0.0);
    expect(_pillOpacity(tester), 0.0);
    expect(_pillIgnoring(tester), isTrue);

    // Reset back to fit:
    controller.value = Matrix4.identity();
    await tester.pumpAndSettle();

    expect(_viewer(tester).clipBehavior, Clip.hardEdge);
    expect(_outerClip(tester).clipBehavior, Clip.antiAlias);
    expect(_menuOpacity(tester), 1.0);
    expect(_pillOpacity(tester), 1.0);
    expect(_pillIgnoring(tester), isFalse);
  });

  testWidgets(
      "zooming via + button keeps the zoom pill visible while fading menu",
      (tester) async {
    await _openViewer(tester);

    final zoomIn = find.byKey(const ValueKey("lightbox_zoom_in"));
    expect(zoomIn, findsOneWidget);

    // Tap + button on the zoom pill:
    await tester.tap(zoomIn);
    await tester.pumpAndSettle();

    // Media is unclipped and zoomed:
    expect(_viewer(tester).clipBehavior, Clip.none);
    expect(_outerClip(tester).clipBehavior, Clip.none);
    expect(_viewer(tester).transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1.01));

    // Menu button fades out, but zoom pill stays visible:
    expect(_menuOpacity(tester), 0.0);
    expect(_pillOpacity(tester), 1.0);
    expect(_pillIgnoring(tester), isFalse);

    // User can continue using the zoom pill:
    await tester.tap(zoomIn);
    await tester.pumpAndSettle();
    expect(_pillOpacity(tester), 1.0);

    // Tap reset on zoom pill:
    final reset = find.byKey(const ValueKey("lightbox_zoom_reset"));
    await tester.tap(reset);
    await tester.pumpAndSettle();

    // Original margins and all UI return:
    expect(_viewer(tester).clipBehavior, Clip.hardEdge);
    expect(_outerClip(tester).clipBehavior, Clip.antiAlias);
    expect(_menuOpacity(tester), 1.0);
    expect(_pillOpacity(tester), 1.0);
  });

  testWidgets(
      "mouse wheel zoom while zoom pill was kept visible fades the pill out",
      (tester) async {
    await _openViewer(tester);

    // Zoom in with + button:
    final zoomIn = find.byKey(const ValueKey("lightbox_zoom_in"));
    await tester.tap(zoomIn);
    await tester.pumpAndSettle();
    expect(_pillOpacity(tester), 1.0);

    // Now interact via pointer scroll event (mouse wheel):
    final center = tester.getCenter(find.byType(InteractiveViewer).first);
    final pointerSignal = PointerScrollEvent(
      position: center,
      scrollDelta: const Offset(0, -50),
    );
    tester.binding.handlePointerEvent(pointerSignal);
    await tester.pumpAndSettle();

    // Zoom pill fades out:
    expect(_pillOpacity(tester), 0.0);
    expect(_pillIgnoring(tester), isTrue);

    // Clicks on faded pill are ignored, but tapping the image resets:
    await tester.tap(find.byType(InteractiveViewer).first);
    await tester.pumpAndSettle();

    expect(_pillOpacity(tester), 1.0);
    expect(_menuOpacity(tester), 1.0);
  });

  testWidgets(
      "gallery on desktop fades counter, strip, arrows and menu when zoomed via + button",
      (tester) async {
    await _openGallery(tester);

    double opacityOf(Finder finder) => tester
        .widget<AnimatedOpacity>(find
            .ancestor(of: finder, matching: find.byType(AnimatedOpacity))
            .first)
        .opacity;

    final counter = find.textContaining("2 / 3");
    final strip = find.byKey(const ValueKey("lightbox-gallery-strip"));
    final backdrop =
        find.byKey(const ValueKey("lightbox-gallery-zoom-backdrop"));
    final zoomIn = find.byKey(const ValueKey("lightbox_zoom_in"));

    expect(opacityOf(counter), 1.0);
    expect(opacityOf(strip), 1.0);
    expect(opacityOf(backdrop), 0.0);
    expect(_pillOpacity(tester), 1.0);

    // Zoom via + button:
    await tester.tap(zoomIn);
    await tester.pumpAndSettle();

    // Gallery surrounding UI fades out, backdrop turns black:
    expect(opacityOf(counter), 0.0);
    expect(opacityOf(strip), 0.0);
    expect(opacityOf(backdrop), 1.0);
    // Zoom pill remains visible:
    expect(_pillOpacity(tester), 1.0);
    expect(_pillIgnoring(tester), isFalse);

    // Reset zoom:
    await tester.tap(find.byKey(const ValueKey("lightbox_zoom_reset")));
    await tester.pumpAndSettle();

    expect(opacityOf(counter), 1.0);
    expect(opacityOf(strip), 1.0);
    expect(opacityOf(backdrop), 0.0);
    expect(_pillOpacity(tester), 1.0);
  });
}
