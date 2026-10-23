import 'package:commet/main.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 628: with New Home on, the shown Home tab's sidebar button
// stays lit (not Home's) while a room opened from its side list is open.
// The rule no longer looks at the open room at all.

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await experimentNewHome.set(true);
  });

  test("People's button is lit while People is shown", () async {
    await peopleInRail.set(true);
    newHomeTab.value = HomeTabs.people;
    expect(homeRailLitTab(), HomeTabs.people);
  });

  test("Home's button is lit for a tab without its own button", () async {
    await peopleInRail.set(false);
    newHomeTab.value = HomeTabs.people;
    expect(homeRailLitTab(), isNull);

    await peopleInRail.set(true);
    newHomeTab.value = HomeTabs.overview;
    expect(homeRailLitTab(), isNull);
  });
}
