import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_gradient.dart';

void main() {
  test('preset ids are unique and resolve with or without the prefix', () {
    var ids = ThemeGradient.presets.map((p) => p.id).toSet();
    expect(ids.length, ThemeGradient.presets.length);

    for (var preset in ThemeGradient.presets) {
      expect(ThemeGradient.byId(preset.id), same(preset));
      expect(
          ThemeGradient.byId(ThemeGradient.prefix + preset.id), same(preset));
    }

    expect(ThemeGradient.byId('gradient:nope'), isNull);
  });

  test('every preset has matching, ordered stops', () {
    for (var preset in ThemeGradient.presets) {
      expect(preset.colors.length, preset.stops.length, reason: preset.id);
      expect(preset.colors.length, greaterThanOrEqualTo(2), reason: preset.id);
      for (var i = 1; i < preset.stops.length; i++) {
        expect(preset.stops[i], greaterThanOrEqualTo(preset.stops[i - 1]),
            reason: preset.id);
      }
    }
  });

  test('sample clamps to the ends and interpolates between stops', () {
    const preset = GradientPreset('t', 'T', Brightness.dark,
        angle: 180,
        midpoint: 0.5,
        colors: [Color(0xff000000), Color(0xffffffff)],
        stops: [0.25, 0.75]);

    expect(preset.sample(0), const Color(0xff000000));
    expect(preset.sample(1), const Color(0xffffffff));
    expect(preset.tint.r, closeTo(0.5, 0.01));
  });

  test('css angles map to gradient directions', () {
    GradientPreset at(double angle) => GradientPreset('t', 'T', Brightness.dark,
        angle: angle,
        midpoint: 0.5,
        colors: const [Colors.black, Colors.white],
        stops: const [0, 1]);

    var down = at(180).gradient;
    expect(down.begin.resolve(TextDirection.ltr).y, closeTo(-1, 1e-9));
    expect(down.end.resolve(TextDirection.ltr).y, closeTo(1, 1e-9));

    var right = at(90).gradient;
    expect(right.end.resolve(TextDirection.ltr).x, closeTo(1, 1e-9));

    // 45deg runs from the bottom-left corner to the top-right one (stretched).
    var diagonal = at(45).gradient.end.resolve(TextDirection.ltr);
    expect(diagonal.x, greaterThan(0));
    expect(diagonal.y, lessThan(0));
  });

  test('themes build with the gradient foundation and glass panels', () {
    for (var preset in ThemeGradient.presets) {
      var theme = ThemeGradient.theme(preset);
      expect(theme.brightness, preset.brightness, reason: preset.id);
      expect(theme.extension<FoundationSettings>()?.gradient, isNotNull);
      expect(theme.extension<GlassSettings>(), isNotNull);
    }
  });
}
