import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:commet/ui/pages/main/room_chat_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A room without components (no banner).
class _Room implements Room {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Stands in for RoomSidePanel: reports its state from inside setState, so the
// layout rebuilds in the same frame, before the panel's new content exists.
class _Panel extends StatefulWidget {
  const _Panel(this.onStateChanged, {super.key});
  final ValueChanged<SidePanelState> onStateChanged;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  SidePanelState _state = SidePanelState.defaultView;

  void show(SidePanelState state) => setState(() {
        _state = state;
        widget.onStateChanged(state);
      });

  @override
  Widget build(BuildContext context) => _state == SidePanelState.thread
      // Fills whatever width it gets: throws unless the layout bounds it.
      ? const SizedBox(
          key: ValueKey("thread"),
          width: double.infinity,
          child: Text("thread"))
      : const SizedBox(width: 250, child: Text("members"));
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    // The Discord-style layout makes the member list resizable.
    await preferences.experimentBannerLayout.set(true);
  });

  testWidgets("closing a thread goes back to the member list", (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final panelKey = GlobalKey<_PanelState>();
    await tester.pumpWidget(MaterialApp(
      home: RoomChatLayout(
        room: _Room(),
        header: const SizedBox(height: 40),
        chat: const Text("chat"),
        panel: (onStateChanged) => _Panel(onStateChanged, key: panelKey),
      ),
    ));
    expect(find.text("members"), findsOneWidget);

    panelKey.currentState!.show(SidePanelState.thread);
    await tester.pump();
    expect(tester.takeException(), isNull);
    // A thread shares the room with the chat.
    expect(tester.getSize(find.byKey(const ValueKey("thread"))).width,
        greaterThan(250));

    panelKey.currentState!.show(SidePanelState.defaultView);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text("members"), findsOneWidget);
    expect(find.text("chat"), findsOneWidget);
  });

  testWidgets("the panel toggle floats the member list in a narrow window",
      (tester) async {
    // Too narrow for the member list beside a 400 px chat.
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final panelKey = GlobalKey<_PanelState>();
    await tester.pumpWidget(MaterialApp(
      home: RoomChatLayout(
        room: _Room(),
        // The toggle arrow reads whether the panel is on screen.
        header: SizedBox(
            height: 40,
            child: Builder(
                builder: (context) => Text(RoomChatLayout.panelShownOf(context)!
                    ? "shown"
                    : "hidden"))),
        chat: const Text("chat"),
        panel: (onStateChanged) => _Panel(onStateChanged, key: panelKey),
      ),
    ));
    expect(find.text("members"), findsNothing);
    expect(find.text("hidden"), findsOneWidget);

    // Open: the list floats over the chat.
    expect(
        RoomChatLayout.toggleFloatingMembers(panelKey.currentContext!), isTrue);
    await tester.pump();
    expect(find.text("members"), findsOneWidget);
    expect(find.text("chat"), findsOneWidget);
    expect(find.text("shown"), findsOneWidget);

    // Tapping the dimmed chat closes it again.
    await tester.tapAt(const Offset(20, 400));
    await tester.pump();
    expect(find.text("members"), findsNothing);
    expect(find.text("hidden"), findsOneWidget);

    // Opened from a closed panel: the panel's own toggle runs (false) and
    // the member list it shows floats.
    panelKey.currentState!.show(SidePanelState.nothing);
    await tester.pump();
    expect(RoomChatLayout.toggleFloatingMembers(panelKey.currentContext!),
        isFalse);
    panelKey.currentState!.show(SidePanelState.defaultView);
    await tester.pump();
    expect(find.text("members"), findsOneWidget);

    // Widened: the list sits beside the chat, and the toggle is the panel's.
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pump();
    expect(find.text("members"), findsOneWidget);
    expect(RoomChatLayout.toggleFloatingMembers(panelKey.currentContext!),
        isFalse);
  });
}
