// Vommet: which icon the app shows (Vommet issue 591). The original
// star-eyed face or the rainbow "V", picked separately for the splash screen
// and for the tray and window icon, and a one-colour tray icon for panels
// where the colour one doesn't fit. Kept beside the feature, not in
// preferences.dart, so this topic doesn't touch a file most topics edit.
import 'package:commet/config/preferences/string_preference.dart';
import 'package:intl/intl.dart';

enum AppIconDesign {
  /// The star-eyed face the app has always had.
  original,

  /// The rainbow "V" with a star.
  v;

  static AppIconDesign parse(String value, AppIconDesign fallback) =>
      values.where((d) => d.name == value).firstOrNull ?? fallback;

  String get label => switch (this) {
        original => appIconDesignOriginal,
        v => appIconDesignV,
      };

  /// The full-colour icon, as an SVG asset.
  String get svgAsset => switch (this) {
        original => "assets/images/app_icon/icon.svg",
        v => "assets/images/app_icon/icon_v.svg",
      };

  /// The one-colour silhouette (black on transparent), as an SVG asset.
  String get monoSvgAsset => switch (this) {
        original => "assets/images/app_icon/icon_mono.svg",
        v => "assets/images/app_icon/icon_v_mono.svg",
      };
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
    defaultValue: AppIconDesign.original.name);

final StringPreference appIconDesignPreference = StringPreference(
    "vommet_app_icon_design",
    defaultValue: AppIconDesign.v.name);

final StringPreference trayIconColoursPreference = StringPreference(
    "vommet_tray_icon_colours",
    defaultValue: TrayIconColours.colour.name);

/// The splash screen's icon.
AppIconDesign get splashIconDesign => AppIconDesign.parse(
    splashIconDesignPreference.value, AppIconDesign.original);

/// The tray and window icon.
AppIconDesign get appIconDesign =>
    AppIconDesign.parse(appIconDesignPreference.value, AppIconDesign.v);

TrayIconColours get trayIconColours =>
    TrayIconColours.parse(trayIconColoursPreference.value);

/// The SVG asset the tray icon is drawn from, or null for the original
/// colour icon, which the tray keeps drawing from its PNG (and, in the
/// Flatpak, from the icon theme).
String? trayIconSvgAsset(AppIconDesign design, TrayIconColours colours) {
  if (colours != TrayIconColours.colour) return design.monoSvgAsset;
  return design == AppIconDesign.original ? null : design.svgAsset;
}

String get appIconSettingsTitle => Intl.message("App icon",
    name: "appIconSettingsTitle",
    desc: "Title of the settings that pick which icon the app shows");

String get appIconSettingsDescription => Intl.message(
    "Pick the icon for the window and tray, and the one on the splash screen while the app starts. Your launcher and app menu keep the original icon.",
    name: "appIconSettingsDescription",
    desc: "Explains the app icon settings in Settings › Appearance");

String get appIconDesignOriginal => Intl.message("Original",
    name: "appIconDesignOriginal",
    desc: "App icon option: the star-eyed face the app has always had");

String get appIconDesignV => Intl.message("Rainbow V",
    name: "appIconDesignV",
    desc: "App icon option: a rainbow-striped letter V with a star");

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
