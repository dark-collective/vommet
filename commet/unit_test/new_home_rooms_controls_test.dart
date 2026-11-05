// Vommet: the New Home Rooms page's chips must all stay in view on desktop
// (they used to scroll sideways out of sight next to a fixed-width search
// field, cutting "Unread" off).
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpControls(WidgetTester tester,
      {required double width,
      required bool phone,
      Map<RoomsChip, int>? counts}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: RoomsControlsLayout(
              key: const ValueKey("controls"),
              phone: phone,
              chips: [
                for (final c in RoomsChip.values)
                  ChoiceChip(
                      key: ValueKey("NewHomeRoomsChip-${c.name}"),
                      label: Text(
                          RoomsModel.chipLabel(c, counts?[c], phone: phone)),
                      selected: c == RoomsChip.all,
                      showCheckmark: false,
                      onSelected: (_) {}),
              ],
              field: const SizedBox(
                  height: 38,
                  child: TextField(key: ValueKey("NewHomeRoomsSearch"))),
            ),
          ),
        ),
      ),
    ));
  }

  void expectAllChipsInView(WidgetTester tester, double width) {
    expect(RoomsChip.values, hasLength(6));
    final controls = tester.getRect(find.byKey(const ValueKey("controls")));
    final search =
        tester.getRect(find.byKey(const ValueKey("NewHomeRoomsSearch")));
    for (final c in RoomsChip.values) {
      final chip = find.byKey(ValueKey("NewHomeRoomsChip-${c.name}"));
      expect(chip.hitTestable(), findsOneWidget, reason: c.name);
      final rect = tester.getRect(chip);
      expect(rect.left, greaterThanOrEqualTo(controls.left), reason: c.name);
      expect(rect.right, lessThanOrEqualTo(controls.left + width),
          reason: "${c.name} is cut off");
      // The chips sit above the search field.
      expect(rect.bottom, lessThanOrEqualTo(search.top), reason: c.name);
    }
    // The search field spans the whole column.
    expect(search.width, width);
  }

  const searchCounts = {
    RoomsChip.all: 1234,
    RoomsChip.standalone: 321,
    RoomsChip.voice: 45,
    RoomsChip.photos: 67,
    RoomsChip.calendars: 89,
    RoomsChip.unread: 456,
  };

  for (final width in [860.0, 600.0, 420.0]) {
    testWidgets("desktop at $width px: all 6 chips in view", (tester) async {
      await pumpControls(tester, width: width, phone: false);
      expectAllChipsInView(tester, width);
    });

    testWidgets("desktop at $width px with search counts: all 6 chips in view",
        (tester) async {
      await pumpControls(tester,
          width: width, phone: false, counts: searchCounts);
      expectAllChipsInView(tester, width);
      expect(find.text("All rooms & spaces 1234"), findsOneWidget);
      expect(find.text("Unread 456"), findsOneWidget);
    });
  }

  testWidgets("phone keeps the search first and the chips scrolling sideways",
      (tester) async {
    await pumpControls(tester, width: 360, phone: true);
    final search =
        tester.getRect(find.byKey(const ValueKey("NewHomeRoomsSearch")));
    final all =
        tester.getRect(find.byKey(const ValueKey("NewHomeRoomsChip-all")));
    expect(all.top, greaterThanOrEqualTo(search.bottom));
    expect(
        find.ancestor(
            of: find.byKey(const ValueKey("NewHomeRoomsChip-all")),
            matching: find.byType(SingleChildScrollView)),
        findsOneWidget);
  });

  test("collapsed sections are remembered across restarts", () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    expect(newHomeRoomsCollapsed.value, isEmpty);
    await newHomeRoomsCollapsed.set(RoomsModel.withCollapsed(
        newHomeRoomsCollapsed.value, RoomsChip.all, ["standalone", "space:a"],
        collapsed: true));

    final stored = (await SharedPreferences.getInstance())
        .getStringList(newHomeRoomsCollapsed.key);
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(
        {newHomeRoomsCollapsed.key: stored!});
    await preferences.init();
    expect(RoomsModel.collapsedFor(newHomeRoomsCollapsed.value, RoomsChip.all),
        {"standalone", "space:a"});
  });
}
