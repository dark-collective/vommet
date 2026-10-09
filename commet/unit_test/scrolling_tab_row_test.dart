import 'package:commet/ui/layout/scrolling_tab_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, double width) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: 44,
            child: ScrollingTabRow(
              background: Colors.black,
              children: [
                for (final t in [
                  "Members",
                  "Threads",
                  "Media",
                  "Files",
                  "Pins"
                ])
                  SizedBox(width: 80, child: Text(t)),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  final left = find.byKey(const ValueKey("scrolling-tab-row-left"));
  final right = find.byKey(const ValueKey("scrolling-tab-row-right"));

  testWidgets('everything fits: no arrows', (tester) async {
    await pump(tester, 500);
    expect(left, findsNothing);
    expect(right, findsNothing);
  });

  testWidgets('overflowing: the right arrow slides the row over',
      (tester) async {
    await pump(tester, 250);
    expect(left, findsNothing);
    expect(right, findsOneWidget);

    // Each tap slides 70 % of the width: here that reaches the end.
    await tester.tap(right);
    await tester.pumpAndSettle();
    expect(left, findsOneWidget, reason: "scrolled: an arrow back");
    expect(right, findsNothing, reason: "at the end");
    expect(tester.getRect(find.text("Pins")).right, lessThanOrEqualTo(250));

    await tester.tap(left);
    await tester.pumpAndSettle();
    expect(left, findsNothing, reason: "back at the start");
    expect(right, findsOneWidget);
  });
}
