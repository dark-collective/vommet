import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/config/style/theme_dark.dart';

// Vommet issue 428: a right-click menu taller than the window was cut off at
// the top or bottom, so some items couldn't be reached.
void main() {
  Future<void> showMenu(WidgetTester tester, Offset at, int count) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: Stack(children: [
          ContextMenuOverlay(
            key: ValueKey(at),
            globalOffset: at,
            items: [
              for (var i = 0; i < count; i++)
                ContextMenuItem(text: "Item $i", onPressed: () {}),
            ],
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Rect menuRect(WidgetTester tester) =>
      tester.getRect(find.byType(SingleChildScrollView));

  void setWindow(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  testWidgets("a menu taller than the window fits and scrolls to every item",
      (tester) async {
    setWindow(tester, const Size(800, 300));
    for (var y in [20.0, 280.0]) {
      await showMenu(tester, Offset(400, y), 30);
      var rect = menuRect(tester);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(300));

      await tester.scrollUntilVisible(find.text("Item 29"), 100,
          scrollable: find.byType(Scrollable));
      expect(find.text("Item 29").hitTestable(), findsOneWidget);
    }
  });

  testWidgets("a short menu near the bottom edge moves up into the window",
      (tester) async {
    setWindow(tester, const Size(800, 600));
    // Lower half opens upwards; a click near the top of the lower half
    // would run the menu past the top edge.
    await showMenu(tester, const Offset(790, 310), 12);
    var rect = menuRect(tester);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(600));
    expect(rect.right, lessThanOrEqualTo(800));
    expect(find.text("Item 0").hitTestable(), findsOneWidget);
    expect(find.text("Item 11").hitTestable(), findsOneWidget);
  });

  testWidgets("a menu that fits still opens at the pointer", (tester) async {
    setWindow(tester, const Size(800, 600));
    await showMenu(tester, const Offset(100, 100), 3);
    var rect = menuRect(tester);
    expect(rect.left, 100);
    expect(rect.top, 100);
  });
}
