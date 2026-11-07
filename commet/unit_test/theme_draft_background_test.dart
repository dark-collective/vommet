import 'package:commet/config/theme_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_gradient.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';

void main() {
  test('gradient angles survive the alignment math', () {
    for (var angle in [0.0, 45.0, 90.0, 135.0, 148.71, 180.0, 270.0]) {
      var preset = GradientPreset("t", "T", Brightness.dark,
          angle: angle,
          midpoint: 0.5,
          colors: const [Colors.black, Colors.white],
          stops: const [0, 1]);
      expect(ThemeDraft.angleOf(preset.gradient), closeTo(angle % 360, 0.01));
    }
  });

  test('a gradient theme opens in the editor looking the same', () async {
    for (var preset in ThemeGradient.presets.take(6)) {
      var source = ThemeGradient.theme(preset);
      var draft = ThemeDraft.fromTheme(source, preset.name);
      expect(draft.background, ThemeBackground.gradient);

      var built = await ThemeJsonConverter.fromJson(draft.toJson(), null);
      var a =
          source.extension<FoundationSettings>()!.gradient as LinearGradient;
      var b =
          built!.extension<FoundationSettings>()!.gradient as LinearGradient;
      expect(b.colors, a.colors, reason: preset.id);
      expect(b.stops, a.stops, reason: preset.id);
      expect((b.begin as Alignment).x, closeTo((a.begin as Alignment).x, 1e-6));
      expect((b.begin as Alignment).y, closeTo((a.begin as Alignment).y, 1e-6));

      var ga = source.extension<GlassSettings>()!;
      var gb = built.extension<GlassSettings>()!;
      expect(gb.surfaceOpacity, ga.surfaceOpacity, reason: preset.id);
      expect(gb.surfaceContainerLowOpacity, ga.surfaceContainerLowOpacity);
      expect(
          gb.surfaceContainerLowestOpacity, ga.surfaceContainerLowestOpacity);
      expect(built.brightness, source.brightness);
    }
  });

  test('solid background drops gradient and image, shape is kept', () async {
    var draft = ThemeDraft.fromTheme(ThemeDark.theme, "t", raw: {
      "foundation": {
        "image": {"file": "bg.png"},
        "gradient": {
          "colors": ["#000000", "#ffffff"]
        }
      }
    });
    draft.background = ThemeBackground.solid;
    draft.cornerRadius = 8;
    draft.spacing = 4;
    draft.borders = false;

    var json = draft.toJson();
    var foundation = json["foundation"] as Map;
    expect(foundation.containsKey("image"), isFalse);
    expect(foundation.containsKey("gradient"), isFalse);
    expect(json.containsKey("glass"), isFalse);

    var built = await ThemeJsonConverter.fromJson(json, null);
    var shape = built!.extension<ThemeSettings>()!;
    expect(shape.caulkBorderRadius, 8);
    expect(shape.caulkPadding, 4);
    expect(shape.caulkBorders, isFalse);
    expect(built.extension<FoundationSettings>()!.gradient, isNull);
  });

  test('a picked image stays a full path until saved', () {
    var draft = ThemeDraft.fromTheme(ThemeDark.theme, "t")
      ..background = ThemeBackground.image
      ..imageFile = "/home/someone/Pictures/lake.jpg";
    expect(draft.imageIsNew, isTrue);
    var image = (draft.toJson()["foundation"] as Map)["image"] as Map;
    expect(image["file"], "lake.jpg");
    expect(draft.toJson().containsKey("glass"), isTrue);
  });
}
