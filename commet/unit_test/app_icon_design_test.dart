// Vommet issue 591: the app icon choices (window and tray, splash screen,
// tray icon colours), their defaults and the assets they draw from.
// Vommet issue 681: one choice for everywhere, the launcher, uploaded icons.
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/config/app_icon_design.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/app_icon_settings.dart';
import 'package:commet/utils/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

void main() {
  setUp(() async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("defaults: the V everywhere, colour tray", () {
    expect(splashIconDesign, AppIconDesign.v);
    expect(appIconDesign, AppIconDesign.v);
    expect(launcherIconDesign, AppIconDesign.v);
    expect(trayIconColours, TrayIconColours.colour);
    expect(everywhereDesign(AppIconPlace.values), AppIconDesign.v);
  });

  test("one design everywhere, until the places differ", () async {
    await splashIconDesignPreference.set(AppIconDesign.original.name);
    expect(everywhereDesign(AppIconPlace.values), isNull);
    expect(everywhereDesign([AppIconPlace.splash]), AppIconDesign.original);

    await appIconDesignPreference.set(AppIconDesign.original.name);
    // The launcher still shows its default, the V.
    expect(everywhereDesign(AppIconPlace.values), isNull);

    await launcherIconDesignPreference.set(AppIconDesign.original.name);
    expect(everywhereDesign(AppIconPlace.values), AppIconDesign.original);
    expect(everywhereDesign(const []), AppIconDesign.v);
  });

  test("an uploaded icon counts only while its file exists", () async {
    final dir = Directory.systemTemp.createTempSync("vommet-app-icon-");
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File("${dir.path}/splash.png")..writeAsBytesSync([1, 2, 3]);

    await splashIconDesignPreference.set(AppIconDesign.custom.name);
    expect(splashIconDesign, AppIconDesign.v, reason: "no file set yet");

    await splashIconCustomPathPreference.set(file.path);
    expect(splashIconDesign, AppIconDesign.custom);
    expect(AppIconPlace.splash.customFile?.path, file.path);
    expect(everywhereDesign(AppIconPlace.values), isNull);

    file.deleteSync();
    expect(splashIconDesign, AppIconDesign.v);
    expect(everywhereDesign(AppIconPlace.values), AppIconDesign.v);
  });

  test("uploads are cropped to a centred square PNG of at most 512", () {
    final wide = img.Image(width: 1200, height: 800);
    img.fill(wide, color: img.ColorRgb8(255, 0, 0));
    final out =
        img.decodePng(squareIconPng(Uint8List.fromList(img.encodeJpg(wide))))!;
    expect(out.width, 512);
    expect(out.height, 512);

    final small = img.Image(width: 40, height: 64);
    final smallOut =
        img.decodePng(squareIconPng(Uint8List.fromList(img.encodePng(small))))!;
    expect(smallOut.width, 40);
    expect(smallOut.height, 40);

    expect(() => squareIconPng(Uint8List.fromList([1, 2, 3, 4])),
        throwsFormatException);
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
    expect(
        trayIconSvgAsset(AppIconDesign.custom, TrayIconColours.colour), isNull);
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

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: const Scaffold(body: SingleChildScrollView(child: AppIconPicker())),
    ));
    await tester.pumpAndSettle();
  }

  Finder card(String cards, AppIconDesign design) => find.descendant(
      of: find.byKey(ValueKey("app-icon-cards-$cards")),
      matching: find.byKey(ValueKey("choice-card-$design")));

  testWidgets("one pick changes every place", (tester) async {
    await pumpPicker(tester);
    expect(find.byKey(const ValueKey("app-icon-cards-splash")), findsNothing,
        reason: "the per-place choices start hidden");

    await tester.tap(card("everywhere", AppIconDesign.original));
    await tester.pumpAndSettle();

    expect(splashIconDesign, AppIconDesign.original);
    expect(appIconDesign, AppIconDesign.original);
    expect(everywhereDesign(AppIconPlace.values), AppIconDesign.original);
  });

  testWidgets("picking the splash icon saves only the splash choice",
      (tester) async {
    await pumpPicker(tester);
    await tester
        .ensureVisible(find.byKey(const ValueKey("app-icon-all-options")));
    await tester.tap(find.byKey(const ValueKey("app-icon-all-options")));
    await tester.pumpAndSettle();

    await tester.ensureVisible(card("splash", AppIconDesign.original));
    await tester.tap(card("splash", AppIconDesign.original));
    await tester.pumpAndSettle();

    expect(splashIconDesign, AppIconDesign.original);
    expect(appIconDesign, AppIconDesign.v);
    expect(splashIconDesignPreference.hasStoredValue, isTrue);
    expect(appIconDesignPreference.hasStoredValue, isFalse);
    expect(launcherIconDesignPreference.hasStoredValue, isFalse);
    expect(find.text(appIconMixed), findsOneWidget);
  });
}
