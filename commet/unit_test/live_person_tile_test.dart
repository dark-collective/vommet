import 'package:commet/ui/organisms/call_view/live_person_tile.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet: a sharer's own tile only carries LIVE (their stream has its own
// tile); a click goes through to the call view, which shows the person.
void main() {
  testWidgets("carries LIVE and offers no stream button", (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 180,
              child: GestureDetector(
                onTap: () => tapped++,
                child: const LivePersonTile(
                  child: ColoredBox(color: Colors.blueGrey),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(LivePersonTile)));
    await tester.pump();

    expect(find.text(StreamWatchCard.streamLiveBadge), findsOneWidget);
    expect(find.text(StreamWatchCard.streamWatchButton), findsNothing);
    expect(find.text(StreamWatchCard.streamWatchShort), findsNothing);

    await tester.tap(find.byType(LivePersonTile));
    expect(tapped, 1);
  });
}
