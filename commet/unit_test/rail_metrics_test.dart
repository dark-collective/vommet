// Vommet: the sidebar icon size setting (Vommet issue 506).

import 'package:commet/main.dart';
import 'package:commet/ui/atoms/rail_metrics.dart';
import 'package:commet/ui/pages/settings/categories/app/sidebar_icon_size_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("the default size draws the original rail", () {
    expect(preferences.sidebarIconSize.value, RailMetrics.defaultIconSize);
    final rail = RailMetrics.current;
    expect(rail.iconSize, 56);
    expect(rail.slot, 70);
    expect(rail.railWidth, 70);
    expect(rail.margin, 0);
    expect(rail.sidePadding, 7);
    expect(rail.rowPadding, 2);
    expect(rail.pill(40), 40);
  });

  test("Discord's size: 40 px icons, 4 px apart rows, centred on the rail", () {
    final rail = RailMetrics(RailMetrics.discordIconSize);
    expect(rail.slot, 50);
    expect(rail.railWidth, 70);
    expect(rail.margin + rail.sidePadding, 15);
    expect(rail.rowPadding, 4);
    expect(rail.iconSize + 2 * rail.rowPadding, 48);
  });

  test("big icons widen the rail; sizes are clamped", () {
    expect(RailMetrics(64).railWidth, 80);
    expect(RailMetrics(64).margin, 0);
    expect(RailMetrics(10).iconSize, RailMetrics.minIconSize);
    expect(RailMetrics(100).iconSize, RailMetrics.maxIconSize);
    expect(RailMetrics(32).rowPadding, 5);
  });

  test("the setting changes the current metrics", () async {
    await preferences.sidebarIconSize.set(48);
    expect(RailMetrics.current.iconSize, 48);
    await preferences.sidebarIconSize.set(RailMetrics.defaultIconSize);
  });

  test("the slider labels the default and Discord's size", () {
    expect(SidebarIconSizeSetting.format(56), "56 px (default)");
    expect(SidebarIconSizeSetting.format(40), "40 px (Discord)");
    expect(SidebarIconSizeSetting.format(48), "48 px");
  });
}
