// Vommet: Theme mode "Follow system" with a theme for light and one for dark.
import 'package:commet/config/preferences.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> reset(Map<String, Object> values) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(values);
    await preferences.init();
  }

  test("unset slots keep the old Follow System Brightness pairs", () async {
    await reset({"app_theme": "nordic"});
    expect(preferences.lightThemeId, "nordic-polar");
    expect(preferences.darkThemeId, "nordic");

    await reset({"app_theme": "amoled"});
    expect(preferences.lightThemeId, "light");
    expect(preferences.darkThemeId, "amoled");

    await reset({"app_theme": "light"});
    expect(preferences.lightThemeId, "light");
    expect(preferences.darkThemeId, "dark");
  });

  test("a gradient or custom theme fills both unset slots, as before",
      () async {
    await reset({"app_theme": "gradient:aurora"});
    expect(preferences.lightThemeId, "gradient:aurora");
    expect(preferences.darkThemeId, "gradient:aurora");

    await reset({"app_theme": "My theme"});
    expect(preferences.lightThemeId, "My theme");
    expect(preferences.darkThemeId, "My theme");
  });

  test("picking a theme fills the selected slot while following", () async {
    await reset({"app_theme": "dark", "should_follow_system_theme": true});
    preferences.themeSlot.value = Brightness.light;
    await preferences.pickTheme("nordic-polar");
    preferences.themeSlot.value = Brightness.dark;
    await preferences.pickTheme("gradient:aurora");

    expect(preferences.theme.value, "dark");
    expect(preferences.resolveThemeId(brightness: Brightness.light),
        "nordic-polar");
    expect(preferences.resolveThemeId(brightness: Brightness.dark),
        "gradient:aurora");
    expect(preferences.pickedThemeId, "gradient:aurora");
  });

  test("with one theme, picking sets it and brightness is ignored", () async {
    await reset({"app_theme": "dark", "app_theme_light": "nordic-polar"});
    await preferences.pickTheme("amoled");
    expect(preferences.theme.value, "amoled");
    expect(preferences.themeLight.value, "nordic-polar");
    expect(preferences.resolveThemeId(brightness: Brightness.light), "amoled");
    expect(preferences.pickedThemeId, "amoled");
  });

  test("isLightTheme knows built-in and gradient brightness", () async {
    expect(Preferences.isLightTheme("light"), isTrue);
    expect(Preferences.isLightTheme("nordic-polar"), isTrue);
    expect(Preferences.isLightTheme("amoled"), isFalse);
    expect(Preferences.isLightTheme("My theme"), isFalse);
    expect(Preferences.isLightTheme("gradient:mint-apple"), isTrue);
  });
}
