import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// Vommet: the glow behind a banner's title, from Settings › Appearance ›
/// Banner glow: "theme" (the default, [bannerThemeGlow]), "classic" (always
/// the classic blue) or "off". Returns the glow (null for none) and the title
/// colour.
(Color?, Color) bannerGlow(BuildContext context) {
  return switch (preferences.bannerGradient.value) {
    "off" => (null, Colors.white),
    "classic" => (ThemeDarkColors.primary, Colors.white),
    _ => (bannerThemeGlow(Theme.of(context)), Colors.white),
  };
}

/// The glow that goes with [theme]: a gradient theme's own tint, otherwise
/// the theme's primary colour (the classic blue on the default Dark theme).
/// Light colours are darkened so the white title stays readable.
Color bannerThemeGlow(ThemeData theme) {
  final scheme = theme.colorScheme;
  // Gradient themes keep the primary colour of the theme they're built on and
  // put their tint in FoundationSettings.color; the plain themes put one of
  // their surface colours there.
  final foundation = theme.extension<FoundationSettings>()?.color;
  final surfaces = {
    scheme.surface,
    scheme.surfaceDim,
    scheme.surfaceContainerLowest,
  };
  var glow = foundation != null && !surfaces.contains(foundation)
      ? foundation
      : scheme.primary;
  final luminance = glow.computeLuminance();
  if (luminance > 0.3) {
    glow = Color.lerp(
        glow, Colors.black, ((luminance - 0.3) * 1.5).clamp(0, 0.6))!;
  }
  return glow;
}
