import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// The Nord palette (nordtheme.com, MIT), laid out the way EliverLara's
/// Nordic GTK theme (dark) and Nordic Polar (light) use it.
class NordColors {
  static const Color nord0 = Color(0xff2e3440);
  static const Color nord1 = Color(0xff3b4252);
  static const Color nord2 = Color(0xff434c5e);
  static const Color nord3 = Color(0xff4c566a);
  static const Color nord4 = Color(0xffd8dee9);
  static const Color nord5 = Color(0xffe5e9f0);
  static const Color nord6 = Color(0xffeceff4);
  static const Color nord7 = Color(0xff8fbcbb);
  static const Color nord8 = Color(0xff88c0d0);
  static const Color nord9 = Color(0xff81a1c1);
  static const Color nord10 = Color(0xff5e81ac);
  static const Color nord11 = Color(0xffbf616a);
  static const Color nord12 = Color(0xffd08770);
  static const Color nord13 = Color(0xffebcb8b);
  static const Color nord14 = Color(0xffa3be8c);
  static const Color nord15 = Color(0xffb48ead);

  /// Nordic's window borders and darkest frame.
  static const Color border = Color(0xff232831);

  /// Nordic's insensitive/unfocused text.
  static const Color muted = Color(0xff8e95a4);
}

class ThemeNordic {
  static ThemeData get theme {
    var scheme = ColorScheme.fromSeed(
      seedColor: NordColors.nord1,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
      primary: NordColors.nord7,
      onPrimary: NordColors.nord0,
      primaryContainer: NordColors.nord7,
      onPrimaryContainer: NordColors.nord0,
      secondary: NordColors.muted,
      tertiary: NordColors.nord13,
      tertiaryContainer: NordColors.nord13.withAlpha(20),
      error: NordColors.nord11,
      surface: NordColors.nord1,
      onSurface: NordColors.nord4,
      surfaceDim: NordColors.border,
      surfaceContainerLowest: NordColors.border,
      surfaceContainerLow: NordColors.nord0,
      surfaceContainer: const Color(0xff353b49),
      surfaceContainerHigh: NordColors.nord2,
      surfaceContainerHighest: NordColors.nord3,
      outline: NordColors.border,
    );

    return ThemeBase.theme(scheme).copyWith(extensions: [
      const ThemeSettings(caulkBorders: true, caulkBorderRadius: 1),
      FoundationSettings(color: scheme.surfaceDim),
      const ExtraColors(
          codeHighlight: NordColors.nord15, linkColor: NordColors.nord8),
    ]);
  }

  /// Nordic Polar, the light partner. Frost blue (nord10) is the accent here:
  /// Nordic's teal is too pale to read on snow-white.
  static ThemeData get polar {
    var scheme = ColorScheme.fromSeed(
      seedColor: NordColors.nord6,
      brightness: Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
      primary: NordColors.nord10,
      onPrimary: Colors.white,
      primaryContainer: NordColors.nord10,
      onPrimaryContainer: Colors.white,
      secondary: NordColors.nord3,
      tertiary: const Color(0xffc29a4b),
      tertiaryContainer: NordColors.nord13.withAlpha(40),
      error: NordColors.nord11,
      surface: const Color(0xfff5f7fa),
      onSurface: NordColors.nord0,
      surfaceDim: NordColors.nord4,
      surfaceContainerLowest: NordColors.nord4,
      surfaceContainerLow: NordColors.nord6,
      surfaceContainer: NordColors.nord5,
      surfaceContainerHigh: NordColors.nord5,
      surfaceContainerHighest: NordColors.nord4,
      outline: const Color(0x304c566a),
    );

    return ThemeBase.theme(scheme).copyWith(extensions: [
      const ThemeSettings(),
      FoundationSettings(color: scheme.surfaceDim),
      const ExtraColors(
          codeHighlight: NordColors.nord15, linkColor: NordColors.nord10),
    ]);
  }
}
