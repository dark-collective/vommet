import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/ui/pages/main/room_chat_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A room without components (no banner).
class _Room implements Room {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group("side column for the window width", () {
    // 70 px space bar + 250 px list + 400 px chat.
    test("everything fits", () {
      expect(ResponsiveDesktop.sideColumnFor(720, 250), DesktopSideColumn.full);
      expect(
          ResponsiveDesktop.sideColumnFor(1280, 250), DesktopSideColumn.full);
    });

    test("the list shrinks to room pictures before the column hides", () {
      expect(
          ResponsiveDesktop.sideColumnFor(719, 250), DesktopSideColumn.compact);
      // 70 + 64 + 400.
      expect(
          ResponsiveDesktop.sideColumnFor(534, 250), DesktopSideColumn.compact);
      expect(
          ResponsiveDesktop.sideColumnFor(533, 250), DesktopSideColumn.hidden);
    });

    test("a wider dragged list gives way sooner", () {
      expect(
          ResponsiveDesktop.sideColumnFor(800, 400), DesktopSideColumn.compact);
    });

    test("collapsed by hand stays collapsed at any width", () {
      expect(ResponsiveDesktop.sideColumnFor(1920, 250, collapsedByHand: true),
          DesktopSideColumn.compact);
      expect(ResponsiveDesktop.sideColumnFor(500, 250, collapsedByHand: true),
          DesktopSideColumn.hidden);
    });
  });

  group("member list", () {
    setUp(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
    });

    Future<void> pumpAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: RoomChatLayout(
          room: _Room(),
          header: const SizedBox(height: 40),
          chat: const Text("chat"),
          panel: (_) => const SizedBox(width: 250, child: Text("members")),
        ),
      ));
    }

    testWidgets("shows while the chat beside it keeps its minimum",
        (tester) async {
      await pumpAt(tester, 700);
      expect(find.text("members"), findsOneWidget);
    });

    testWidgets("hides first when the chat would get too narrow",
        (tester) async {
      await pumpAt(tester, 600);
      expect(find.text("members"), findsNothing);
      expect(find.text("chat"), findsOneWidget);
    });
  });
}
