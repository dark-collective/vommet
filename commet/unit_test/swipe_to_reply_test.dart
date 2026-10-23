import 'package:commet/ui/molecules/timeline_events/swipe_to_reply.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SwipeToReply.startsAtEdge', () {
    test('only near the right edge', () {
      expect(SwipeToReply.startsAtEdge(390, 400, 0), isTrue);
      expect(SwipeToReply.startsAtEdge(352, 400, 0), isTrue);
      expect(SwipeToReply.startsAtEdge(351, 400, 0), isFalse);
      expect(SwipeToReply.startsAtEdge(200, 400, 0), isFalse);
    });

    test('moves in past the system gesture strip', () {
      expect(SwipeToReply.startsAtEdge(330, 400, 24), isTrue);
      expect(SwipeToReply.startsAtEdge(327, 400, 24), isFalse);
    });
  });

  group('SwipeToReply.offsetFor', () {
    test('never moves right', () {
      expect(SwipeToReply.offsetFor(30), 0);
    });

    test('follows the finger up to the trigger distance', () {
      expect(SwipeToReply.offsetFor(-40), -40);
      expect(SwipeToReply.offsetFor(-SwipeToReply.triggerDistance),
          -SwipeToReply.triggerDistance);
    });

    test('slows down past it and stops at the maximum', () {
      final past = SwipeToReply.offsetFor(-SwipeToReply.triggerDistance - 30);
      expect(past, lessThan(-SwipeToReply.triggerDistance));
      expect(past, greaterThan(-SwipeToReply.triggerDistance - 30));
      expect(SwipeToReply.offsetFor(-1000), -SwipeToReply.maxDistance);
    });
  });

  group('SwipeToReply gesture', () {
    Future<({int replies, int panelDrags})> swipe(
        WidgetTester tester, double startX, double dx,
        {bool canReply = true}) async {
      var replies = 0;
      var panelDrags = 0;
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: GestureDetector(
          // Stands in for the side panels' drag.
          onHorizontalDragUpdate: (_) => panelDrags++,
          child: Align(
            alignment: Alignment.topCenter,
            child: SwipeToReply(
              replyAction: () => canReply ? () => replies++ : null,
              child: const ColoredBox(
                  color: Colors.white, child: SizedBox(height: 60, width: 400)),
            ),
          ),
        ),
      ));

      final gesture = await tester.startGesture(Offset(startX, 30));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(Offset(dx / 10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      return (replies: replies, panelDrags: panelDrags);
    }

    testWidgets('a swipe from the right edge replies', (tester) async {
      final result = await swipe(tester, 390, -120);
      expect(result.replies, 1);
      expect(result.panelDrags, 0);
    });

    testWidgets('a short swipe from the edge does not', (tester) async {
      final result = await swipe(tester, 390, -30);
      expect(result.replies, 0);
    });

    testWidgets('a swipe from the middle goes to the panels', (tester) async {
      final result = await swipe(tester, 200, -120);
      expect(result.replies, 0);
      expect(result.panelDrags, greaterThan(0));
    });

    testWidgets('a message without Reply leaves the drag to the panels',
        (tester) async {
      final result = await swipe(tester, 390, -120, canReply: false);
      expect(result.replies, 0);
      expect(result.panelDrags, greaterThan(0));
    });
  });
}
