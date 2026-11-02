import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/atoms/emoji_widget.dart';
import 'package:commet/ui/layout/reflow_scroll_controller.dart';
import 'package:commet/ui/molecules/emoji_picker.dart';
import 'package:commet/ui/organisms/room_members_list/grid_columns_zoom.dart';
import 'package:commet/ui/organisms/room_members_list/media_grid_zoom.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Vommet issue 897: the sticker picker resizes one sticker per row at a
// time, sliding between layouts, in the same frame as the gesture.

class _Sticker implements Emoticon {
  _Sticker(this.key);

  @override
  final String key;
  @override
  ImageProvider? get image => tiamat.transparentImage.image;
  @override
  String get slug => key;
  @override
  String? get shortcode => key;
  @override
  EmoticonUsage get usage => EmoticonUsage.sticker;
  @override
  bool get isSticker => true;
  @override
  bool get isEmoji => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pack implements EmoticonPack {
  _Pack(this.displayName, int count)
      : stickers = [for (var i = 0; i < count; i++) _Sticker("$displayName$i")];

  @override
  final String displayName;
  @override
  final List<Emoticon> stickers;
  @override
  List<Emoticon> get emotes => stickers;
  @override
  List<Emoticon> get emoji => const [];
  @override
  ImageProvider? get image => null;
  @override
  IconData? get icon => Icons.star;
  @override
  String get identifier => displayName;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GridZoom _zoom(DoublePreference preference) => GridZoom(
    sizes: const [64, 280], preference: () => preference, fixedCount: true);

void main() {
  late DoublePreference preference;
  late GridZoom zoom;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    preference = DoublePreference("test_sticker_size", defaultValue: 125);
    zoom = _zoom(preference);
  });

  group("stickers per row", () {
    test("the old default size keeps its count at the usual widths", () {
      // floor(width / 125), as before.
      expect(zoom.columns(412), 3);
      expect(zoom.columns(452), 3);
      expect(zoom.columns(500), 4);
    });

    test("every count comes up, one step at a time", () {
      for (final width in [412.0, 450.0, 452.0]) {
        final seen = <int>[];
        var columns = zoom.minColumns(width);
        while (true) {
          seen.add(columns);
          final next = zoom.stepColumns(columns, -1, width);
          if (next == columns) break;
          columns = next;
        }
        expect(
            seen,
            [
              for (var c = zoom.minColumns(width);
                  c <= zoom.maxColumns(width);
                  c++)
                c
            ],
            reason: "$width");
      }
      // The reporter's skipped 5 and 6 at 450 px.
      expect(zoom.stepColumns(4, -1, 450), 5);
      expect(zoom.stepColumns(5, -1, 450), 6);
      expect(zoom.stepColumns(6, -1, 450), 7);
      expect(zoom.stepColumns(7, 1, 450), 6);
    });

    test("the fewest and the most per row", () {
      // 412 / 280 ≈ 1.5 -> 1 per row; 412 / 64 = 6.4 -> 6.
      expect(zoom.minColumns(412), 1);
      expect(zoom.maxColumns(412), 6);
      expect(zoom.minColumns(900), 3);
      expect(zoom.maxColumns(900), 14);
      expect(zoom.stepColumns(6, -1, 412), 6);
      expect(zoom.stepColumns(1, 1, 412), 1);
    });

    test("the size remembered for a count gives that count back", () {
      for (final width in [300.0, 412.0, 450.0, 452.0, 915.0]) {
        for (var n = zoom.minColumns(width); n <= zoom.maxColumns(width); n++) {
          preference.set(zoom.sizeFor(width, n));
          expect(zoom.columns(width), n, reason: "$width, $n");
          // A slightly narrower picker keeps it, while it fits.
          if (n <= zoom.maxColumns(width - 4)) {
            expect(zoom.columns(width - 4), n, reason: "${width - 4}, $n");
          }
        }
      }
    });

    test("a pinch settles on the next count a third of the way there", () {
      expect(GridZoom.settleColumns(4, 4), 4);
      expect(GridZoom.settleColumns(4, 4.2), 4);
      expect(GridZoom.settleColumns(4, 4.35), 5);
      expect(GridZoom.settleColumns(4, 5.2), 5);
      expect(GridZoom.settleColumns(4, 5.9), 6);
      expect(GridZoom.settleColumns(4, 3.8), 4);
      expect(GridZoom.settleColumns(4, 3.6), 3);
      expect(GridZoom.settleColumns(4, 2.8), 3);
      expect(GridZoom.settleColumns(4, 2.1), 2);
      // From between two counts (a pinch over a step still easing in).
      expect(GridZoom.settleColumns(4.4, 4.4), 4);
    });

    test("set notifies at once", () {
      var heard = 0;
      zoom.changes.addListener(() => heard++);
      zoom.set(100);
      expect(heard, 1);
      expect(zoom.size, 100);
      zoom.set(100);
      expect(heard, 1);
    });
  });

  group("phone held sideways", () {
    test("upright and on desktop the remembered size is the size shown", () {
      expect(GridZoom.landscapeScale(const Size(412, 915)), 1);
      expect(GridZoom.landscapeScale(const Size(1600, 900), mobile: false), 1);
    });

    test("more per row, each bigger, than upright", () {
      final scale = GridZoom.landscapeScale(const Size(915, 412));
      expect(scale, closeTo(1.49, 0.01));
      // 4 per row upright.
      preference.set(zoom.sizeFor(412, 4));
      expect(zoom.columns(412), 4);
      final sideways = zoom.columns(915, scale: scale);
      expect(sideways, 6);
      expect(915 / sideways, greaterThan(412 / 4));
      // Picking a count sideways keeps it there, and upright again keeps a
      // matching count.
      preference.set(zoom.sizeFor(915, 7, scale: scale));
      expect(zoom.columns(915, scale: scale), 7);
      // About 4.7 upright.
      expect(zoom.columns(412), 4);
    });
  });

  group("layout between two counts", () {
    test("a whole count lays out as a regular grid", () {
      final layout = ColumnsGridLayout(4, 400);
      final g = layout.getGeometryForChildIndex(5);
      expect(g.crossAxisOffset, 100);
      expect(g.scrollOffset, 100);
      expect(g.crossAxisExtent, 100);
      expect(layout.computeMaxScrollOffset(9), 300);
      expect(layout.computeMaxScrollOffset(0), 0);
    });

    test("in between, items are width / columns wide, partway between places",
        () {
      final layout = ColumnsGridLayout(4.5, 450);
      // Item 4: start of row 2 at 4 per row, end of row 1 at 5 per row.
      final g = layout.getGeometryForChildIndex(4);
      expect(g.crossAxisExtent, closeTo(100, 1e-9));
      expect(g.mainAxisExtent, closeTo(100, 1e-9));
      final t = ColumnsGridLayout.progress(4.5);
      expect(g.crossAxisOffset, closeTo(360 * t, 1e-9));
      expect(g.scrollOffset, closeTo(112.5 * (1 - t), 1e-9));
      // Smooth: the ends meet the whole-number layouts.
      expect(ColumnsGridLayout.progress(4), 0);
      expect(ColumnsGridLayout.progress(4.9999), closeTo(1, 1e-3));
      expect(
          ColumnsGridLayout(4.9999, 450)
              .getGeometryForChildIndex(4)
              .crossAxisOffset,
          closeTo(360, 0.1));
    });

    test("every item that can show is laid out", () {
      for (final columns in [1.3, 2.5, 4.2, 4.5, 4.8, 6.7]) {
        final layout = ColumnsGridLayout(columns, 450);
        for (final offset in [0.0, 37.0, 200.0, 555.0]) {
          final first = layout.getMinChildIndexForScrollOffset(offset);
          final last = layout.getMaxChildIndexForScrollOffset(offset + 300);
          for (var i = 0; i < 200; i++) {
            final g = layout.getGeometryForChildIndex(i);
            final shows = g.trailingScrollOffset > offset &&
                g.scrollOffset < offset + 300;
            if (shows) {
              expect(i, inInclusiveRange(first, last),
                  reason: "$columns at $offset: item $i");
            }
          }
        }
        // The grid ends at its last item.
        expect(
            layout.computeMaxScrollOffset(50),
            closeTo(layout.getGeometryForChildIndex(49).trailingScrollOffset,
                1e-9));
      }
    });

    test("the item at a point", () {
      final layout = ColumnsGridLayout(4, 400);
      expect(layout.indexAt(const Offset(150, 250), 40), 9);
      // Past the last item: the nearest.
      expect(layout.indexAt(const Offset(350, 250), 10), 9);
    });
  });

  testWidgets("a reflow scroll controller puts the view back in the same frame",
      (tester) async {
    final controller = ReflowScrollController();
    var height = 100.0;
    late StateSetter setState;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, set) {
        setState = set;
        return ListView.builder(
          controller: controller,
          itemExtent: height,
          itemCount: 100,
          itemBuilder: (context, i) =>
              SizedBox(height: height, child: Text("item $i")),
        );
      }),
    ));
    controller.jumpTo(1000);
    await tester.pump();
    expect(tester.getTopLeft(find.text("item 10")).dy, 0);

    // Halve the rows; keep item 10 at the top.
    setState(() => height = 50);
    controller.anchor((extent) {
      expect(extent, 5000);
      return 500;
    });
    await tester.pump();
    expect(controller.offset, 500);
    expect(tester.getTopLeft(find.text("item 10")).dy, 0);

    // Forgotten after that frame.
    controller.jumpTo(800);
    await tester.pump();
    expect(controller.offset, 800);
  });

  group("in the sticker picker", () {
    Future<void> pumpPicker(WidgetTester tester, {double width = 450}) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 400,
              child: EmojiPicker(
                [_Pack("a", 30), _Pack("b", 60)],
                onlyStickers: true,
                previewOnHold: true,
                packListAxis: Axis.horizontal,
                zoom: zoom,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    Rect sticker(WidgetTester tester, String key) => tester.getRect(find
        .ancestor(
            of: find.byWidgetPredicate(
                (w) => w is EmojiWidget && w.emoji.key == key),
            matching: find.byType(InkWell))
        .first);

    // Stickers per row, from how far apart the first two are.
    double perRow(WidgetTester tester) =>
        450 / (sticker(tester, "a1").left - sticker(tester, "a0").left);

    testWidgets("Ctrl + wheel steps one per row at a time", (tester) async {
      preference.set(zoom.sizeFor(450, 4));
      await pumpPicker(tester);
      expect(perRow(tester), closeTo(4, 1e-6));

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      final at = tester.getCenter(find.byType(GridColumnsZoom));
      await tester.sendEventToBinding(mouse.hover(at));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      for (final expected in [5, 6, 7]) {
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 60)));
        // Under way: between the two counts.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(perRow(tester), inExclusiveRange(expected - 1, expected));
        await tester.pumpAndSettle();
        expect(perRow(tester), closeTo(expected, 1e-6));
        expect(zoom.columns(450), expected);
      }
      // 7 is the most at 450 px (64 px each).
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 60)));
      await tester.pumpAndSettle();
      expect(perRow(tester), closeTo(7, 1e-6));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -60)));
      await tester.pumpAndSettle();
      expect(perRow(tester), closeTo(6, 1e-6));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets("a pinch follows the fingers between counts, then settles",
        (tester) async {
      preference.set(zoom.sizeFor(450, 4));
      await pumpPicker(tester);
      final center = tester.getCenter(find.byType(GridColumnsZoom));
      final a = await tester.startGesture(center - const Offset(60, 0),
          kind: PointerDeviceKind.touch, pointer: 1);
      final b = await tester.startGesture(center + const Offset(60, 0),
          kind: PointerDeviceKind.touch, pointer: 2);
      await tester.pump();

      // Fingers a little closer: smaller stickers, between 4 and 5 per row.
      await a.moveBy(const Offset(10, 0));
      await b.moveBy(const Offset(-10, 0));
      await tester.pump();
      final width = sticker(tester, "a0").width;
      expect(width, closeTo(450 / (4 * 120 / 100), 1e-6));
      expect(perRow(tester), inExclusiveRange(4, 5));

      // Closer still: past 5, toward 6.
      await a.moveBy(const Offset(8, 0));
      await b.moveBy(const Offset(-8, 0));
      await tester.pump();
      expect(450 / sticker(tester, "a0").width, closeTo(4 * 120 / 84, 1e-6));

      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      // 5.71 per row: past a third of the way to 6.
      expect(perRow(tester), closeTo(6, 1e-6));
      expect(zoom.columns(450), 6);
    });

    testWidgets("the sticker under the fingers stays put", (tester) async {
      preference.set(zoom.sizeFor(450, 4));
      await pumpPicker(tester);
      final scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable).last);
      scrollable.position.jumpTo(700);
      await tester.pump();

      final grid = tester.getRect(find.byType(GridColumnsZoom));
      final focal = Offset(grid.left + 60, grid.top + 150);
      // The sticker there and how far down it the point is.
      final hit = tester.hitTestOnBinding(focal);
      String? key;
      for (final entry in hit.path) {
        final target = entry.target;
        if (target is RenderMetaData && target.metaData is Emoticon) {
          key = (target.metaData as Emoticon).key;
          break;
        }
      }
      expect(key, isNotNull);
      final before = sticker(tester, key!);
      final share = (focal.dy - before.top) / before.height;

      final a = await tester.startGesture(focal - const Offset(0, 50),
          kind: PointerDeviceKind.touch, pointer: 1);
      final b = await tester.startGesture(focal + const Offset(0, 50),
          kind: PointerDeviceKind.touch, pointer: 2);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await a.moveBy(const Offset(0, -6));
        await b.moveBy(const Offset(0, 6));
        await tester.pump();
        final now = sticker(tester, key);
        expect(now.top + share * now.height, closeTo(focal.dy, 0.5),
            reason: "move $i");
      }
      await a.up();
      await b.up();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = sticker(tester, key);
        expect(now.top + share * now.height, closeTo(focal.dy, 0.5),
            reason: "settling $i");
      }
      await tester.pumpAndSettle();
      // 4 / 1.6 = 2.5 per row: half way past 3, so 2.
      expect(zoom.columns(450), 2);
      expect(sticker(tester, key).width, closeTo(225, 1e-6));
      final now = sticker(tester, key);
      expect(now.top + share * now.height, closeTo(focal.dy, 0.5));
    });
  });
}
