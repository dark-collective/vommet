import 'package:commet/main.dart';
import 'package:commet/ui/atoms/rail_metrics.dart';
import 'package:commet/ui/atoms/rail_pill.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 609: with New Home on, the rail's Home button opens Home on
// its first tab (Overview by default) and shows the selected pill like the
// other rail entries.

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    newHomeTab.value = HomeTabs.overview;
  });

  test("Home opens on the first tab, not the last one shown", () async {
    await experimentNewHome.set(true);
    newHomeTab.value = HomeTabs.people;
    newHomeShowFirstTab();
    expect(newHomeTab.value, HomeTabs.overview);
  });

  test("Home leaves the shown tab alone with New Home off", () async {
    await experimentNewHome.set(false);
    newHomeTab.value = HomeTabs.people;
    newHomeShowFirstTab();
    expect(newHomeTab.value, HomeTabs.people);
  });

  test("no rail button is selected outside the main page", () async {
    await experimentNewHome.set(true);
    expect(homeRailSelected(null), isNull);
  });

  double pillHeight(WidgetTester tester) => tester
      .getSize(find.descendant(
          of: find.byType(RailSlot), matching: find.byType(AnimatedContainer)))
      .height;

  Future<void> pumpSlot(WidgetTester tester, {required bool selected}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: RailSlot(
              selected: selected,
              child: const SizedBox(width: 48, height: 48),
            ),
          ),
        ),
      ));

  testWidgets("a selected rail entry that isn't a space shows the full pill",
      (tester) async {
    await pumpSlot(tester, selected: true);
    await tester.pumpAndSettle();
    expect(pillHeight(tester), RailMetrics.current.pill(40));

    await pumpSlot(tester, selected: false);
    await tester.pumpAndSettle();
    expect(pillHeight(tester), 0);
  });
}
