// Vommet (New Home): Customize Home's Undo. Each change made while
// Customize is open can be undone, newest first, back to how Home was when
// it opened; the history clears when Customize closes.
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_editor.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String _describe(HomeTabs before, HomeTabs after) =>
    describeHomeChange(before, after,
        section: (s) => "S:${s.type}", card: (c) => "C:${c.type}");

List<String> _ids(HomeTabs tabs) => [for (final t in tabs.tabs) t.id];

void main() {
  group("What Undo undoes", () {
    final home = HomeTabs.defaults;
    final overview = home.tab(HomeTabs.overview)!;

    test("tabs: added, removed, moved, renamed, icon, sidebar", () {
      final (added, id) = home.createTab(name: "Games", icon: "gamepad");
      expect(_describe(home, added), "added the Games tab");
      expect(_describe(added, added.removeTab(id)), "removed the Games tab");
      expect(_describe(home, home.moveTab(HomeTabs.overview, 3)),
          "moved the Overview tab");
      expect(_describe(home, home.replaceTab(overview.copyWith(name: "Start"))),
          "renamed the Overview tab");
      expect(_describe(home, home.replaceTab(overview.copyWith(icon: "star"))),
          "changed the Overview tab’s icon");
      expect(_describe(home, home.replaceTab(overview.copyWith(rail: true))),
          "showed Overview in the sidebar");
    });

    test("side list and main page", () {
      final withRecent =
          overview.addSection(const HomeSection(HomeSection.recent), index: 0);
      expect(_describe(home, home.replaceTab(withRecent)), "added “S:recent”");
      expect(
          _describe(home,
              home.replaceTab(overview.removeSection(HomeSection.favourites))),
          "removed “S:favourites”");
      expect(
          _describe(home,
              home.replaceTab(overview.moveSection(HomeSection.favourites, 2))),
          "moved “S:favourites”");
      final main = overview.main;
      expect(
          _describe(
              home,
              home.replaceTab(
                  overview.copyWith(main: main.remove(HomeLayout.recent)))),
          "removed “C:recent”");
      final recent = main.card(HomeLayout.recent);
      expect(
          _describe(
              home,
              home.replaceTab(overview.copyWith(
                  main: main.replace(recent.copyWith(count: 10))))),
          "changed “C:recent”");
    });
  });

  group("Undo history", () {
    final store = HomeLayoutStore.instance;
    setUp(() => store.saveTabs(HomeTabs.defaults, undoable: false));

    test("only while Customize is open; newest first; clears on close",
        () async {
      await store.saveTabs(store.tabs.value.removeTab(HomeTabs.people));
      expect(store.undoHistory.value, isEmpty);

      store.beginEditing();
      await store.saveTabs(store.tabs.value.removeTab(HomeTabs.rooms));
      await store.saveTabs(store.tabs.value.replaceTab(
          store.tabs.value.tab(HomeTabs.overview)!.copyWith(name: "Start")));
      // Not changes: the same Home again, a collapsed section.
      await store.saveTabs(store.tabs.value);
      await store.saveTabs(
          store.tabs.value.replaceTab(store.tabs.value
              .tab(HomeTabs.overview)!
              .replaceSection(
                  const HomeSection(HomeSection.favourites, collapsed: true))),
          undoable: false);
      expect(store.undoHistory.value, hasLength(2));

      await store.undo();
      expect(store.tabs.value.tab(HomeTabs.overview)!.name, "Overview");
      await store.undo();
      expect(_ids(store.tabs.value), ["overview", "rooms"]);
      expect(newHomeTab.value, HomeTabs.rooms);
      expect(store.undoHistory.value, isEmpty);
      // Nothing left: Undo does nothing.
      await store.undo();
      expect(_ids(store.tabs.value), ["overview", "rooms"]);

      await store.saveTabs(store.tabs.value.removeTab(HomeTabs.rooms));
      store.endEditing();
      expect(store.undoHistory.value, isEmpty);
    });
  });

  group("Undo button", () {
    final store = HomeLayoutStore.instance;
    setUp(() => store.saveTabs(HomeTabs.defaults, undoable: false));

    Future<void> pump(WidgetTester tester, {bool field = false}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HomeEditingScope(
              child: Column(children: [
                const HomeUndoButton(phone: false),
                if (field) const TextField(autofocus: true),
              ]),
            ),
          ),
        ));

    testWidgets("gray until a change, then undoes it", (tester) async {
      await pump(tester);
      TextButton button() =>
          tester.widget<TextButton>(find.byKey(const ValueKey("NewHomeUndo")));
      expect(button().onPressed, isNull);
      expect(find.byTooltip("Nothing to undo"), findsOneWidget);

      await store.saveTabs(store.tabs.value.removeTab(HomeTabs.people));
      await tester.pump();
      expect(button().onPressed, isNotNull);
      expect(find.byTooltip("Undo: removed the People tab"), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey("NewHomeUndo")));
      await tester.pump();
      expect(_ids(store.tabs.value), ["overview", "people", "rooms"]);
      expect(button().onPressed, isNull);

      // Reset names itself.
      await store.saveTabs(store.tabs.value.removeTab(HomeTabs.people));
      await store.saveTabs(store.tabs.value.reset(),
          label: "reset Home to default");
      await tester.pump();
      expect(find.byTooltip("Undo: reset Home to default"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("NewHomeUndo")));
      await tester.tap(find.byKey(const ValueKey("NewHomeUndo")));
      await tester.pump();
      expect(_ids(store.tabs.value), ["overview", "people", "rooms"]);

      // Leaving Customize clears the history.
      await store.saveTabs(store.tabs.value.removeTab(HomeTabs.people));
      await tester.pumpWidget(const SizedBox());
      expect(store.undoHistory.value, isEmpty);
    });

    testWidgets("Ctrl+Z undoes, except in a text field", (tester) async {
      await pump(tester);
      await store.saveTabs(store.tabs.value.removeTab(HomeTabs.people));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(_ids(store.tabs.value), ["overview", "people", "rooms"]);

      await pump(tester, field: true);
      await tester.pump();
      await store.saveTabs(store.tabs.value.removeTab(HomeTabs.people));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(_ids(store.tabs.value), ["overview", "rooms"]);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
