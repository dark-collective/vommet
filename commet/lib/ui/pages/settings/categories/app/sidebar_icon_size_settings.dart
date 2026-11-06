import 'package:commet/main.dart';
import 'package:commet/ui/atoms/rail_metrics.dart';
import 'package:commet/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: Settings › Appearance › Sidebar icon size (Vommet issue 506). The
/// slider steps by 4 px, so it lands on Discord's 40 px, 48 px and the
/// default 56 px.
class SidebarIconSizeSetting extends StatelessWidget {
  const SidebarIconSizeSetting({super.key});

  static String format(double size) {
    final px = size.round();
    if (size == RailMetrics.defaultIconSize) return sidebarIconSizeDefault(px);
    if (size == RailMetrics.discordIconSize) return sidebarIconSizeDiscord(px);
    return sidebarIconSizePx(px);
  }

  @override
  Widget build(BuildContext context) {
    return DoublePreferenceSlider(
      preference: preferences.sidebarIconSize,
      min: RailMetrics.minIconSize,
      max: RailMetrics.maxIconSize,
      divisions:
          ((RailMetrics.maxIconSize - RailMetrics.minIconSize) / 4).round(),
      numDecimals: 0,
      formatValue: format,
      title: sidebarIconSizeTitle,
      description: sidebarIconSizeDescription,
    );
  }
}

String get sidebarIconSizeTitle => Intl.message("Sidebar icon size",
    name: "sidebarIconSizeTitle",
    desc:
        "Title of the setting for the size of the icons on the space sidebar");

String get sidebarIconSizeDescription => Intl.message(
    "The size of the Home, direct message and space icons on the sidebar",
    name: "sidebarIconSizeDescription",
    desc: "Description of the sidebar icon size setting");

String sidebarIconSizePx(int size) => Intl.message("$size px",
    name: "sidebarIconSizePx",
    args: [size],
    desc: "A sidebar icon size in pixels");

String sidebarIconSizeDefault(int size) => Intl.message("$size px (default)",
    name: "sidebarIconSizeDefault",
    args: [size],
    desc: "The default sidebar icon size, in pixels");

String sidebarIconSizeDiscord(int size) => Intl.message("$size px (Discord)",
    name: "sidebarIconSizeDiscord",
    args: [size],
    desc: "The sidebar icon size Discord uses, in pixels");
