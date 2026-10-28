import 'package:commet/main.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 322: a panel sliding out of view gives up the keyboard focus,
// so typing never goes into a message box you can't see.
void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  late FocusNode room;
  late FocusNode thread;
  late FocusNode roomList;
  late FocusNode outside;
  late GlobalKey<OverlappingPanelsState> panels;

  Future<void> pumpPanels(WidgetTester tester) async {
    room = FocusNode(debugLabel: "room");
    thread = FocusNode(debugLabel: "thread");
    roomList = FocusNode(debugLabel: "room list");
    outside = FocusNode(debugLabel: "outside");
    addTearDown(() {
      for (final node in [room, thread, roomList, outside]) {
        node.dispose();
      }
    });
    panels = GlobalKey<OverlappingPanelsState>();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: OverlappingPanels(
              key: panels,
              left: Material(child: TextField(focusNode: roomList)),
              main: Material(child: TextField(focusNode: room)),
              right: Material(child: TextField(focusNode: thread)),
            ),
          ),
          TextField(focusNode: outside),
        ]),
      ),
    ));
  }

  Future<void> reveal(WidgetTester tester, RevealSide side) async {
    panels.currentState!.reveal(side);
    await tester.pumpAndSettle();
  }

  Future<void> focus(WidgetTester tester, FocusNode node) async {
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);
  }

  testWidgets("opening a thread takes the focus from the room's message box",
      (tester) async {
    await pumpPanels(tester);
    await focus(tester, room);

    await reveal(tester, RevealSide.right);

    expect(room.hasFocus, isFalse);
  });

  testWidgets("the thread's message box keeps a focus it took while opening",
      (tester) async {
    await pumpPanels(tester);
    await focus(tester, room);

    // As "Reply in Thread" does: the thread's box asks for the focus in the
    // frame the panel starts sliding in, before the slide has finished.
    panels.currentState!.reveal(RevealSide.right);
    await tester.pump();
    thread.requestFocus();
    await tester.pumpAndSettle();

    expect(thread.hasFocus, isTrue);
    expect(room.hasFocus, isFalse);
  });

  testWidgets("going back to the room takes the focus from the thread",
      (tester) async {
    await pumpPanels(tester);
    await reveal(tester, RevealSide.right);
    await focus(tester, thread);

    await reveal(tester, RevealSide.main);

    expect(thread.hasFocus, isFalse);
  });

  testWidgets("the room list takes the focus from the room", (tester) async {
    await pumpPanels(tester);
    await focus(tester, room);

    await reveal(tester, RevealSide.left);

    expect(room.hasFocus, isFalse);
  });

  testWidgets("staying on the room keeps its focus", (tester) async {
    await pumpPanels(tester);
    await focus(tester, room);

    await reveal(tester, RevealSide.main);

    expect(room.hasFocus, isTrue);
  });

  testWidgets("focus outside the panels is left alone", (tester) async {
    await pumpPanels(tester);
    await focus(tester, outside);

    await reveal(tester, RevealSide.right);
    await reveal(tester, RevealSide.main);

    expect(outside.hasFocus, isTrue);
  });
}
