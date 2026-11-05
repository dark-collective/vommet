import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The phone layout's back button decides whether the app may close from
  // the side reported here; a reveal from code (back opening the room list)
  // used to report nothing, so back then did nothing on the room list.
  testWidgets("revealing a side from code reports it", (tester) async {
    final key = GlobalKey<OverlappingPanelsState>();
    final sides = <RevealSide>[];
    await tester.pumpWidget(MaterialApp(
      home: OverlappingPanels(
        key: key,
        left: const Text("left"),
        main: const Text("main"),
        right: const Text("right"),
        onSideChange: sides.add,
      ),
    ));

    key.currentState!.reveal(RevealSide.left);
    await tester.pumpAndSettle();
    expect(sides, [RevealSide.left]);

    key.currentState!.reveal(RevealSide.main);
    await tester.pumpAndSettle();
    expect(sides, [RevealSide.left, RevealSide.main]);
  });
}
