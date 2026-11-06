import 'dart:typed_data';

import 'package:commet/config/app_font.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/app_font_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_changer.dart';
import 'package:tiamat/config/style/theme_dark.dart';

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("the default keeps the theme's own fonts", () {
    final theme = ThemeDark.theme;
    expect(identical(AppFont.apply(theme), theme), isTrue);
  });

  test("a bundled font replaces every text style's family", () async {
    await preferences.appFont.set("lexend");
    final theme = AppFont.apply(ThemeDark.theme);
    expect(theme.textTheme.bodyMedium!.fontFamily, "Lexend");
    expect(theme.textTheme.headlineLarge!.fontFamily, "Lexend");
    expect(
        theme.textTheme.bodyMedium!.fontFamilyFallback, contains("EmojiFont"));
  });

  test("the system font and a missing file", () async {
    await preferences.appFont.set(AppFont.system);
    expect(AppFont.currentFamily, AppFont.systemFamily);

    await preferences.appFont.set(AppFont.file);
    expect(AppFont.currentFamily, isNull);
  });

  test("only font files pass the check", () {
    expect(AppFont.looksLikeFont(Uint8List.fromList([0, 1, 0, 0, 9])), isTrue);
    expect(AppFont.looksLikeFont(Uint8List.fromList("OTTO".codeUnits)), isTrue);
    expect(AppFont.looksLikeFont(Uint8List.fromList("PK\x03\x04".codeUnits)),
        isFalse);
    expect(AppFont.looksLikeFont(Uint8List(2)), isFalse);
  });

  testWidgets("picking a font applies at once", (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ThemeChanger(
      themeFilter: AppFont.apply,
      shouldFollowSystemTheme: () => false,
      getDarkTheme: () async => ThemeDark.theme,
      getLightTheme: () async => ThemeDark.theme,
      initialTheme: ThemeDark.theme,
      materialAppBuilder: (context, theme) => MaterialApp(
          theme: theme,
          home: const Scaffold(
              body: SingleChildScrollView(child: AppFontSettings()))),
    ));

    String? bodyFamily() =>
        Theme.of(tester.element(find.byType(AppFontSettings)))
            .textTheme
            .bodyMedium!
            .fontFamily;
    expect(bodyFamily(), "RobotoCustom");

    await tester.tap(find.text("Atkinson Hyperlegible"));
    await tester.pumpAndSettle();
    expect(preferences.appFont.value, "atkinson");
    expect(bodyFamily(), "AtkinsonHyperlegible");

    await tester.tap(find.text("Default"));
    await tester.pumpAndSettle();
    expect(bodyFamily(), "RobotoCustom");
  });
}
