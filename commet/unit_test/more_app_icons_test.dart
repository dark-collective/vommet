// Vommet (more app icons): the recolored V's. Each is a choice everywhere,
// has its SVG, Android launcher entry and drawables, and iOS keeps to the
// two icons in its asset catalog.
import 'dart:io';

import 'package:commet/config/app_icon_design.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/app_icon_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

const _recolored = [
  AppIconDesign.midnight,
  AppIconDesign.grayscale,
  AppIconDesign.sunset,
  AppIconDesign.pastel,
];

void main() {
  setUp(() async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("the recolored V's come with the app, not on iOS", () {
    for (final d in _recolored) {
      expect(AppIconDesign.builtIn, contains(d));
      expect(AppIconDesign.builtInIos, isNot(contains(d)));
      expect(d.isV, isTrue);
      expect(AppIconDesign.parse(d.name, AppIconDesign.original), d);
      expect(d.monoSvgAsset, AppIconDesign.v.monoSvgAsset);
      expect(d.svgAsset, isNot(AppIconDesign.v.svgAsset));
    }
    expect(AppIconDesign.original.isV, isFalse);
    expect(AppIconDesign.custom.isV, isFalse);
    expect(AppIconDesign.builtIn.first, AppIconDesign.v,
        reason: "the default stays first");
  });

  test("each recolored V is the V's shapes in new colors", () {
    final shapes = RegExp(r'd="([^"]+)"');
    final v = File(AppIconDesign.v.svgAsset).readAsStringSync();
    for (final d in _recolored) {
      final svg = File(d.svgAsset).readAsStringSync();
      expect(shapes.allMatches(svg).map((m) => m[1]).toList(),
          shapes.allMatches(v).map((m) => m[1]).toList(),
          reason: d.name);
      expect(svg, isNot(contains("#2B1B6B")), reason: d.name);
    }
  });

  test("Android has a launcher entry and drawables for every built-in icon",
      () {
    const res = "android/app/src/main/res";
    final manifest =
        File("android/app/src/main/AndroidManifest.xml").readAsStringSync();
    final kotlin =
        File("android/app/src/main/kotlin/im/nether/chat/LauncherIcon.kt")
            .readAsStringSync();
    final colors =
        File("$res/values/vommet_launcher_icons.xml").readAsStringSync();
    for (final d in _recolored) {
      final alias = "LauncherV${d.name[0].toUpperCase()}${d.name.substring(1)}";
      expect(manifest, contains('android:name=".$alias"'), reason: d.name);
      expect(manifest, contains("@drawable/ic_launcher_v_${d.name}\""));
      expect(kotlin, contains('"${d.name}" to Pair("im.nether.chat.$alias"'));
      expect(colors, contains("ic_launcher_v_${d.name}_background"));
      for (final f in [
        "drawable/ic_launcher_v_${d.name}.xml",
        "drawable/ic_launcher_v_${d.name}_foreground.xml",
        "drawable-anydpi-v26/ic_launcher_v_${d.name}.xml",
      ]) {
        expect(File("$res/$f").existsSync(), isTrue, reason: f);
      }
    }
  });

  testWidgets("a recolored V can be picked for every place", (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: const Scaffold(body: SingleChildScrollView(child: AppIconPicker())),
    ));
    await tester.pumpAndSettle();
    final sunset = find.descendant(
        of: find.byKey(const ValueKey("app-icon-cards-everywhere")),
        matching: find.byKey(ValueKey("choice-card-${AppIconDesign.sunset}")));
    expect(find.text(appIconDesignSunset), findsOneWidget);
    await tester.ensureVisible(sunset);
    await tester.tap(sunset);
    await tester.pumpAndSettle();

    expect(splashIconDesign, AppIconDesign.sunset);
    expect(appIconDesign, AppIconDesign.sunset);
    expect(everywhereDesign(AppIconPlace.values), AppIconDesign.sunset);
    expect(find.text(appIconSunsetDescription), findsOneWidget);
  });
}
