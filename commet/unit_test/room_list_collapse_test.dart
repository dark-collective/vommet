import 'package:commet/main.dart';
import 'package:commet/ui/atoms/room_list_collapse_button.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 456: the room list's collapse button sits in its header row,
// and the panes' resize edges show they can be dragged.
void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await ResponsiveDesktop.setCollapsed(false);
  });

  Widget header() => Builder(
      builder: (context) =>
          RoomListHeaderAction.of(context) ?? const Text("no button"));

  group("collapse button", () {
    testWidgets("only header rows under the desktop room list get it",
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: header())));
      expect(find.text("no button"), findsOneWidget);

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: RoomListHeaderAction(child: header()))));
      expect(find.byType(RoomListCollapseButton), findsOneWidget);
    });

    testWidgets("collapses the list, and the collapsed one widens it",
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: RoomListHeaderAction(child: header()))));
      await tester.tap(find.byType(RoomListCollapseButton));
      expect(ResponsiveDesktop.collapsed.value, isTrue);

      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: RoomListCollapseButton(collapsed: true))));
      await tester.tap(find.byType(RoomListCollapseButton));
      expect(ResponsiveDesktop.collapsed.value, isFalse);
    });
  });

  group("resize edge", () {
    Finder edge() => find.descendant(
        of: find.byType(PaneResizeHandle),
        matching: find.byType(AnimatedOpacity));

    double edgeOpacity(WidgetTester tester) =>
        tester.widget<AnimatedOpacity>(edge()).opacity;

    testWidgets("shows the resize cursor and lights up under the pointer",
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            const SizedBox(width: 200),
            SizedBox(height: 300, child: PaneResizeHandle(PaneWidths.left)),
          ]),
        ),
      ));
      expect(edgeOpacity(tester), 0);

      final mouse =
          await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 1);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(PaneResizeHandle)));
      await tester.pumpAndSettle();
      expect(edgeOpacity(tester), 1);
      final cursor =
          // ignore: invalid_use_of_visible_for_testing_member
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
      expect(cursor, SystemMouseCursors.resizeColumn);

      await mouse.moveTo(const Offset(50, 50));
      await tester.pumpAndSettle();
      expect(edgeOpacity(tester), 0);
    });
  });
}
