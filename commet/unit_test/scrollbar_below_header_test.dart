import 'package:commet/ui/layout/collapsing_header.dart';
import 'package:commet/ui/layout/scrollbar_below_header.dart';
import 'package:commet/ui/layout/scrolling_tab_row.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final stripKey = GlobalKey();

  // The side panel's shape: a banner that collapses from 100 to 40, the tab
  // strip pinned under it, then a long list.
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 250,
            height: 400,
            child: ScrollbarBelowHeader(
              headerKey: stripKey,
              builder: (context, controller, behavior) => CustomScrollView(
                controller: controller,
                scrollBehavior: behavior,
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: CollapsingHeaderDelegate(
                        minHeight: 40,
                        maxHeight: 100,
                        builder: (context, _) => const SizedBox.expand()),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: CollapsingHeaderDelegate(
                      minHeight: 44,
                      maxHeight: 44,
                      builder: (context, _) => ScrollingTabRow(
                        key: stripKey,
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
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                        (context, i) => SizedBox(height: 50, child: Text("$i")),
                        childCount: 100),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // The scrollbar's top inset (it reads MediaQuery's padding).
  double scrollbarTop(WidgetTester tester) =>
      MediaQuery.of(tester.element(find.byType(Scrollbar))).padding.top;

  testWidgets('the scrollbar starts under the tab strip, following it',
      (tester) async {
    await pump(tester);
    expect(find.byType(Scrollbar), findsOneWidget,
        reason: "one scrollbar: ours, not the scroll view's own");
    expect(scrollbarTop(tester), 144, reason: "banner 100 + strip 44");

    await tester.drag(find.text("3"), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(scrollbarTop(tester), 84, reason: "banner collapsed to 40");
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('the more-tabs arrow is clickable with the scrollbar shown',
      (tester) async {
    await pump(tester);
    final right = find.byKey(const ValueKey("scrolling-tab-row-right"));
    // Hovering the right edge shows a desktop scrollbar.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(right));
    await tester.pumpAndSettle();

    await tester.tap(right, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("scrolling-tab-row-left")), findsOneWidget,
        reason: "the click reached the arrow, which slid the row");
    await mouse.removePointer();
  }, variant: TargetPlatformVariant.desktop());
}
