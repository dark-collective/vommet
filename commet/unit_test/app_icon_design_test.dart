// Vommet issue 591: the app icon choices (window and tray, splash screen,
// tray icon colours), their defaults and the assets they draw from.
import 'dart:io';

import 'package:commet/config/app_icon_design.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/app_icon_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

void main() {
  setUp(() async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("defaults: original splash, colour V window and tray icon", () {
    expect(splashIconDesign, AppIconDesign.original);
    expect(appIconDesign, AppIconDesign.v);
    expect(trayIconColours, TrayIconColours.colour);
  });

  test("unknown stored values fall back", () {
    expect(AppIconDesign.parse("nonsense", AppIconDesign.v), AppIconDesign.v);
    expect(AppIconDesign.parse("original", AppIconDesign.v),
        AppIconDesign.original);
    expect(TrayIconColours.parse("nonsense"), TrayIconColours.colour);
    expect(TrayIconColours.parse("black"), TrayIconColours.black);
  });

  test(
      "the tray draws the original colour icon from its PNG, the rest from SVG",
      () {
    expect(trayIconSvgAsset(AppIconDesign.original, TrayIconColours.colour),
        isNull);
    expect(trayIconSvgAsset(AppIconDesign.v, TrayIconColours.colour),
        AppIconDesign.v.svgAsset);
    expect(trayIconSvgAsset(AppIconDesign.original, TrayIconColours.white),
        AppIconDesign.original.monoSvgAsset);
    expect(trayIconSvgAsset(AppIconDesign.v, TrayIconColours.black),
        AppIconDesign.v.monoSvgAsset);
    expect(TrayIconColours.colour.argb, isNull);
    expect(TrayIconColours.white.argb, 0xFFFFFFFF);
    expect(TrayIconColours.black.argb, 0xFF000000);
  });

  test("every icon asset exists", () {
    for (final d in AppIconDesign.values) {
      expect(File(d.svgAsset).existsSync(), isTrue, reason: d.svgAsset);
      expect(File(d.monoSvgAsset).existsSync(), isTrue, reason: d.monoSvgAsset);
    }
  });

  testWidgets("picking the splash icon saves only the splash choice",
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: const Scaffold(body: SingleChildScrollView(child: AppIconPicker())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey("app-icon-cards-splash")),
        matching: find.byKey(ValueKey("choice-card-${AppIconDesign.v}"))));
    await tester.pumpAndSettle();

    expect(splashIconDesign, AppIconDesign.v);
    expect(appIconDesign, AppIconDesign.v);
    expect(splashIconDesignPreference.hasStoredValue, isTrue);
    expect(appIconDesignPreference.hasStoredValue, isFalse);
  });
}
