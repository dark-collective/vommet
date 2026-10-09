import 'package:commet/main.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

/// Vommet: Settings › Appearance › Banners and panes.
class BannerAndPaneSettings extends StatefulWidget {
  const BannerAndPaneSettings({super.key});

  @override
  State<BannerAndPaneSettings> createState() => _BannerAndPaneSettingsState();
}

class _BannerAndPaneSettingsState extends State<BannerAndPaneSettings> {
  static const gradients = {
    "theme": "Match theme",
    "classic": "Classic blue",
    "off": "Off",
  };

  @override
  Widget build(BuildContext context) {
    return Panel(
      header: "Banners and panes",
      mode: TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            const tiamat.Text("Banner glow"),
            const tiamat.Text.labelLow(
                "The glow behind a space or room name on its banner"),
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
            const tiamat.Text("Pane widths"),
            const tiamat.Text.labelLow(
                "Drag the edge of the room list or the member list to resize "
                "it; double-click the edge to reset it"),
            Align(
              alignment: Alignment.centerLeft,
              child: tiamat.Button.secondary(
                text: "Reset pane widths",
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
