import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 630: with New Home on, the compact (icon-only) room list
// starts with the column's tab rows as icons, the shown tab highlighted.

void main() {
  final tabs = HomeTabs.defaults.tabs;

  Future<List<String>> pump(WidgetTester tester, String? selected) async {
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 64,
          child: NewHomeCompactRows(
              tabs: tabs,
              selected: selected,
              onSelect: (tab) => opened.add(tab.id)),
        ),
      ),
    ));
    return opened;
  }

  testWidgets("one icon per tab, named on hover", (tester) async {
    await pump(tester, HomeTabs.overview);
    for (final tab in tabs) {
      expect(
          find.byKey(ValueKey("NewHomeCompactRow-${tab.id}")), findsOneWidget);
      expect(find.byTooltip(tab.name), findsOneWidget);
    }
  });

  testWidgets("tapping an icon opens its tab", (tester) async {
    final opened = await pump(tester, HomeTabs.overview);
    await tester.tap(find.byKey(const ValueKey("NewHomeCompactRow-people")));
    expect(opened, [HomeTabs.people]);
  });

  testWidgets("only the shown tab is highlighted", (tester) async {
    Color? colorOf(String id) => tester
        .widget<Material>(find
            .ancestor(
                of: find.byKey(ValueKey("NewHomeCompactRow-$id")),
                matching: find.byType(Material))
            .first)
        .color;

    await pump(tester, HomeTabs.people);
    expect(colorOf(HomeTabs.people), isNot(Colors.transparent));
    expect(colorOf(HomeTabs.overview), Colors.transparent);

    // A room is open: no tab row is highlighted, as in the column.
    await pump(tester, null);
    expect(colorOf(HomeTabs.people), Colors.transparent);
  });
}
