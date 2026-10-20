import 'package:commet/config/theme_draft.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_color_picker.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';
import 'package:tiamat/config/style/theme_light.dart';
import 'package:tiamat/config/style/theme_nordic.dart';

void main() {
  test('hex colors round-trip', () {
    expect(colorToHex(const Color(0xff8fbcbb)), "#8fbcbb");
    expect(colorToHex(const Color(0x308fbcbb)), "#308fbcbb");
    expect(colorFromHex("#8FBCBB"), const Color(0xff8fbcbb));
    expect(colorFromHex("308fbcbb"), const Color(0x308fbcbb));
    expect(colorFromHex("#8fbcb"), isNull);
    expect(colorFromHex("nope"), isNull);
  });

  test('every slot survives a trip through theme.json', () async {
    for (var source in [
      ThemeNordic.theme,
      ThemeNordic.polar,
      ThemeDark.theme
    ]) {
      var draft = ThemeDraft.fromTheme(source, "t");
      draft.colors["primary"] = const Color(0xffff8800);
      draft.colors[ThemeSlot.foundationKey] = const Color(0xff101418);

      var built = await ThemeJsonConverter.fromJson(draft.toJson(), null);
      expect(built, isNotNull);
      expect(built!.brightness, source.brightness);
      for (var slot in ThemeSlot.all) {
        expect(ThemeSlot.read(built, slot.key), draft.colors[slot.key],
            reason: slot.key);
      }
    }
  });

  test('Raised paints selected rows (Vommet issue 417)', () async {
    var draft = ThemeDraft.fromTheme(ThemeDark.theme, "t");
    draft.colors["surfaceContainerHigh"] = const Color(0xff123456);
    var built = await ThemeJsonConverter.fromJson(draft.toJson(), null);
    expect(built!.colorScheme.secondaryContainer, const Color(0xff123456));
  });

  test('editing keeps keys the editor does not own', () {
    var draft = ThemeDraft.fromTheme(ThemeLight.theme, "t", raw: {
      "base": "dark",
      "shadows": [
        {"color": "#000000", "blurRadius": 4}
      ],
      "foundation": {
        "image": {"file": "bg.png"}
      },
      "colorScheme": {"seed": "#ff0000", "inversePrimary": "#123456"},
    })
      // The image is the theme's own background, so it stays.
      ..background = ThemeBackground.image
      ..imageFile = "bg.png";
    var json = draft.toJson();
    expect(json["base"], "light");
    expect(json["shadows"], [
      {"color": "#000000", "blurRadius": 4}
    ]);
    expect((json["foundation"] as Map)["image"],
        {"file": "bg.png", "fit": "cover"});
    var scheme = json["colorScheme"] as Map;
    expect(scheme.containsKey("seed"), isFalse);
    expect(scheme["inversePrimary"], "#123456");
  });

  test('theme names are safe folder names', () {
    expect(ThemeDraft.safeName("  Nordic / mine?  "), "Nordic  mine");
    expect(ThemeDraft.safeName("../.."), "My theme");
    expect(ThemeDraft.safeName(""), "My theme");
  });

  testWidgets('picker reports hex input and swatch taps', (tester) async {
    var picked = <Color>[];
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: SizedBox(
          width: 320,
          child: ThemeColorPicker(
            initial: NordColors.nord7,
            palette: const [NordColors.nord11],
            onChanged: picked.add,
          ),
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), "#5e81ac");
    expect(picked.last, NordColors.nord10);

    await tester.tap(find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color == NordColors.nord11 &&
        w.constraints?.maxWidth == 24));
    expect(picked.last, NordColors.nord11);
  });

  testWidgets('live preview draws in both widths', (tester) async {
    for (var compact in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: compact ? 380 : 700,
            height: compact ? 220 : 420,
            child: ThemeLivePreview(theme: ThemeNordic.theme, compact: compact),
          ),
        ),
      ));
      expect(find.text("general"), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });
}
