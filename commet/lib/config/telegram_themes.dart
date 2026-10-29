import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/config/config.dart';
import 'package:tiamat/config/style/theme_base.dart';

/// Vommet: one accent circle of a Telegram theme. Android accents also
/// recolor your own bubbles and the chat background, as Telegram does.
class TelegramAccent {
  const TelegramAccent(this.color,
      {this.ownBubble, this.wallpaper, this.intensity});

  final int color;
  final int? ownBubble;
  final List<int>? wallpaper;

  /// Pattern strength in percent.
  final int? intensity;
}

/// Vommet: a Telegram built-in theme, its colors mapped to the theme
/// editor's slots (see [ThemeSlot]). Colors and accents come from Telegram
/// Desktop (GPLv3+) and Telegram for Android (GPLv2+); credited on the
/// licenses page.
class TelegramTheme {
  const TelegramTheme(
      {required this.slug,
      required this.name,
      required this.android,
      required this.dark,
      required this.colors,
      required this.wallpaper,
      this.intensity = 50,
      required this.accents});

  final String slug;
  final String name;
  final bool android;
  final bool dark;

  /// Slot key → ARGB. surfaceContainerHigh/Highest are derived when absent.
  final Map<String, int> colors;

  /// Behind the messages: one color or a gradient.
  final List<int> wallpaper;

  /// Pattern strength in percent.
  final int intensity;

  /// Circle 0 (the theme as it ships) is not in this list.
  final List<TelegramAccent> accents;

  String get id => "${TelegramThemes.prefix}$slug";
  Brightness get brightness => dark ? Brightness.dark : Brightness.light;
  Color get accent => Color(colors["primary"]!);
}

/// A picked Telegram theme: the theme plus an accent circle (index into
/// [TelegramTheme.accents]) or a custom accent color.
class TelegramPick {
  const TelegramPick(this.theme, {this.accent, this.custom});

  final TelegramTheme theme;
  final int? accent;
  final Color? custom;

  String get id {
    if (custom != null) {
      var hex = (custom!.toARGB32() & 0xffffff).toRadixString(16);
      return "${theme.id}:#${hex.padLeft(6, "0")}";
    }
    if (accent != null) return "${theme.id}:$accent";
    return theme.id;
  }
}

class TelegramThemes {
  /// Theme ids: `telegram-<slug>`, with `:<accent index>` or `:#rrggbb`
  /// for an accent. Custom theme names can't contain ":".
  static const prefix = "telegram-";

  static bool isTelegram(String id) => id.startsWith(prefix);

  static const desktop = [classic, day, tinted, night];
  static const android = [blue, arcticBlue, darkBlue, androidNight];
  static const all = [...desktop, ...android];

  static TelegramPick? parse(String id) {
    if (!isTelegram(id)) return null;
    var parts = id.substring(prefix.length).split(":");
    TelegramTheme? theme;
    for (var t in all) {
      if (t.slug == parts.first) theme = t;
    }
    if (theme == null) return null;
    if (parts.length < 2) return TelegramPick(theme);
    var suffix = parts[1];
    if (suffix.startsWith("#") && suffix.length == 7) {
      var value = int.tryParse(suffix.substring(1), radix: 16);
      if (value != null) {
        return TelegramPick(theme, custom: Color(0xff000000 | value));
      }
    }
    var index = int.tryParse(suffix);
    if (index != null && index >= 0 && index < theme.accents.length) {
      return TelegramPick(theme, accent: index);
    }
    return TelegramPick(theme);
  }

  static TelegramTheme? byId(String id) => parse(id)?.theme;

  /// Credits Telegram's art and theme colors on the licenses page.
  static void registerLicenses() {
    LicenseRegistry.addLicense(() => Stream.fromIterable(const [
          LicenseEntryWithLineBreaks(
              ["Telegram Desktop"],
              "The chat background pattern (assets/images/telegram/pattern.svg.gz) "
              "and the Telegram Desktop theme colors come from Telegram Desktop, "
              "https://github.com/telegramdesktop/tdesktop.\n\n"
              "Copyright (c) The Telegram Desktop Authors.\n\n"
              "Telegram Desktop is free software: you can redistribute it and/or "
              "modify it under the terms of the GNU General Public License as "
              "published by the Free Software Foundation, either version 3 of the "
              "License, or (at your option) any later version. It is "
              "distributed WITHOUT ANY WARRANTY; without even the implied "
              "warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. "
              "In addition, as a special exception, the copyright holders give "
              "permission to link the code of portions of this program with the "
              "OpenSSL library. See https://www.gnu.org/licenses/gpl-3.0.html."),
          LicenseEntryWithLineBreaks(
              ["Telegram for Android"],
              "The Telegram for Android theme colors and accents come from "
              "Telegram for Android, https://github.com/DrKLO/Telegram.\n\n"
              "Copyright Nikolai Kudashov and the Telegram for Android authors.\n\n"
              "Telegram for Android is free software: you can redistribute it "
              "and/or modify it under the terms of the GNU General Public "
              "License as published by the Free Software Foundation, either "
              "version 2 of the License, or (at your option) any later version. "
              "It is distributed WITHOUT ANY WARRANTY. See "
              "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html."),
        ]));
  }

  /// The slot colors of [pick], accent applied, every editor slot filled.
  static Map<String, Color> colorsOf(TelegramPick pick) {
    var theme = pick.theme;
    var colors = {
      for (var e in theme.colors.entries) e.key: Color(e.value),
    };

    Color? accent = pick.custom;
    TelegramAccent? option;
    if (pick.accent != null) {
      option = theme.accents[pick.accent!];
      accent = Color(option.color);
    }
    if (accent != null) {
      colors["primary"] = accent;
      colors["links"] = theme.dark ? _lighten(accent) : _darken(accent);
      colors["selectedRoom"] = accent;
      colors["tertiary"] = accent;
      if (option?.ownBubble case var bubble?) {
        colors["ownBubble"] = Color(bubble);
      } else if (colors["ownBubble"] case var own?) {
        colors["ownBubble"] = _withHueOf(own, accent);
      }
    }

    var surface = colors["surface"]!;
    var onSurface = colors["onSurface"]!;
    colors["surfaceContainerHigh"] ??=
        Color.alphaBlend(onSurface.withValues(alpha: 0.08), surface);
    colors["surfaceContainerHighest"] ??=
        Color.alphaBlend(onSurface.withValues(alpha: 0.12), surface);
    return colors;
  }

  /// What sits behind the messages for [pick].
  static ChatStyle chatStyleOf(TelegramPick pick) {
    var theme = pick.theme;
    var wallpaper = theme.wallpaper;
    var intensity = theme.intensity;
    if (pick.accent != null) {
      var option = theme.accents[pick.accent!];
      if (option.wallpaper case var w?) wallpaper = w;
      if (option.intensity case var i?) intensity = i;
    }
    return ChatStyle(
        colors: [for (var c in wallpaper) Color(c)],
        pattern: ChatStyle.telegramPattern,
        patternStrength: intensity / 100);
  }

  /// The colorScheme entries a saved copy needs on top of the editor's
  /// slots so it looks the same (theme.json keys).
  static Map<String, Color> extraSchemeColors(Map<String, Color> colors) => {
        "primaryContainer": colors["primary"]!,
        "onPrimaryContainer": colors["onPrimary"]!,
      };

  static ThemeData theme(TelegramPick pick) {
    var t = pick.theme;
    var c = colorsOf(pick);
    var base = t.dark ? ThemeDark.theme : ThemeLight.theme;
    var scheme = base.colorScheme.copyWith(
      primary: c["primary"],
      onPrimary: c["onPrimary"],
      primaryContainer: c["primary"],
      onPrimaryContainer: c["onPrimary"],
      surface: c["surface"],
      surfaceContainerLow: c["surfaceContainerLow"],
      surfaceContainerLowest: c["surfaceContainerLowest"],
      surfaceContainer: c["surfaceContainer"],
      surfaceContainerHigh: c["surfaceContainerHigh"],
      surfaceContainerHighest: c["surfaceContainerHighest"],
      secondaryContainer: c["surfaceContainerHigh"],
      surfaceDim: c["foundation"],
      onSurface: c["onSurface"],
      onSurfaceVariant: c["secondary"],
      secondary: c["secondary"],
      tertiary: c["tertiary"],
      error: c["error"],
      outline: c["outline"],
    );
    return ThemeBase.theme(scheme).copyWith(extensions: [
      const ThemeSettings(caulkBorders: false, caulkBorderRadius: 0),
      FoundationSettings(color: c["foundation"]!),
      ExtraColors(
          codeHighlight: c["codeHighlight"]!,
          linkColor: c["links"]!,
          ownBubble: c["ownBubble"],
          otherBubble: c["otherBubble"],
          selectedRoom: c["selectedRoom"]),
      chatStyleOf(pick),
    ]);
  }

  static Color _withHueOf(Color color, Color accent) {
    var hsl = HSLColor.fromColor(color);
    return hsl.withHue(HSLColor.fromColor(accent).hue).toColor();
  }

  static Color _lighten(Color c) {
    var hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + 0.15).clamp(0.0, 0.85)).toColor();
  }

  static Color _darken(Color c) {
    var hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.1).clamp(0.2, 1.0)).toColor();
  }

  static const _desktopLightAccents = [
    TelegramAccent(0xff45bce7),
    TelegramAccent(0xff52b440),
    TelegramAccent(0xffd46c99),
    TelegramAccent(0xffdf8a49),
    TelegramAccent(0xff9978c8),
    TelegramAccent(0xffc55245),
    TelegramAccent(0xff687b98),
    TelegramAccent(0xffdea922),
  ];

  // Telegram Desktop: "Day" (day-blue), "Tinted" (night) and "Night"
  // (night-green); Classic is the default palette.
  static const classic = TelegramTheme(
    slug: "classic",
    name: "Classic",
    android: false,
    dark: false,
    colors: {
      "primary": 0xff40a7e3,
      "onPrimary": 0xffffffff,
      "links": 0xff168acd,
      "surface": 0xffffffff,
      "surfaceContainerLow": 0xffffffff,
      "selectedRoom": 0xff419fd9,
      "surfaceContainerLowest": 0xffffffff,
      "foundation": 0xff293a4c,
      "surfaceContainer": 0xfff1f1f1,
      "surfaceContainerHigh": 0xffe5e5e5,
      "ownBubble": 0xffeffdde,
      "otherBubble": 0xffffffff,
      "onSurface": 0xff000000,
      "secondary": 0xff999999,
      "tertiary": 0xff40a7e3,
      "error": 0xffd14e4e,
      "outline": 0xffe0e0e0,
      "codeHighlight": 0xff4e7391,
    },
    wallpaper: [0xffdbddbb, 0xff6ba587, 0xffd5d88d, 0xff88b884],
    accents: _desktopLightAccents,
  );

  static const day = TelegramTheme(
    slug: "day",
    name: "Day",
    android: false,
    dark: false,
    colors: {
      "primary": 0xff40a7e3,
      "onPrimary": 0xffffffff,
      "links": 0xff168acd,
      "surface": 0xffffffff,
      "surfaceContainerLow": 0xffffffff,
      "selectedRoom": 0xff419fd9,
      "surfaceContainerLowest": 0xffffffff,
      "foundation": 0xff293a4c,
      "surfaceContainer": 0xfff1f1f1,
      "surfaceContainerHigh": 0xffe5e5e5,
      "ownBubble": 0xffdef1fd,
      "otherBubble": 0xffffffff,
      "onSurface": 0xff000000,
      "secondary": 0xff999999,
      "tertiary": 0xff40a7e3,
      "error": 0xffd14e4e,
      "outline": 0xffe0e0e0,
      "codeHighlight": 0xff4e7391,
    },
    wallpaper: [0xff74b4e0],
    accents: _desktopLightAccents,
  );

  static const tinted = TelegramTheme(
    slug: "tinted",
    name: "Tinted",
    android: false,
    dark: true,
    colors: {
      "primary": 0xff2f6ea5,
      "onPrimary": 0xffffffff,
      "links": 0xff70baf5,
      "surface": 0xff17212b,
      "surfaceContainerLow": 0xff17212b,
      "selectedRoom": 0xff2b5278,
      "surfaceContainerLowest": 0xff17212b,
      "foundation": 0xff0e1621,
      "surfaceContainer": 0xff232e3c,
      "surfaceContainerHigh": 0xff24303d,
      "ownBubble": 0xff2b5278,
      "otherBubble": 0xff182533,
      "onSurface": 0xfff5f5f5,
      "secondary": 0xff708499,
      "tertiary": 0xff4082bc,
      "error": 0xffec3942,
      "outline": 0xff313c49,
      "codeHighlight": 0xff5a8cb7,
    },
    wallpaper: [0xff0e1621],
    accents: [
      TelegramAccent(0xff58bfe8),
      TelegramAccent(0xff466f42),
      TelegramAccent(0xffaa6084),
      TelegramAccent(0xffa46d3c),
      TelegramAccent(0xff917bbd),
      TelegramAccent(0xffab5149),
      TelegramAccent(0xff697b97),
      TelegramAccent(0xff9b834b),
    ],
  );

  static const night = TelegramTheme(
    slug: "night",
    name: "Night",
    android: false,
    dark: true,
    colors: {
      "primary": 0xff2da192,
      "onPrimary": 0xffffffff,
      "links": 0xff37e1cb,
      "surface": 0xff282e33,
      "surfaceContainerLow": 0xff282e33,
      "selectedRoom": 0xff009687,
      "surfaceContainerLowest": 0xff282e33,
      "foundation": 0xff18191d,
      "surfaceContainer": 0xff313b43,
      "surfaceContainerHigh": 0xff3f4850,
      "ownBubble": 0xff2a2f33,
      "otherBubble": 0xff33393f,
      "onSurface": 0xfff5f5f5,
      "secondary": 0xff82868a,
      "tertiary": 0xff05a091,
      "error": 0xfff57474,
      "outline": 0xff6f6f6f,
      "codeHighlight": 0xff5aaba0,
    },
    wallpaper: [0xff18191d],
    accents: [
      TelegramAccent(0xff60a8e7),
      TelegramAccent(0xff4e9c57),
      TelegramAccent(0xffca7896),
      TelegramAccent(0xffcc925c),
      TelegramAccent(0xffa58ed2),
      TelegramAccent(0xffd27570),
      TelegramAccent(0xff7b8799),
      TelegramAccent(0xffcbac67),
    ],
  );

  // Telegram for Android: bluebubbles, arctic, darkblue and night .attheme,
  // missing keys from its built-in defaults.
  static const blue = TelegramTheme(
    slug: "blue",
    name: "Blue",
    android: true,
    dark: false,
    colors: {
      "primary": 0xff5890c5,
      "onPrimary": 0xffffffff,
      "links": 0xff0a79bd,
      "surface": 0xffffffff,
      "surfaceContainerLow": 0xffffffff,
      "selectedRoom": 0xff5890c5,
      "surfaceContainerLowest": 0xffffffff,
      "foundation": 0xffffffff,
      "surfaceContainer": 0xfff1f1f3,
      "ownBubble": 0xffe6f2fc,
      "otherBubble": 0xffffffff,
      "onSurface": 0xff1a1d21,
      "secondary": 0xff8c8f91,
      "tertiary": 0xff229af0,
      "error": 0xffcc2929,
      "outline": 0xffd9d9d9,
      "codeHighlight": 0xff0a79bd,
    },
    wallpaper: [0xff9bbce7, 0xffc0d9f3, 0xff95c3eb, 0xffbbd5e8],
    intensity: 35,
    accents: [
      TelegramAccent(0xff239853,
          ownBubble: 0xfffafbcc,
          wallpaper: [0xffdfe2a0, 0xffbad89d, 0xffe2dea7, 0xff9ec790],
          intensity: 52),
      TelegramAccent(0xffce5e82,
          ownBubble: 0xfffff9dc,
          wallpaper: [0xfff1b290, 0xffeccf94, 0xffe7b384, 0xffebdea8],
          intensity: 46),
      TelegramAccent(0xff7f63c3,
          ownBubble: 0xffc14f6e,
          wallpaper: [0xffd7c1e9, 0xffe8bdd6, 0xffd2aee9, 0xffeccb88],
          intensity: 57),
      TelegramAccent(0xff2491ad,
          ownBubble: 0xffd1bd1b,
          wallpaper: [0xffd7b89e, 0xffe6dec2, 0xffdac5ae, 0xffe5dcbf],
          intensity: 45),
      TelegramAccent(0xff299c2f,
          ownBubble: 0xfffffac9,
          wallpaper: [0xffec9e73, 0xffe8d085, 0xffeea677, 0xffede4a9],
          intensity: 64),
      TelegramAccent(0xff8854b4,
          ownBubble: 0xfffcf6d8,
          wallpaper: [0xffcbb0e4, 0xffebc8e9, 0xffdfa8d1, 0xffedc8a8],
          intensity: 52),
      TelegramAccent(0xff43acc7,
          wallpaper: [0xff91c5ec, 0xffbfdfec, 0xffb5e1d9, 0xffbfdbe8],
          intensity: 36),
      TelegramAccent(0xff52ac44,
          wallpaper: [0xff9bc982, 0xffe0dd93, 0xffbed595, 0xffd1db97],
          intensity: 41),
    ],
  );

  static const arcticBlue = TelegramTheme(
    slug: "arctic",
    name: "Arctic Blue",
    android: true,
    dark: false,
    colors: {
      "primary": 0xff50a4f5,
      "onPrimary": 0xffffffff,
      "links": 0xff0183e8,
      "surface": 0xffffffff,
      "surfaceContainerLow": 0xffffffff,
      "selectedRoom": 0xff50a4f5,
      "surfaceContainerLowest": 0xffffffff,
      "foundation": 0xffffffff,
      "surfaceContainer": 0xfff1f1f3,
      "ownBubble": 0xff3490eb,
      "otherBubble": 0xffffffff,
      "onSurface": 0xff333333,
      "secondary": 0xff8b949f,
      "tertiary": 0xff0babff,
      "error": 0xffcc2929,
      "outline": 0xffe6e6e6,
      "codeHighlight": 0xff0183e8,
    },
    wallpaper: [0xffe0e7ed, 0xffbed7f3, 0xffe0e8f3, 0xffc8dbf3],
    intensity: 49,
    accents: [
      TelegramAccent(0xff40b1e2,
          ownBubble: 0xff319fca,
          wallpaper: [0xffc5e2f0, 0xffe8f4f3, 0xffb4daf0, 0xffcff0ef],
          intensity: 50),
      TelegramAccent(0xff41b05d,
          ownBubble: 0xff28a359,
          wallpaper: [0xffdadea9, 0xffbce3ac, 0xffcde7a9, 0xffa8cf9b],
          intensity: 50),
      TelegramAccent(0xffce8c20,
          ownBubble: 0xff8c5a3f,
          wallpaper: [0xffd6c9a5, 0xffe6dbaf, 0xffe8c091, 0xffe1d09f],
          intensity: 58),
      TelegramAccent(0xff57a3eb,
          ownBubble: 0xff3085d3,
          wallpaper: [0xffe3f3f3, 0xffc8e6ee, 0xffd9eff3, 0xffb4d6e8],
          intensity: 47),
      TelegramAccent(0xffde8534,
          ownBubble: 0xffc95870,
          wallpaper: [0xffeee5b0, 0xffeebeaa, 0xffeecf92, 0xffeeaf87],
          intensity: 46),
      TelegramAccent(0xffcc6189,
          ownBubble: 0xff7871cd,
          wallpaper: [0xffe5dfec, 0xffe1c6ec, 0xfff6eaf6, 0xffe5c5cf],
          intensity: 50),
      TelegramAccent(0xff52ac44,
          wallpaper: [0xffc2e0af, 0xffcbe19a, 0xffb8de89, 0xffcee5a2],
          intensity: 51),
    ],
  );

  static const darkBlue = TelegramTheme(
    slug: "darkblue",
    name: "Dark Blue",
    android: true,
    dark: true,
    colors: {
      "primary": 0xff5fa3de,
      "onPrimary": 0xffffffff,
      "links": 0xff79c4fc,
      "surface": 0xff1d2733,
      "surfaceContainerLow": 0xff1d2733,
      "selectedRoom": 0xff2b4766,
      "surfaceContainerLowest": 0xff283848,
      "foundation": 0xff242d39,
      "surfaceContainer": 0xff151e27,
      "ownBubble": 0xff3e618a,
      "otherBubble": 0xff232e3b,
      "onSurface": 0xffffffff,
      "secondary": 0xff7d8b99,
      "tertiary": 0xff64b5ef,
      "error": 0xffee686f,
      "outline": 0xff0c1015,
      "codeHighlight": 0xff79c4fc,
    },
    wallpaper: [0xff151e27],
    accents: [
      TelegramAccent(0xff927bd4,
          ownBubble: 0xff9d5c99,
          wallpaper: [0xff271e2e, 0xff110e13, 0xff2b1e2b, 0xff161227],
          intensity: 40),
      TelegramAccent(0xff698afb,
          ownBubble: 0xff635545,
          wallpaper: [0xff171a22, 0xff26262e, 0xff15151b, 0xff1a1916],
          intensity: 40),
      TelegramAccent(0xff23a7f0,
          ownBubble: 0xff31818b,
          wallpaper: [0xff071e1f, 0xff141d26, 0xff0c151a, 0xff0d272c],
          intensity: 31),
      TelegramAccent(0xff7b71d1,
          ownBubble: 0xffad6426,
          wallpaper: [0xff100f13, 0xff221a27, 0xff0e0f13, 0xff271d29],
          intensity: 50),
      TelegramAccent(0xff69b955,
          ownBubble: 0xff4a7034,
          wallpaper: [0xff0e1811, 0xff1f2818, 0xff0b170f, 0xff171d19],
          intensity: 25),
      TelegramAccent(0xff2990ea,
          ownBubble: 0xff335d82,
          wallpaper: [0xff0b131c, 0xff192330, 0xff131822, 0xff172331],
          intensity: 34),
      TelegramAccent(0xff7082e9,
          ownBubble: 0xff36576f,
          wallpaper: [0xff1d2129, 0xff12161a, 0xff17242d, 0xff111521],
          intensity: 35),
      TelegramAccent(0xff66baed,
          ownBubble: 0xff597563,
          wallpaper: [0xff202c2a, 0xff141a1e, 0xff16202b, 0xff051717],
          intensity: 35),
    ],
  );

  static const androidNight = TelegramTheme(
    slug: "android-night",
    name: "Night",
    android: true,
    dark: true,
    colors: {
      "primary": 0xff5ea0db,
      "onPrimary": 0xffffffff,
      "links": 0xff79c4fc,
      "surface": 0xff181819,
      "surfaceContainerLow": 0xff181819,
      "selectedRoom": 0xff2a3d52,
      "surfaceContainerLowest": 0xff282829,
      "foundation": 0xff232326,
      "surfaceContainer": 0xff000000,
      "ownBubble": 0xff366caf,
      "otherBubble": 0xff1f2123,
      "onSurface": 0xffffffff,
      "secondary": 0xff7c7c7c,
      "tertiary": 0xff399ef3,
      "error": 0xffee686f,
      "outline": 0xff000000,
      "codeHighlight": 0xff79c4fc,
    },
    wallpaper: [0xff0f0f10],
    accents: [
      TelegramAccent(0xff6abe3f,
          ownBubble: 0xff8a5294,
          wallpaper: [0xff16131c, 0xff201827, 0xff0e0b13, 0xff1e192a],
          intensity: 34),
      TelegramAccent(0xff8d78e3,
          ownBubble: 0xffb46c1b,
          wallpaper: [0xff1e1118, 0xff100f13, 0xff211623, 0xff111016],
          intensity: 47),
      TelegramAccent(0xffde5e7e,
          ownBubble: 0xffaf4f6f,
          wallpaper: [0xff0f0b10, 0xff1b151a, 0xff130e12, 0xff21141a],
          intensity: 52),
      TelegramAccent(0xff5977e8,
          ownBubble: 0xff266e8d,
          wallpaper: [0xff090c0c, 0xff141f22, 0xff0d0f11, 0xff111a1b],
          intensity: 48),
      TelegramAccent(0xffdbc11a,
          ownBubble: 0xff744eb7,
          wallpaper: [0xff071519, 0xff0c0c0f, 0xff10191f, 0xff0a0d13],
          intensity: 54),
      TelegramAccent(0xff3e88f7,
          wallpaper: [0xff0d0e17, 0xff090a0c, 0xff181c28, 0xff0e0f12],
          intensity: 50),
      TelegramAccent(0xff4ab5d3,
          wallpaper: [0xff111b1c, 0xff0a0e0e, 0xff142121, 0xff070c0b],
          intensity: 37),
      TelegramAccent(0xffd95576,
          wallpaper: [0xff0e0b0d, 0xff1a1618, 0xff130e11, 0xff22121e],
          intensity: 48),
    ],
  );
}
