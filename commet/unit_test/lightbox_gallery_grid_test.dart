import 'dart:async';
import 'dart:ui' show Tristate;

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
import 'package:commet/ui/atoms/lightbox_full_screen.dart';
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
Future<void> _open(WidgetTester tester,
    {bool newestFirst = false,
    int count = 5,
    int initial = 3,
    Size? size,
    Size? viewerSize,
    double textScale = 1,
    EdgeInsets padding = EdgeInsets.zero,
    bool routed = false}) async {
  tester.view.physicalSize = size ?? const Size(1080, 2280);
  tester.view.devicePixelRatio = size == null ? 2.75 : 1;
  addTearDown(tester.view.reset);
  final timeline = _Timeline()
    ..events.addAll([for (var i = count; i >= 1; i--) _picture("\$$i")]);
  Widget gallery(BuildContext context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale), padding: padding),
      child: Center(
          child: SizedBox(
              width: viewerSize?.width,
              height: viewerSize?.height,
              child: LightboxGallery(
                  timeline: timeline,
                  initialKey: "\$$initial/0",
                  newestFirst: newestFirst))));
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => routed
              ? Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: gallery)),
                      child: const Text("Open")))
              : gallery(context))));
  if (routed) {
    await tester.tap(find.text("Open"));
    await tester.pumpAndSettle();
  }

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
  await tester.fling(_stripHandle, const Offset(0, -120), 1000);
  await _settle(tester);
  expect(_grid, findsOneWidget);
}

final _reveal = find.byKey(const ValueKey("lightbox-gallery-grid-reveal"));

/// A slow drag by [steps] from [finder], held down at the end.
Future<TestGesture> _hold(
    WidgetTester tester, Finder finder, List<double> steps) async {
  var time = Duration.zero;
  final gesture = await tester.startGesture(tester.getCenter(finder));
  for (final dy in steps) {
    time += const Duration(milliseconds: 500);
    await gesture.moveBy(Offset(0, dy), timeStamp: time);
    await tester.pump();
  }
  return gesture;
}

double _cellWidth(WidgetTester tester, String key) =>
    tester.getSize(_cell(key)).width;

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

  // Keep the existing phone gesture coverage; desktop/tablet cases override below.
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
    await tester.fling(find.byKey(const ValueKey("lightbox-gallery-strip")),
        const Offset(0, -120), 1000);
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
    await tester.fling(_gridHandle, const Offset(0, 120), 1000);
    await _settle(tester);
    expect(_grid, findsNothing);
    expect(_stripHandle, findsOneWidget);
  });

  // Vommet issue 753.
  testWidgets("the grid grows with the finger while swiping up",
      (tester) async {
    await _open(tester);
    final gesture = await _hold(tester, _stripHandle, [-30, -40]);
    expect(_reveal, findsOneWidget);
    final first = tester.getSize(_reveal).height;
    await gesture.moveBy(const Offset(0, -60),
        timeStamp: const Duration(milliseconds: 1500));
    await tester.pump();
    final second = tester.getSize(_reveal).height;
    expect(second, greaterThan(first));
    expect(second - first, closeTo(60, 1));
    // Still held: nothing settles on its own.
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(_reveal).height, second);
    await gesture.moveBy(const Offset(0, -400),
        timeStamp: const Duration(seconds: 4));
    await gesture.up(timeStamp: const Duration(seconds: 5));
    await _settle(tester);
    expect(_grid, findsOneWidget);
    expect(tester.getRect(find.byType(PageView)).bottom,
        lessThanOrEqualTo(tester.getRect(_grid).top));
  });

  testWidgets("a short slow swipe up goes back to the strip", (tester) async {
    await _open(tester);
    final gesture = await _hold(tester, _stripHandle, [-30, -30]);
    expect(_reveal, findsOneWidget);
    await gesture.up(timeStamp: const Duration(seconds: 2));
    await _settle(tester);
    expect(_reveal, findsNothing);
    expect(_stripHandle, findsOneWidget);
  });

  testWidgets("the grid shrinks with the finger while dragged down",
      (tester) async {
    await _open(tester);
    await _openGrid(tester);
    final open = tester.getSize(_reveal).height;
    final gesture = await _hold(tester, _gridHandle, [30, 50]);
    final held = tester.getSize(_reveal).height;
    expect(held, lessThan(open));
    expect(_grid, findsOneWidget);
    // Too short: it goes back up when let go.
    await gesture.up(timeStamp: const Duration(seconds: 2));
    await _settle(tester);
    expect(tester.getSize(_reveal).height, open);
  });

  // Vommet issue 754.
  testWidgets("a pinch on the grid resizes its thumbnails, and it sticks",
      (tester) async {
    addTearDown(() => preferences.mediaGridThumbnailSize.set(110));
    await preferences.mediaGridThumbnailSize.set(110);
    await _open(tester);
    await _openGrid(tester);
    final before = _cellWidth(tester, r"$3/0");

    final center = tester
        .getCenter(find.byKey(const ValueKey("lightbox-gallery-grid-view")));
    final a = await tester.startGesture(center - const Offset(20, 0));
    final b = await tester.startGesture(center + const Offset(20, 0));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await a.moveBy(const Offset(-10, 0));
      await b.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await _settle(tester);

    expect(preferences.mediaGridThumbnailSize.value, greaterThan(110));
    final after = _cellWidth(tester, r"$3/0");
    expect(after, greaterThan(before));

    // Closed and opened again, the grid keeps the size.
    await tester.tap(_gridHandle);
    await _settle(tester);
    expect(_grid, findsNothing);
    await _openGrid(tester);
    expect(_cellWidth(tester, r"$3/0"), after);
  });

  for (final size in [
    const Size(834, 1194),
    const Size(1194, 834),
    const Size(1280, 800)
  ]) {
    testWidgets("desktop layout opens and collapses the grid at $size",
        (tester) async {
      await preferences.layoutOverride.set("desktop");
      await _open(tester, size: size);
      expect(_stripHandle, findsOneWidget);
      await _openGrid(tester);
      expect(
          tester.getSize(_reveal).height,
          lessThanOrEqualTo(
              size.height * (size.width > size.height ? .45 : .60)));
      expect(tester.getRect(find.byType(PageView)).bottom,
          lessThanOrEqualTo(tester.getRect(_grid).top));
      await tester.tap(_cell(r"$5/0"));
      await _settle(tester);
      expect(find.text("5 / 5 · Someone"), findsOneWidget);
      await tester.tap(_gridHandle);
      await _settle(tester);
      expect(_grid, findsNothing);
      expect(find.text("5 / 5 · Someone"), findsOneWidget);
    });
  }

  testWidgets("expansion button exposes its state and works from the keyboard",
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await preferences.layoutOverride.set("desktop");
      await _open(tester, size: const Size(834, 1194));
      final show = find.widgetWithText(TextButton, "Show media grid");
      final node = tester.getSemantics(show).getSemanticsData();
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isExpanded, Tristate.isFalse);
      Focus.of(tester.element(find.text("Show media grid"))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(_grid, findsOneWidget);
      expect(
          tester
              .getSemantics(find.widgetWithText(TextButton, "Hide media grid"))
              .getSemanticsData()
              .flagsCollection
              .isExpanded,
          Tristate.isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets("Escape collapses the desktop grid before closing the viewer",
      (tester) async {
    await preferences.layoutOverride.set("desktop");
    await _open(tester, size: const Size(1194, 834), routed: true);
    await _openGrid(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(_grid, findsNothing);
    expect(find.byType(LightboxGallery), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(LightboxGallery), findsNothing);
  });

  testWidgets(
      "Back leaves full screen, then collapses grid, then closes viewer",
      (tester) async {
    await preferences.layoutOverride.set("desktop");
    final oldSupported = LightboxSystemBars.supported;
    LightboxSystemBars.supported = () => true;
    addTearDown(() {
      LightboxFullScreen.exit();
      LightboxSystemBars.supported = oldSupported;
    });
    await _open(tester, size: const Size(834, 1194), routed: true);
    await _openGrid(tester);
    LightboxFullScreen.enter();
    await _settle(tester);
    await Navigator.of(tester.element(find.byType(LightboxGallery))).maybePop();
    await _settle(tester);
    expect(LightboxFullScreen.active.value, isFalse);
    expect(_grid, findsOneWidget);
    await Navigator.of(tester.element(find.byType(LightboxGallery))).maybePop();
    await _settle(tester);
    expect(_grid, findsNothing);
    expect(find.byType(LightboxGallery), findsOneWidget);
    await Navigator.of(tester.element(find.byType(LightboxGallery))).maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(LightboxGallery), findsNothing);
  });

  testWidgets("grid cells scroll instead of collapsing the dock",
      (tester) async {
    await preferences.layoutOverride.set("desktop");
    await _open(tester, size: const Size(1194, 834));
    await _openGrid(tester);
    final before = tester.getSize(_reveal).height;
    await tester.drag(find.byKey(const ValueKey("lightbox-gallery-grid-view")),
        const Offset(0, 80));
    await _settle(tester);
    expect(tester.getSize(_reveal).height, before);
  });

  testWidgets(
      "local viewer constraints and safe insets bound a large-text dock",
      (tester) async {
    await preferences.layoutOverride.set("desktop");
    await _open(tester,
        size: const Size(1200, 1000),
        viewerSize: const Size(600, 320),
        textScale: 2,
        padding: const EdgeInsets.fromLTRB(30, 24, 40, 20));
    await tester.tap(_stripHandle);
    await _settle(tester);
    expect(tester.getSize(_reveal).height, lessThanOrEqualTo(320 * .45));
    final rect = tester.getRect(find.byType(LightboxGallery));
    for (var i = 1; i <= 5; i++) {
      final cell = tester.getRect(_cell("\$$i/0"));
      expect(cell.left, greaterThanOrEqualTo(rect.left + 30));
      expect(cell.right, lessThanOrEqualTo(rect.right - 40));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets("rotation keeps the grid open and selected item visible",
      (tester) async {
    await preferences.layoutOverride.set("desktop");
    await _open(tester, size: const Size(1194, 834), count: 120, initial: 90);
    await _openGrid(tester);
    tester.view.physicalSize = const Size(834, 1194);
    await _settle(tester);
    expect(_grid, findsOneWidget);
    expect(_glows(tester, r"$90/0"), isTrue);
    expect(tester.getSize(_reveal).height, lessThanOrEqualTo(1194 * .60));
    expect(
        tester.getRect(_cell(r"$90/0")).overlaps(tester
            .getRect(find.byKey(const ValueKey("lightbox-gallery-grid-view")))),
        isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets("thumbnail zoom does not jump back to an offscreen selected item",
      (tester) async {
    addTearDown(() => preferences.mediaGridThumbnailSize.set(110));
    await preferences.mediaGridThumbnailSize.set(110);
    await preferences.layoutOverride.set("desktop");
    await _open(tester, size: const Size(1194, 834), count: 120);
    await _openGrid(tester);
    final view = tester.widget<GridView>(
        find.byKey(const ValueKey("lightbox-gallery-grid-view")));
    final scroll = view.controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await _settle(tester);
    expect(scroll.position.pixels, greaterThan(500));
    await preferences.mediaGridThumbnailSize.set(160);
    await _settle(tester);
    expect(scroll.position.pixels, greaterThan(500));
  });
  testWidgets("short desktop gallery retains a usable preview above the grid",
      (tester) async {
    await preferences.layoutOverride.set("desktop");
    await _open(tester,
        size: const Size(600, 320),
        padding: const EdgeInsets.only(top: 24, bottom: 20));
    await tester.tap(_stripHandle);
    await _settle(tester);
    final previews =
        tester.widgetList<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(previews, isNotEmpty);
    for (final preview in find.byType(InteractiveViewer).evaluate()) {
      expect(
          tester
              .getSize(find
                  .byElementPredicate((element) => identical(element, preview)))
              .height,
          greaterThanOrEqualTo(100));
    }
    expect(tester.takeException(), isNull);
  });
}
