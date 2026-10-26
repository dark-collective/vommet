import 'dart:io';

import 'package:commet/config/app_icon_design.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:commet/utils/app_icon.dart';
import 'package:commet/utils/launcher_icon.dart';
import 'package:commet/utils/tray/app_tray.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart' hide Text, TextButton;

/// Vommet: Settings › Appearance › App icon (Vommet issue 591).
class AppIconSettings extends StatelessWidget {
  const AppIconSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSearchTarget(
      ids: [
        appIconDesignPreference.key,
        splashIconDesignPreference.key,
        launcherIconDesignPreference.key,
        trayIconColoursPreference.key,
        appIconSettingsTitle
      ],
      child: Panel(
        header: appIconSettingsTitle,
        mode: TileType.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              tiamat.Text.labelLow(!AppIcon.windowIconSupported
                  ? appIconSettingsDescriptionNoWindow
                  : LauncherIcon.isSupported
                      ? appIconSettingsDescription
                      : appIconSettingsDescriptionNoLauncher),
              const AppIconPicker(),
            ],
          ),
        ),
      ),
    );
  }
}

String get appIconOriginalDescription =>
    Intl.message("The star-eyed face Vommet has always had.",
        name: "appIconOriginalDescription",
        desc: "Describes the original app icon option");

String get appIconVDescription =>
    Intl.message("A rainbow V with a star, easier to make out when small.",
        name: "appIconVDescription",
        desc: "Describes the rainbow V app icon option");

String get trayIconColourDescription => Intl.message("As in the app.",
    name: "trayIconColourDescription",
    desc: "Describes the full-colour tray icon option");

String get trayIconWhiteDescription => Intl.message("For dark panels.",
    name: "trayIconWhiteDescription",
    desc: "Describes the white tray icon option");

String get trayIconBlackDescription => Intl.message("For light panels.",
    name: "trayIconBlackDescription",
    desc: "Describes the black tray icon option");

String get appIconShowAllOptions => Intl.message("Show all options",
    name: "appIconShowAllOptions",
    desc: "Button that shows the app icon choice for each place separately");

String get appIconHideAllOptions => Intl.message("Hide all options",
    name: "appIconHideAllOptions",
    desc: "Button that hides the app icon choices for each place again");

String get appIconAllOptionsHint => Intl.message(
    "You can also pick a different icon for each place, or upload your own.",
    name: "appIconAllOptionsHint",
    desc: "Under the app icon choice, says what Show all options offers");

String get appIconMixed => Intl.message(
    "Mixed: you picked different icons below. Pick one above to use it everywhere again.",
    name: "appIconMixed",
    desc:
        "Shown when the app icon differs between places (launcher, window, splash screen)");

String get appIconUploadDescription => Intl.message("Upload an image.",
    name: "appIconUploadDescription",
    desc: "Describes the app icon option for an image the user uploads");

String get appIconCustomDescription => Intl.message("The image you uploaded.",
    name: "appIconCustomDescription",
    desc: "Describes the app icon option once the user uploaded an image");

String get appIconChangeUpload => Intl.message("Change",
    name: "appIconChangeUpload",
    desc: "Button that replaces the image the user uploaded as an app icon");

String get appIconRemoveUpload => Intl.message("Remove",
    name: "appIconRemoveUpload",
    desc: "Button that removes the image the user uploaded as an app icon");

String get appIconUploadFailed =>
    Intl.message("That file isn't an image Vommet can use.",
        name: "appIconUploadFailed",
        desc: "Shown when the file picked as an app icon can't be read");

String get appIconLauncherNoteAndroid => Intl.message(
    "Your home screen can take a few seconds to update. On some phones the home screen shortcut goes away; add it again from the app list.",
    name: "appIconLauncherNoteAndroid",
    desc: "What to expect when the launcher icon changes on Android");

String get appIconLauncherNoteIos => Intl.message(
    "Your iPhone or iPad shows a short message when the icon changes.",
    name: "appIconLauncherNoteIos",
    desc: "What to expect when the home screen icon changes on iOS");

String get appIconLauncherNoteMac => Intl.message(
    "Shows in the Dock while Vommet is open.",
    name: "appIconLauncherNoteMac",
    desc:
        "On macOS the launcher icon choice only changes the Dock icon while the app runs");

String get appIconLauncherNoteLinux => Intl.message(
    "Your app menu shows the new icon once it refreshes. On some desktops that only happens after you sign out and back in.",
    name: "appIconLauncherNoteLinux",
    desc: "What to expect when the app menu icon changes on Linux");

/// The icon choices that apply on this platform; picking one saves it.
/// Also the onboarding page's content.
///
/// Vommet issue 681: one choice for every place first; "Show all options"
/// opens a choice per place, each of which can also take an uploaded image.
class AppIconPicker extends StatefulWidget {
  const AppIconPicker({super.key});

  @override
  State<AppIconPicker> createState() => _AppIconPickerState();
}

class _AppIconPickerState extends State<AppIconPicker> {
  /// Opens with the per-place choices shown when they differ.
  late bool _expanded = everywhereDesign(_places) == null;

  static List<AppIconPlace> get _places => [
        if (LauncherIcon.isSupported) AppIconPlace.launcher,
        if (AppIcon.windowIconSupported) AppIconPlace.window,
        AppIconPlace.splash,
      ];

  Future<void> _set(StringPreference preference, String value) async {
    await preference.set(value);
    if (mounted) setState(() {});
  }

  Future<void> _pick(AppIconPlace place, AppIconDesign design) async {
    await place.preference.set(design.name);
    if (place == AppIconPlace.launcher) await LauncherIcon.apply();
    if (mounted) setState(() {});
  }

  Future<void> _pickEverywhere(AppIconDesign? design) async {
    if (design == null) return;
    for (final place in _places) {
      await place.preference.set(design.name);
    }
    await LauncherIcon.apply();
    if (mounted) setState(() {});
  }

  Future<void> _upload(AppIconPlace place) async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: false, withData: true);
    final picked = result?.files.singleOrNull;
    if (picked == null) return;
    try {
      final bytes = picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) return;
      await AppIcon.setCustomIcon(place, bytes);
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(appIconUploadFailed)));
      }
      return;
    }
    if (place == AppIconPlace.launcher) await LauncherIcon.apply();
    if (mounted) setState(() {});
  }

  Future<void> _removeUpload(AppIconPlace place) async {
    await AppIcon.removeCustomIcon(place);
    if (place == AppIconPlace.launcher) await LauncherIcon.apply();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final places = _places;
    final everywhere = everywhereDesign(places);
    final tray = AppTray.isSupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        ChoiceCards<AppIconDesign?>(
          key: const ValueKey("app-icon-cards-everywhere"),
          selected: everywhere,
          onSelected: _pickEverywhere,
          options: [
            for (final d in AppIconDesign.builtIn)
              _builtInOption<AppIconDesign?>(d)
          ],
        ),
        if (everywhere == null)
          Row(
            spacing: 8,
            children: [
              Icon(Icons.info_outline,
                  size: 18, color: Theme.of(context).colorScheme.tertiary),
              Expanded(child: tiamat.Text.labelLow(appIconMixed)),
            ],
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey("app-icon-all-options"),
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            label:
                Text(_expanded ? appIconHideAllOptions : appIconShowAllOptions),
          ),
        ),
        if (!_expanded) tiamat.Text.labelLow(appIconAllOptionsHint),
        if (_expanded) ...[
          const Divider(),
          for (final place in places) ...[
            const SizedBox(height: 4),
            tiamat.Text.labelEmphasised(switch (place) {
              AppIconPlace.launcher => appIconLauncher,
              AppIconPlace.window =>
                tray ? appIconWindowAndTray : appIconWindow,
              AppIconPlace.splash => appIconSplash,
            }),
            _placeCards(place),
            if (place == AppIconPlace.launcher && _launcherNote != null)
              tiamat.Text.labelLow(_launcherNote!),
            if (place == AppIconPlace.window && tray) ...[
              const SizedBox(height: 4),
              tiamat.Text.labelEmphasised(trayIconColoursTitle),
              _trayColourCards(),
            ],
          ],
        ],
      ],
    );
  }

  /// What to expect when the launcher icon changes here.
  String? get _launcherNote {
    if (PlatformUtils.isAndroid) return appIconLauncherNoteAndroid;
    if (PlatformUtils.isIOS) return appIconLauncherNoteIos;
    if (PlatformUtils.isLinux) return appIconLauncherNoteLinux;
    if (!PlatformUtils.isWeb && Platform.isMacOS) {
      return appIconLauncherNoteMac;
    }
    return null;
  }

  ChoiceCardOption<T> _builtInOption<T extends AppIconDesign?>(
          AppIconDesign d) =>
      ChoiceCardOption<T>(
        value: d as T,
        title: d.label,
        description: d == AppIconDesign.original
            ? appIconOriginalDescription
            : appIconVDescription,
        preview: Center(
          child: SvgPicture.asset(d.svgAsset, width: 56, height: 56),
        ),
      );

  Widget _placeCards(AppIconPlace place) {
    // The web app has no files of its own to keep an upload in.
    final canUpload = !PlatformUtils.isWeb &&
        (place != AppIconPlace.launcher || LauncherIcon.customSupported);
    final file = place.customFile;
    return ChoiceCards<AppIconDesign>(
      key: ValueKey("app-icon-cards-${place.name}"),
      selected: place.design,
      onSelected: (d) => d == AppIconDesign.custom && file == null
          ? _upload(place)
          : _pick(place, d),
      options: [
        for (final d in AppIconDesign.builtIn) _builtInOption<AppIconDesign>(d),
        if (canUpload)
          ChoiceCardOption(
            value: AppIconDesign.custom,
            title: appIconDesignCustom,
            description: file == null
                ? appIconUploadDescription
                : appIconCustomDescription,
            preview: Center(
              child: file == null
                  ? Icon(Icons.add_photo_alternate_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(file, width: 56, height: 56),
                    ),
            ),
            extra: file == null
                ? null
                : Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                          onPressed: () => _upload(place),
                          child: Text(appIconChangeUpload)),
                      TextButton(
                          onPressed: () => _removeUpload(place),
                          child: Text(appIconRemoveUpload)),
                    ],
                  ),
          ),
      ],
    );
  }

  Widget _trayColourCards() {
    final design = appIconDesign;
    return ChoiceCards<TrayIconColours>(
      selected: trayIconColours,
      onSelected: (c) => _set(trayIconColoursPreference, c.name),
      options: [
        for (final c in TrayIconColours.values)
          ChoiceCardOption(
            value: c,
            title: c.label,
            description: switch (c) {
              TrayIconColours.colour => trayIconColourDescription,
              TrayIconColours.white => trayIconWhiteDescription,
              TrayIconColours.black => trayIconBlackDescription,
            },
            preview: TrayIconPreview(design: design, colours: c),
          ),
      ],
    );
  }
}

/// The tray icon at tray sizes on a strip coloured like a panel it suits.
class TrayIconPreview extends StatelessWidget {
  const TrayIconPreview(
      {required this.design, required this.colours, super.key});

  final AppIconDesign design;
  final TrayIconColours colours;

  @override
  Widget build(BuildContext context) {
    final argb = colours.argb;
    final panel = switch (colours) {
      TrayIconColours.colour => const Color(0xFF3A3A44),
      TrayIconColours.white => const Color(0xFF1E1E24),
      TrayIconColours.black => const Color(0xFFE8E8EC),
    };
    final file =
        design == AppIconDesign.custom ? AppIconPlace.window.customFile : null;
    final filter =
        argb == null ? null : ColorFilter.mode(Color(argb), BlendMode.srcIn);
    Widget icon(double size) => file != null
        ? filter == null
            ? Image.file(file, width: size, height: size)
            : ColorFiltered(
                colorFilter: filter,
                child: Image.file(file, width: size, height: size))
        : argb == null
            ? SvgPicture.asset(design.svgAsset, width: size, height: size)
            : SvgPicture.asset(design.monoSvgAsset,
                width: size, height: size, colorFilter: filter);
    return Container(
      height: 44,
      decoration:
          BoxDecoration(color: panel, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 12,
        children: [icon(16), icon(22), icon(32)],
      ),
    );
  }
}
