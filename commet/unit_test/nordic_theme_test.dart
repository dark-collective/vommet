import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_preview_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_gradient.dart';
import 'package:tiamat/config/style/theme_nordic.dart';

double _luminance(Color c) => c.computeLuminance();

double _contrast(Color a, Color b) {
  var la = _luminance(a), lb = _luminance(b);
  var hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('Nordic is dark and uses the Nord palette', () {
    var theme = ThemeNordic.theme;
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, NordColors.nord7);
    expect(theme.colorScheme.surface, NordColors.nord1);
    expect(theme.colorScheme.onSurface, NordColors.nord4);
    expect(theme.extension<ExtraColors>()?.linkColor, NordColors.nord8);
  });

  test('Nordic Polar is the light partner', () {
    var theme = ThemeNordic.polar;
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.onSurface, NordColors.nord0);
  });

  test('text stays readable on both Nordic themes', () {
    for (var theme in [ThemeNordic.theme, ThemeNordic.polar]) {
      var s = theme.colorScheme;
      expect(_contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(s.onSurface, s.surfaceContainerLow),
          greaterThanOrEqualTo(4.5));
    }
    // The accent carries button text and links on Polar's light panels.
    var polar = ThemeNordic.polar.colorScheme;
    expect(_contrast(polar.onPrimary, polar.primary), greaterThanOrEqualTo(3));
  });

  testWidgets('theme cards draw solid and gradient themes', (tester) async {
    var gradient = ThemeGradient.theme(ThemeGradient.presets.first);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Wrap(children: [
          ThemePreviewCard(theme: ThemeNordic.theme, name: "Nordic"),
          ThemePreviewCard(
              theme: ThemeNordic.polar, name: "Nordic Polar", selected: true),
          ThemePreviewCard(theme: gradient, name: "Gradient"),
        ]),
      ),
    ));

    expect(find.text("Nordic"), findsOneWidget);
    expect(find.text("Nordic Polar"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
