import 'package:commet/ui/layout/tab_swipe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direction: fast or far enough, left is the next tab', () {
    expect(TabSwipeDetector.directionOf(-60, 0), 1);
    expect(TabSwipeDetector.directionOf(60, 0), -1);
    expect(TabSwipeDetector.directionOf(-10, -900), 1);
    expect(TabSwipeDetector.directionOf(10, 900), -1);
    expect(TabSwipeDetector.directionOf(20, 100), 0);
  });

  // The panel behind (OverlappingPanels on phones) is a horizontal-drag
  // GestureDetector; it should get exactly the swipes the tabs don't take.
  Future<(List<int>, int)> swipe(WidgetTester tester,
      {required int tab,
      required Offset by,
      int tabs = 4,
      Offset from = const Offset(400, 300),
      bool Function(Offset)? startsHere,
      PointerDeviceKind kind = PointerDeviceKind.touch}) async {
    final swiped = <int>[];
    var panelDrags = 0;
    await tester.pumpWidget(MaterialApp(
      home: GestureDetector(
        onHorizontalDragEnd: (_) => panelDrags++,
        child: TabSwipeDetector(
          canSwipe: (d) => tab + d >= 0 && tab + d < tabs,
          onSwipe: swiped.add,
          startsHere: startsHere,
          child: const SizedBox.expand(child: ColoredBox(color: Colors.grey)),
        ),
      ),
    ));
    await tester.dragFrom(from, by, kind: kind);
    await tester.pumpAndSettle();
    return (swiped, panelDrags);
  }

  testWidgets('swipe left on a middle tab: next tab, panel untouched',
      (tester) async {
    final (swiped, panel) =
        await swipe(tester, tab: 1, by: const Offset(-200, 0));
    expect(swiped, [1]);
    expect(panel, 0);
  });

  testWidgets('swipe right on the first tab: falls through to the panel',
      (tester) async {
    final (swiped, panel) =
        await swipe(tester, tab: 0, by: const Offset(200, 0));
    expect(swiped, isEmpty);
    expect(panel, 1);
  });

  testWidgets('swipe left on the last tab: falls through to the panel',
      (tester) async {
    final (swiped, panel) =
        await swipe(tester, tab: 3, by: const Offset(-200, 0));
    expect(swiped, isEmpty);
    expect(panel, 1);
  });

  testWidgets('a mouse drag never changes the tab', (tester) async {
    final (swiped, _) = await swipe(tester,
        tab: 1, by: const Offset(-200, 0), kind: PointerDeviceKind.mouse);
    expect(swiped, isEmpty);
  });

  testWidgets('a swipe starting on the header goes to the panel',
      (tester) async {
    // Content starts at y = 200 (below the tab strip), x = 24 (panel edge).
    bool content(Offset p) => p.dy > 200 && p.dx > 24;
    var (swiped, panel) = await swipe(tester,
        tab: 1,
        by: const Offset(-200, 0),
        from: const Offset(400, 100),
        startsHere: content);
    expect(swiped, isEmpty, reason: "started on the header");
    expect(panel, 1);

    (swiped, panel) = await swipe(tester,
        tab: 1,
        by: const Offset(200, 0),
        from: const Offset(10, 400),
        startsHere: content);
    expect(swiped, isEmpty, reason: "started at the panel's edge");
    expect(panel, 1);

    (swiped, panel) = await swipe(tester,
        tab: 1,
        by: const Offset(-200, 0),
        from: const Offset(400, 400),
        startsHere: content);
    expect(swiped, [1], reason: "started on the tab's content");
    expect(panel, 0);
  });
}
