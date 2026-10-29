import 'package:commet/ui/organisms/call_view/stream_tile.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet: every screen share has its own tile in the call view, as on
// Discord: thumbnail, LIVE, the sharer's name and who's watching; Watch
// stream and a small icon on hover (always shown without a mouse).
void main() {
  Future<({List<String> calls})> pumpTile(
    WidgetTester tester, {
    StreamTileState state = StreamTileState.idle,
    StreamTileSmallAction small = StreamTileSmallAction.miniPlayer,
    bool alwaysShowButtons = false,
    bool hover = true,
    String? title,
  }) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 202,
              child: StreamTile(
                name: "Pell",
                title: title,
                background: const ColoredBox(color: Colors.blueGrey),
                viewers: const Text("2 viewers"),
                state: state,
                small: small,
                alwaysShowButtons: alwaysShowButtons,
                onWatch: () => calls.add("watch"),
                onSmall: () => calls.add("small"),
                onShowHere: () => calls.add("showHere"),
              ),
            ),
          ),
        ),
      ),
    );
    if (hover) {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(StreamTile)));
      await tester.pump();
    }
    return (calls: calls);
  }

  Finder richTextContaining(String text) => find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains(text),
      );

  testWidgets("shows LIVE, the sharer's name and who's watching", (
    tester,
  ) async {
    await pumpTile(tester, hover: false, title: "Hollow Peaks");
    expect(find.text(StreamWatchCard.streamLiveBadge), findsOneWidget);
    expect(richTextContaining("Pell · Hollow Peaks"), findsOneWidget);
    expect(find.text("2 viewers"), findsOneWidget);
    // No mouse over it: no buttons yet.
    expect(find.text(StreamWatchCard.streamWatchButton), findsNothing);
  });

  testWidgets("the name is shown without a title", (tester) async {
    await pumpTile(tester, hover: false);
    expect(richTextContaining("Pell"), findsOneWidget);
    expect(richTextContaining("·"), findsNothing);
  });

  testWidgets("pointing shows Watch stream, which calls onWatch", (
    tester,
  ) async {
    final r = await pumpTile(tester);
    expect(find.text(StreamWatchCard.streamWatchButton), findsOneWidget);
    await tester.tap(find.text(StreamWatchCard.streamWatchButton));
    expect(r.calls, ["watch"]);
  });

  testWidgets("without a mouse the buttons are always shown", (tester) async {
    final r = await pumpTile(tester, hover: false, alwaysShowButtons: true);
    expect(find.text(StreamWatchCard.streamWatchButton), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("streamTileSmall")));
    expect(r.calls, ["small"]);
  });

  testWidgets("shown big: says so, no Watch button, a click does nothing", (
    tester,
  ) async {
    final r = await pumpTile(tester, state: StreamTileState.shownBig);
    expect(find.text(StreamWatchCard.streamWatchButton), findsNothing);
    expect(find.text(StreamTile.streamTileShownBig), findsOneWidget);
    await tester.tap(find.byType(StreamTile));
    expect(r.calls, isEmpty);
  });

  testWidgets("in the mini-player: says so, Show here docks it back", (
    tester,
  ) async {
    final r = await pumpTile(tester, state: StreamTileState.inMiniPlayer);
    expect(find.text(StreamTile.streamTileInMiniPlayer), findsOneWidget);
    expect(find.text(StreamWatchCard.streamWatchButton), findsNothing);
    await tester.tap(find.text(StreamTile.streamTileShowHere));
    expect(r.calls, ["showHere"]);
  });

  group("small icon", () {
    tearDown(() => StreamTile.popOutWindow = null);

    test("another stream big: side by side", () {
      expect(
        StreamTile.smallActionFor(othersBig: true, phone: false),
        StreamTileSmallAction.sideBySide,
      );
      expect(
        StreamTile.smallActionFor(othersBig: true, phone: true),
        StreamTileSmallAction.sideBySide,
      );
    });

    test("phone: mini-player", () {
      StreamTile.popOutWindow = (_, __) async {};
      expect(
        StreamTile.smallActionFor(othersBig: false, phone: true),
        StreamTileSmallAction.miniPlayer,
      );
    });

    test("desktop: mini-player until the pop-out window exists", () {
      expect(
        StreamTile.smallActionFor(othersBig: false, phone: false),
        StreamTileSmallAction.miniPlayer,
      );
      StreamTile.popOutWindow = (_, __) async {};
      expect(
        StreamTile.smallActionFor(othersBig: false, phone: false),
        StreamTileSmallAction.popOutWindow,
      );
    });

    for (final small in StreamTileSmallAction.values) {
      testWidgets("${small.name}: its icon and tooltip, calls onSmall", (
        tester,
      ) async {
        final r = await pumpTile(tester, small: small);
        expect(find.byIcon(StreamTile.smallIcon(small)), findsOneWidget);
        expect(find.byTooltip(StreamTile.smallLabel(small)), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey("streamTileSmall")));
        expect(r.calls, ["small"]);
      });
    }
  });

  testWidgets("long press offers Watch stream and the mini-player", (
    tester,
  ) async {
    final r = await pumpTile(tester, hover: false, alwaysShowButtons: true);
    await tester.longPress(find.byType(StreamTile));
    await tester.pumpAndSettle();
    expect(find.text(StreamTile.streamTileMiniPlayer), findsOneWidget);
    await tester.tap(find.text(StreamTile.streamTileMiniPlayer));
    await tester.pumpAndSettle();
    expect(r.calls, ["small"]);
  });
}
