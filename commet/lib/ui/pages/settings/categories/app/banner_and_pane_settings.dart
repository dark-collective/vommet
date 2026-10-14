import 'package:commet/main.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';
import 'package:intl/intl.dart';

/// Vommet: Settings › Appearance › Banners and panes.
class BannerAndPaneSettings extends StatefulWidget {
  const BannerAndPaneSettings({super.key});

  @override
  State<BannerAndPaneSettings> createState() => _BannerAndPaneSettingsState();
}

class _BannerAndPaneSettingsState extends State<BannerAndPaneSettings> {
  static Map<String, String> get gradients => {
        "theme": bannerGlowMatchTheme,
        "classic": bannerGlowClassicBlue,
        "off": bannerGlowOff,
      };

  @override
  Widget build(BuildContext context) {
    return Panel(
      header: bannerPaneSettingsHeader,
      mode: TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            tiamat.Text(bannerGlowTitle),
            tiamat.Text.labelLow(bannerGlowDescription),
            tiamat.DropdownSelector<String>(
              color: ColorScheme.of(context).surfaceContainerLow,
              items: gradients.keys.toList(),
              itemBuilder: (item) => tiamat.Text(gradients[item] ?? item),
              onItemSelected: (item) async {
                if (item == null) return;
                await preferences.bannerGradient.set(item);
                if (mounted) setState(() {});
              },
              // An older "space" value shows as the default.
              value: gradients.containsKey(preferences.bannerGradient.value)
                  ? preferences.bannerGradient.value
                  : "theme",
            ),
            const tiamat.Seperator(),
            tiamat.Text(paneWidthsTitle),
            tiamat.Text.labelLow(paneWidthsDescription),
            Align(
              alignment: Alignment.centerLeft,
              child: tiamat.Button.secondary(
                text: paneWidthsReset,
                onTap: () {
                  PaneWidths.left.reset();
                  PaneWidths.right.reset();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String get bannerGlowMatchTheme => Intl.message("Match theme",
    name: "bannerGlowMatchTheme",
    desc: "Banner glow option: colour taken from the theme");

String get bannerGlowClassicBlue => Intl.message("Classic blue",
    name: "bannerGlowClassicBlue",
    desc: "Banner glow option: the classic blue glow");

String get bannerGlowOff => Intl.message("Off",
    name: "bannerGlowOff", desc: "Banner glow option: no glow");

String get bannerPaneSettingsHeader => Intl.message("Banners and panes",
    name: "bannerPaneSettingsHeader",
    desc: "Header of the Banners and panes appearance settings panel");

String get bannerGlowTitle => Intl.message("Banner glow",
    name: "bannerGlowTitle", desc: "Title of the banner glow setting");

String get bannerGlowDescription =>
    Intl.message("The glow behind a space or room name on its banner",
        name: "bannerGlowDescription",
        desc: "Description of the banner glow setting");

String get paneWidthsTitle => Intl.message("Pane widths",
    name: "paneWidthsTitle", desc: "Title of the pane widths setting");

String get paneWidthsDescription => Intl.message(
    "Drag the edge of the room list or the member list to resize it; double-click the edge to reset it",
    name: "paneWidthsDescription",
    desc: "Description of the pane widths setting");

String get paneWidthsReset => Intl.message("Reset pane widths",
    name: "paneWidthsReset",
    desc: "Button that resets the room list and member list widths");
