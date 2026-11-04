// Vommet issue 806: the dashed "Hide offline members" row sticks to the
// member panel's bottom edge while its place at the end of a long list is
// out of sight.
import 'package:commet/ui/molecules/user_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<(GlobalKey, ScrollController)> pump(
      WidgetTester tester, int rows) async {
    final key = GlobalKey();
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        height: 600,
        child: CustomScrollView(controller: controller, slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
          SliverList(
            delegate: SliverChildBuilderDelegate(
                (context, index) => const SizedBox(height: 50),
                childCount: rows),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverToBoxAdapter(child: SizedBox(key: key, height: 40)),
          ),
        ]),
      ),
    ));
    return (key, controller);
  }

  testWidgets('pins while the row is below the edge, also on open',
      (tester) async {
    final (key, controller) = await pump(tester, 60);
    expect(toggleRowNeedsPin(key.currentContext), isTrue);

    // Scrolling, still out of sight: stays pinned (no flicker).
    for (var offset = 100.0; offset < 2500; offset += 137) {
      controller.jumpTo(offset);
      await tester.pump();
      expect(toggleRowNeedsPin(key.currentContext), isTrue,
          reason: 'offset $offset');
    }

    // Partly in view: the pinned copy still covers it.
    controller.jumpTo(controller.position.maxScrollExtent - 20);
    await tester.pump();
    expect(toggleRowNeedsPin(key.currentContext), isTrue);

    // Its place at the end is in view: no pinned copy.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(toggleRowNeedsPin(key.currentContext), isFalse);
  });

  testWidgets('short list: the row is in view, no pin', (tester) async {
    final (key, _) = await pump(tester, 3);
    expect(toggleRowNeedsPin(key.currentContext), isFalse);
  });

  testWidgets('not built yet: pin', (tester) async {
    expect(toggleRowNeedsPin(null), isTrue);
  });
}
