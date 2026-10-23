// Vommet: Overview's header shows a visible "Customize" button (it was hidden
// in a ⋯ menu), and the bottom of Overview has a dashed "Add a card" tile.
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_main.dart';
import 'package:commet/ui/organisms/new_home/new_home_overview.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => newHomeCustomizing.value = false);

  Future<void> pumpHeader(WidgetTester tester, {required bool phone}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: phone ? 380 : 1200,
            child: NewHomeHeader(
                tab: HomeTabs.defaultTab(HomeTabs.overview)!, phone: phone),
          ),
        ),
      ));

  for (final phone in [false, true]) {
    testWidgets("header: a Customize button, no ⋯ menu (phone: $phone)",
        (tester) async {
      await pumpHeader(tester, phone: phone);
      final button = find.byKey(const ValueKey("NewHomeCustomizeButton"));
      expect(button, findsOneWidget);
      expect(find.descendant(of: button, matching: find.text("Customize")),
          findsOneWidget);
      expect(
          find.descendant(
              of: button,
              matching: find.byIcon(Icons.dashboard_customize_rounded)),
          findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });
  }

  testWidgets("header in customize mode: the Customizing tag instead",
      (tester) async {
    newHomeCustomizing.value = true;
    await pumpHeader(tester, phone: false);
    expect(find.byKey(const ValueKey("NewHomeCustomizingTag")), findsOneWidget);
    expect(find.byKey(const ValueKey("NewHomeCustomizeButton")), findsNothing);
  });

  testWidgets("every tab has the Customize button and shows its name",
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: NewHomeHeader(
              tab: HomeTabs.defaultTab(HomeTabs.rooms)!, phone: false)),
    ));
    expect(
        find.byKey(const ValueKey("NewHomeCustomizeButton")), findsOneWidget);
    expect(find.text("Rooms"), findsOneWidget);
  });

  testWidgets("the Add a card tile is full width and opens customizing",
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AddCardTile(onTap: () => taps++),
        ]),
      ),
    ));
    expect(find.text("Add a card"), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byType(DashedOutline), findsOneWidget);
    final tile =
        tester.getRect(find.byKey(const ValueKey("NewHomeAddCardTile")));
    expect(tile.width, tester.getSize(find.byType(Scaffold)).width);
    await tester.tap(find.text("Add a card"));
    expect(taps, 1);
  });
}
