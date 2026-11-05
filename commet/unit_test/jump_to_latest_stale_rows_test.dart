// Vommet issue 726: after scrolling far back by hand, "Jump to latest"
// stopped short of the newest messages. Rows that grew after they were laid
// out (pictures, previews) leave the history list's offsets stale; at offset
// 0 Flutter fixes them one row per layout and moves the view up each time.
// The timeline now gives the history list a fresh key when it lands, as
// this test's list does.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Timeline extends StatefulWidget {
  const _Timeline({required this.heights});

  final List<double> heights;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  final controller = ScrollController();
  GlobalKey centerKey = GlobalKey();

  void grow(double height) => setState(() {
        for (var i = 0; i < widget.heights.length; i++) {
          widget.heights[i] = height;
        }
      });

  void jumpToLatest({required bool freshList}) => setState(() {
        if (freshList) centerKey = GlobalKey();
        controller.jumpTo(0);
      });

  @override
  Widget build(BuildContext context) => CustomScrollView(
        controller: controller,
        reverse: true,
        center: centerKey,
        slivers: [
          SliverList(
              delegate: SliverChildBuilderDelegate(
                  childCount: 0, (context, index) => null)),
          SliverList(
            key: centerKey,
            delegate: SliverChildBuilderDelegate(
              childCount: widget.heights.length,
              (context, index) => SizedBox(
                  height: widget.heights[index], child: Text("row $index")),
            ),
          ),
        ],
      );
}

Future<_TimelineState> _scrolledBack(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: SizedBox(
        height: 400,
        child: _Timeline(heights: List.filled(200, 50.0, growable: false))),
  ));
  final state = tester.state<_TimelineState>(find.byType(_Timeline));
  state.controller.jumpTo(9000);
  await tester.pump();
  expect(find.text("row 0"), findsNothing);
  // The rows above the view got taller while they were out of sight.
  state.grow(100);
  await tester.pump();
  return state;
}

void main() {
  testWidgets("a plain jump stops short over stale rows", (tester) async {
    final state = await _scrolledBack(tester);
    state.jumpToLatest(freshList: false);
    await tester.pump();
    expect(find.text("row 0"), findsNothing);
  });

  testWidgets("a fresh history list lands on the newest row", (tester) async {
    final state = await _scrolledBack(tester);
    state.jumpToLatest(freshList: true);
    await tester.pump();
    expect(find.text("row 0"), findsOneWidget);
    expect(state.controller.offset, 0);
  });
}
