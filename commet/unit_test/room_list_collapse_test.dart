import 'package:commet/main.dart';
import 'package:commet/ui/atoms/room_list_collapse_button.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

  group("space menu", () {
    testWidgets("offers collapsing only under the desktop room list",
        (tester) async {
      SpaceMenuEntry? entry;
      final probe = Builder(builder: (context) {
        entry = RoomListHeaderAction.menuEntry(context);
        return const SizedBox();
      });
      await tester.pumpWidget(MaterialApp(home: probe));
      expect(entry, isNull);

      await tester
          .pumpWidget(MaterialApp(home: RoomListHeaderAction(child: probe)));
      expect(entry?.label, RoomListCollapseButton.collapseRoomListTooltip);
      expect(entry?.shortcut, isNotNull);
      entry!.onSelected();
      expect(ResponsiveDesktop.collapsed.value, isTrue);
    });
  });

  group("shortcut", () {
    testWidgets("Ctrl+Shift+B collapses the list and widens it again",
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: RoomListCollapseShortcut(child: SizedBox())));
      Future<void> press() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }

      await press();
      expect(ResponsiveDesktop.collapsed.value, isTrue);
      await press();
      expect(ResponsiveDesktop.collapsed.value, isFalse);

      // Ctrl+B alone (bold in the composer) leaves it be.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(ResponsiveDesktop.collapsed.value, isFalse);
    });
  });

  group("dragging the edge", () {
    Widget edge(Widget handle) => MaterialApp(
          home: Scaffold(
            body: Row(children: [
              const SizedBox(width: 300),
              SizedBox(height: 300, child: handle),
            ]),
          ),
        );

    testWidgets("far past the narrowest width collapses the list",
        (tester) async {
      final pane = PaneWidths.left;
      final before = pane.value;
      var collapsed = false;
      await tester.pumpWidget(
          edge(PaneResizeHandle(pane, onCollapse: () => collapsed = true)));
      await tester.timedDrag(
          find.byType(PaneResizeHandle),
          Offset(-(before - pane.min) - PaneWidth.collapsePull - 60, 0),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(collapsed, isTrue);
      expect(pane.value, before);
    });

    testWidgets("a short drag only resizes", (tester) async {
      final pane = PaneWidths.left;
      var collapsed = false;
      await tester.pumpWidget(
          edge(PaneResizeHandle(pane, onCollapse: () => collapsed = true)));
      await tester.timedDrag(find.byType(PaneResizeHandle),
          const Offset(-40, 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(collapsed, isFalse);
      await pane.reset();
    });

    testWidgets("the collapsed list's edge drags back out", (tester) async {
      var expanded = false;
      await tester.pumpWidget(
          edge(CollapsedPaneHandle(onExpand: () => expanded = true)));
      await tester.timedDrag(find.byType(CollapsedPaneHandle),
          const Offset(20, 0), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(expanded, isFalse);
      await tester.timedDrag(find.byType(CollapsedPaneHandle),
          const Offset(80, 0), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(expanded, isTrue);
    });
  });
}
