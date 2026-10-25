// Vommet (New Home): Customize Home's first-time tips and the New tab /
// Rename and icon form (Vommet issues 604 and 607).
import 'package:commet/ui/organisms/new_home/new_home_editor.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("Side list | Views switch", () {
    tearDown(() => newHomeEditPart.value = HomeEditPart.side);

    testWidgets("both parts stay reachable while the editor rebuilds",
        (tester) async {
      // Like the editor: a parent that rebuilds on every change and holds
      // the switch as a const widget.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: newHomeEditPart,
            builder: (context, _) => const Column(children: [HomePartSwitch()]),
          ),
        ),
      ));
      Set<HomeEditPart> shown() => tester
          .widget<SegmentedButton<HomeEditPart>>(
              find.byKey(const ValueKey("NewHomeEditPart")))
          .selected;

      expect(shown(), {HomeEditPart.side});
      await tester.tap(find.text("Views"));
      await tester.pump();
      expect(newHomeEditPart.value, HomeEditPart.main);
      expect(shown(), {HomeEditPart.main});
      await tester.tap(find.text("Side list"));
      await tester.pump();
      expect(newHomeEditPart.value, HomeEditPart.side);
      expect(shown(), {HomeEditPart.side});
      // Changed from elsewhere ("Add a card" opens the main page).
      newHomeEditPart.value = HomeEditPart.main;
      await tester.pump();
      expect(shown(), {HomeEditPart.main});
      await tester.tap(find.text("Side list"));
      await tester.pump();
      expect(newHomeEditPart.value, HomeEditPart.side);
    });
  });

  group("Tips", () {
    testWidgets("three steps: Skip and Next, then Start customizing",
        (tester) async {
      var done = 0;
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: HomeTips(onDone: () => done++))));

      expect(find.text("Home is made of tabs"), findsOneWidget);
      expect(find.byKey(const ValueKey("NewHomeTipsSkip")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("NewHomeTipsNext")));
      await tester.pump();

      expect(find.text("Each tab has two parts"), findsOneWidget);
      expect(find.byKey(const ValueKey("NewHomeTipsSkip")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("NewHomeTipsNext")));
      await tester.pump();

      expect(find.text("You can’t break it"), findsOneWidget);
      expect(find.byKey(const ValueKey("NewHomeTipsSkip")), findsNothing);
      expect(find.byKey(const ValueKey("NewHomeTipsNext")), findsNothing);
      await tester.tap(find.text("Start customizing"));
      await tester.pump();
      expect(done, 1);
    });

    testWidgets("Skip ends the tips", (tester) async {
      var done = 0;
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: HomeTips(onDone: () => done++))));
      await tester.tap(find.byKey(const ValueKey("NewHomeTipsSkip")));
      await tester.pump();
      expect(done, 1);
    });
  });

  group("New tab form", () {
    Future<TabFormResult?> run(WidgetTester tester,
        {HomeTab? editing,
        List<HomeTab> removed = const [],
        required Future<void> Function() act}) async {
      TabFormResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showDialog<TabFormResult>(
                    context: context,
                    builder: (_) => Dialog(
                      child: SingleChildScrollView(
                        child: HomeTabForm(
                            current: HomeTabs.defaultTab(HomeTabs.overview)!,
                            removedDefaults: removed,
                            editing: editing),
                      ),
                    ),
                  );
                },
                child: const Text("open"),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();
      await act();
      await tester.tap(find.byKey(const ValueKey("NewHomeTabSubmit")));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets("an empty tab with a name and an icon", (tester) async {
      final result = await run(tester, act: () async {
        expect(find.text("New tab"), findsOneWidget);
        expect(find.text("Create tab"), findsOneWidget);
        expect(find.text("An empty tab"), findsOneWidget);
        expect(find.text("A copy of Overview"), findsOneWidget);
        await tester.enterText(
            find.byKey(const ValueKey("NewHomeTabName")), "  Gaming ");
        await tester.tap(find.byKey(const ValueKey("NewHomeTabIcon-gamepad")));
        await tester.pump();
      });
      expect(result?.name, "Gaming");
      expect(result?.icon, "gamepad");
      expect(result?.copyOf, isNull);
      expect(result?.restore, isNull);
    });

    testWidgets("a copy of the current tab", (tester) async {
      final result = await run(tester, act: () async {
        await tester.tap(find.byKey(const ValueKey("NewHomeTabStart-copy")));
        await tester.pump();
      });
      expect(result?.copyOf, HomeTabs.overview);
      expect(result?.name, "New tab");
    });

    testWidgets("a removed default tab takes its name and icon",
        (tester) async {
      final result = await run(tester,
          removed: [HomeTabs.defaultTab(HomeTabs.people)!], act: () async {
        expect(find.text("The default People tab (removed)"), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey("NewHomeTabStart-people")));
        await tester.pump();
      });
      expect(result?.restore, HomeTabs.people);
      expect(result?.name, "People");
      expect(result?.icon, HomeTabs.defaultTab(HomeTabs.people)!.icon);
    });

    testWidgets("Rename and icon: no Start with, Save", (tester) async {
      final result = await run(tester,
          editing: HomeTabs.defaultTab(HomeTabs.rooms), act: () async {
        expect(find.text("Rename and icon"), findsOneWidget);
        expect(find.text("An empty tab"), findsNothing);
        expect(find.text("Save"), findsOneWidget);
        await tester.enterText(
            find.byKey(const ValueKey("NewHomeTabName")), "Spaces");
      });
      expect(result?.name, "Spaces");
      expect(result?.icon, HomeTabs.defaultTab(HomeTabs.rooms)!.icon);
    });
  });
}
