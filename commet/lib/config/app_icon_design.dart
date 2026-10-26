// Vommet: which icon the app shows (Vommet issue 591). The original
// star-eyed face or the rainbow "V", picked separately for the splash screen
// and for the tray and window icon, and a one-colour tray icon for panels
// where the colour one doesn't fit. Kept beside the feature, not in
// preferences.dart, so this topic doesn't touch a file most topics edit.
//
// Vommet issue 681: also the launcher / app menu icon, one choice that sets
// every place at once, and an uploaded image ("your own") for each place.
import 'dart:io';

import 'package:commet/config/preferences/string_preference.dart';
import 'package:intl/intl.dart';

enum AppIconDesign {
  /// The star-eyed face the app has always had.
  original,

  /// The rainbow "V" with a star.
  v,

  /// An image the user uploaded (Vommet issue 681). Its file is in the
  /// place's [AppIconPlace.customPathPreference]; without one, the place
  /// shows its default.
  custom;

  static AppIconDesign parse(String value, AppIconDesign fallback) =>
      values.where((d) => d.name == value).firstOrNull ?? fallback;

  String get label => switch (this) {
        original => appIconDesignOriginal,
        v => appIconDesignV,
        custom => appIconDesignCustom,
      };

  /// The full-colour icon, as an SVG asset. [custom] has none of its own and
  /// gives the V's.
  String get svgAsset => switch (this) {
        original => "assets/images/app_icon/icon.svg",
        v || custom => "assets/images/app_icon/icon_v.svg",
      };

  /// The one-colour silhouette (black on transparent), as an SVG asset.
  String get monoSvgAsset => switch (this) {
        original => "assets/images/app_icon/icon_mono.svg",
        v || custom => "assets/images/app_icon/icon_v_mono.svg",
      };

  /// The two icons that come with the app.
  static const builtIn = [v, original];
}

/// Where an icon shows (Vommet issue 681).
enum AppIconPlace {
  /// The launcher, home screen and app menu (the macOS Dock).
  launcher,

  /// The window, taskbar and tray icon.
  window,

  /// The logo on the splash screen.
  splash;

  StringPreference get preference => switch (this) {
        launcher => launcherIconDesignPreference,
        window => appIconDesignPreference,
        splash => splashIconDesignPreference,
      };

  StringPreference get customPathPreference => switch (this) {
        launcher => launcherIconCustomPathPreference,
        window => appIconCustomPathPreference,
        splash => splashIconCustomPathPreference,
      };

  /// What the place shows until something else is picked: the V
  /// everywhere.
  AppIconDesign get defaultDesign => AppIconDesign.v;

  /// The picked design; an uploaded image whose file is gone gives the
  /// default.
  AppIconDesign get design {
    final picked = AppIconDesign.parse(preference.value, defaultDesign);
    if (picked == AppIconDesign.custom && customFile == null) {
      return defaultDesign;
    }
    return picked;
  }

  /// The uploaded image, if there is one.
  File? get customFile {
    final path = customPathPreference.value;
    if (path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }
}

/// The design every place in [places] shows, or null when they differ (or
/// one shows an uploaded image).
AppIconDesign? everywhereDesign(Iterable<AppIconPlace> places) {
  AppIconDesign? common;
  for (final place in places) {
    final design = place.design;
    if (design == AppIconDesign.custom) return null;
    if (common != null && common != design) return null;
    common = design;
  }
  return common ?? AppIconPlace.window.defaultDesign;
}

/// How the tray icon is coloured.
enum TrayIconColours {
  /// The icon as it is.
  colour,

  /// A white silhouette, for dark panels.
  white,

  /// A black silhouette, for light panels.
  black;

  static TrayIconColours parse(String value) =>
      values.where((c) => c.name == value).firstOrNull ?? colour;

  String get label => switch (this) {
        colour => trayIconColoursColour,
        white => trayIconColoursWhite,
        black => trayIconColoursBlack,
      };

  /// The silhouette's colour (ARGB), or null for the colour icon.
  int? get argb => switch (this) {
        colour => null,
        white => 0xFFFFFFFF,
        black => 0xFF000000,
      };
}

final StringPreference splashIconDesignPreference = StringPreference(
    "vommet_splash_icon_design",
    defaultValue: AppIconDesign.v.name);

final StringPreference launcherIconDesignPreference = StringPreference(
    "vommet_launcher_icon_design",
    defaultValue: AppIconDesign.v.name);

final StringPreference launcherIconCustomPathPreference =
    StringPreference("vommet_launcher_icon_custom_path", defaultValue: "");

final StringPreference appIconCustomPathPreference =
    StringPreference("vommet_app_icon_custom_path", defaultValue: "");

final StringPreference splashIconCustomPathPreference =
    StringPreference("vommet_splash_icon_custom_path", defaultValue: "");

final StringPreference appIconDesignPreference = StringPreference(
    "vommet_app_icon_design",
    defaultValue: AppIconDesign.v.name);

final StringPreference trayIconColoursPreference = StringPreference(
    "vommet_tray_icon_colours",
    defaultValue: TrayIconColours.colour.name);

/// The splash screen's icon.
AppIconDesign get splashIconDesign => AppIconPlace.splash.design;

/// The tray and window icon.
AppIconDesign get appIconDesign => AppIconPlace.window.design;

/// The launcher and app menu icon.
AppIconDesign get launcherIconDesign => AppIconPlace.launcher.design;

TrayIconColours get trayIconColours =>
    TrayIconColours.parse(trayIconColoursPreference.value);

/// The SVG asset the tray icon is drawn from, or null for the original
/// colour icon, which the tray keeps drawing from its PNG (and, in the
/// Flatpak, from the icon theme), and for an uploaded image.
String? trayIconSvgAsset(AppIconDesign design, TrayIconColours colours) {
  if (design == AppIconDesign.custom) return null;
  if (colours != TrayIconColours.colour) return design.monoSvgAsset;
  return design == AppIconDesign.original ? null : design.svgAsset;
}

String get appIconSettingsTitle => Intl.message("App icon",
    name: "appIconSettingsTitle",
    desc: "Title of the settings that pick which icon the app shows");

String get appIconSettingsDescription => Intl.message(
    "Used everywhere: your launcher and app menu, the window and tray, and the splash screen.",
    name: "appIconSettingsDescription",
    desc: "Explains the app icon settings in Settings › Appearance");

String get appIconDesignOriginal => Intl.message("Original",
    name: "appIconDesignOriginal",
    desc: "App icon option: the star-eyed face the app has always had");

String get appIconDesignV => Intl.message("Rainbow V",
    name: "appIconDesignV",
    desc: "App icon option: a rainbow-striped letter V with a star");

String get appIconSettingsDescriptionNoWindow => Intl.message(
    "Used everywhere: your home screen and app list, and the splash screen.",
    name: "appIconSettingsDescriptionNoWindow",
    desc:
        "Explains the app icon settings in Settings › Appearance on phones, which have no window or tray icon");

/// Vommet issue 697: desktops whose launcher icon can't be picked (the
/// Flatpak, Windows).
String get appIconSettingsDescriptionNoLauncher => Intl.message(
    "Used for the window and tray and the splash screen. Your launcher and app menu keep the standard icon.",
    name: "appIconSettingsDescriptionNoLauncher",
    desc:
        "Explains the app icon settings in Settings › Appearance where the launcher and app menu icon can't be changed (Flatpak, Windows)");

String get appIconDesignCustom => Intl.message("Your own",
    name: "appIconDesignCustom",
    desc: "App icon option: an image the user uploaded");

String get appIconLauncher => Intl.message("Launcher and app menu",
    name: "appIconLauncher",
    desc:
        "Heading of the app icon choice for the icon in the launcher, home screen or app menu");

String get appIconWindowAndTray => Intl.message("Window and tray icon",
    name: "appIconWindowAndTray",
    desc:
        "Heading of the app icon choice for the window, taskbar and tray icon");

String get appIconWindow => Intl.message("Window icon",
    name: "appIconWindow",
    desc:
        "Heading of the app icon choice for the window and taskbar icon, where there is no tray icon");

String get appIconSplash => Intl.message("Splash screen",
    name: "appIconSplash",
    desc:
        "Heading of the app icon choice for the logo shown while the app starts");

String get trayIconColoursTitle => Intl.message("Tray icon colours",
    name: "trayIconColoursTitle",
    desc:
        "Heading of the choice between a colour or a black-and-white tray icon");

String get trayIconColoursColour => Intl.message("Colour",
    name: "trayIconColoursColour",
    desc: "Tray icon colours option: the icon in full colour");

String get trayIconColoursWhite => Intl.message("White",
    name: "trayIconColoursWhite",
    desc: "Tray icon colours option: a white icon, for dark panels");

String get trayIconColoursBlack => Intl.message("Black",
    name: "trayIconColoursBlack",
    desc: "Tray icon colours option: a black icon, for light panels");
