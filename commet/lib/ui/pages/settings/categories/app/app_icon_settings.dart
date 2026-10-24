import 'package:commet/config/app_icon_design.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:commet/utils/app_icon.dart';
import 'package:commet/utils/tray/app_tray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

/// Vommet: Settings › Appearance › App icon (Vommet issue 591).
class AppIconSettings extends StatelessWidget {
  const AppIconSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSearchTarget(
      ids: [
        appIconDesignPreference.key,
        splashIconDesignPreference.key,
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
              tiamat.Text.labelLow(appIconSettingsDescription),
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

/// The icon choices that apply on this platform; picking one saves it.
/// Also the onboarding page's content.
class AppIconPicker extends StatefulWidget {
  const AppIconPicker({super.key});

  @override
  State<AppIconPicker> createState() => _AppIconPickerState();
}

class _AppIconPickerState extends State<AppIconPicker> {
  Future<void> _set(StringPreference preference, String value) async {
    await preference.set(value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tray = AppTray.isSupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        if (AppIcon.windowIconSupported) ...[
          tiamat.Text.labelEmphasised(
              tray ? appIconWindowAndTray : appIconWindow),
          _designCards("window", appIconDesign,
              (d) => _set(appIconDesignPreference, d.name)),
        ],
        if (tray) ...[
          const SizedBox(height: 4),
          tiamat.Text.labelEmphasised(trayIconColoursTitle),
          _trayColourCards(),
        ],
        const SizedBox(height: 4),
        tiamat.Text.labelEmphasised(appIconSplash),
        _designCards("splash", splashIconDesign,
            (d) => _set(splashIconDesignPreference, d.name)),
      ],
    );
  }

  Widget _designCards(String id, AppIconDesign selected,
      void Function(AppIconDesign) onSelected) {
    return ChoiceCards<AppIconDesign>(
      key: ValueKey("app-icon-cards-$id"),
      selected: selected,
      onSelected: onSelected,
      options: [
        for (final d in AppIconDesign.values)
          ChoiceCardOption(
            value: d,
            title: d.label,
            description: d == AppIconDesign.original
                ? appIconOriginalDescription
                : appIconVDescription,
            preview: Center(
              child: SvgPicture.asset(d.svgAsset, width: 56, height: 56),
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
    Widget icon(double size) => argb == null
        ? SvgPicture.asset(design.svgAsset, width: size, height: size)
        : SvgPicture.asset(design.monoSvgAsset,
            width: size,
            height: size,
            colorFilter: ColorFilter.mode(Color(argb), BlendMode.srcIn));
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
