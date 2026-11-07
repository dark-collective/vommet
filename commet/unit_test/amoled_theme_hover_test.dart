import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';

// Vommet issue 457: hover overlays must show on AMOLED's pure black.
void main() {
  Color overBlack(Color overlay) => Color.alphaBlend(overlay, Colors.black);

  test("AMOLED hover lifts black to a visible shade", () {
    final theme = ThemeAmoled.theme;
    expect(overBlack(theme.hoverColor), ThemeAmoledColors.surfaceHigh1);

    final overlay = theme.textButtonTheme.style!.overlayColor!;
    expect(overlay.resolve({WidgetState.hovered}), theme.hoverColor);
    expect(overlay.resolve({WidgetState.pressed}), ThemeAmoledColors.pressed);
    expect(overlay.resolve({}), isNull);
  });

  test("AMOLED hover stays fainter than a selected row", () {
    final theme = ThemeAmoled.theme;
    expect(overBlack(theme.hoverColor).computeLuminance(),
        lessThan(theme.colorScheme.secondaryContainer.computeLuminance()));
  });

  test("AMOLED keeps the base text button shape", () {
    expect(ThemeAmoled.theme.textButtonTheme.style!.shape, isNotNull);
  });

  test("dark theme hover is unchanged", () {
    final dark = ThemeDark.theme;
    expect(dark.hoverColor, ThemeData(brightness: Brightness.dark).hoverColor);
    expect(dark.textButtonTheme.style!.overlayColor, isNull);
  });
}
