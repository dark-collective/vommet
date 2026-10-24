import 'package:commet/main.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 567: a long swipe from the room list back to Home snapped
// back to the room list, because the panels only changed side when the drag
// ended between 20% and 80% of the screen.
void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  late GlobalKey<OverlappingPanelsState> panels;
  late List<RevealSide> sides;
  const middle = Offset(400, 300);

  Future<void> pumpPanels(WidgetTester tester, {bool withRight = true}) async {
    panels = GlobalKey<OverlappingPanelsState>();
    sides = [];
    const fill = SizedBox.expand(child: ColoredBox(color: Colors.grey));
    await tester.pumpWidget(MaterialApp(
      home: OverlappingPanels(
        key: panels,
        left: fill,
        main: fill,
        right: withRight ? fill : null,
        onSideChange: sides.add,
      ),
    ));
  }

  Future<void> openLeft(WidgetTester tester) async {
    panels.currentState!.reveal(RevealSide.left);
    await tester.pumpAndSettle();
    sides.clear();
  }

  // Slow enough not to count as a flick.
  Future<void> slowDrag(WidgetTester tester, Offset by) async {
    await tester.timedDragFrom(middle, by, const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  RevealSide side() => panels.currentState!.currentSide;

  testWidgets("a long slow swipe from the left panel goes back to main",
      (tester) async {
    await pumpPanels(tester, withRight: false);
    await openLeft(tester);

    await slowDrag(tester, const Offset(-760, 0));

    expect(side(), RevealSide.main);
    expect(panels.currentState!.translate, 0);
    expect(sides, [RevealSide.main]);
  });

  testWidgets("a short flick from the left panel goes back to main",
      (tester) async {
    await pumpPanels(tester);
    await openLeft(tester);

    await tester.flingFrom(middle, const Offset(-60, 0), 1500);
    await tester.pumpAndSettle();

    expect(side(), RevealSide.main);
    expect(sides, [RevealSide.main]);
  });

  testWidgets("a short slow drag stays on the left panel", (tester) async {
    await pumpPanels(tester);
    await openLeft(tester);

    await slowDrag(tester, const Offset(-60, 0));

    expect(side(), RevealSide.left);
  });

  testWidgets("a long slow drag from main opens the left panel",
      (tester) async {
    await pumpPanels(tester);

    await slowDrag(tester, const Offset(700, 0));

    expect(side(), RevealSide.left);
    expect(sides, [RevealSide.left]);
  });

  testWidgets("a flick from main opens the right panel", (tester) async {
    await pumpPanels(tester);

    await tester.flingFrom(middle, const Offset(-60, 0), 1500);
    await tester.pumpAndSettle();

    expect(side(), RevealSide.right);
  });

  testWidgets("a flick towards a missing panel stays on main", (tester) async {
    await pumpPanels(tester, withRight: false);

    await tester.flingFrom(middle, const Offset(-60, 0), 1500);
    await tester.pumpAndSettle();

    expect(side(), RevealSide.main);
    expect(panels.currentState!.translate, 0);
  });
}
