import 'dart:math';

import 'package:commet/main.dart';
import 'package:flutter/widgets.dart';

/// Vommet: the sidebar rail's sizes, set by "Sidebar icon size" in
/// Appearance settings (Vommet issue 506).
///
/// Each rail entry sits in a square slot: the icon plus [sidePadding] on
/// either side. The slot keeps the original proportions (56 px icons in
/// 70 px slots), so the corners, letters and glyphs that ImageButton derives
/// from the slot scale with the icon. The rail stays at least 70 px wide and
/// centres the slots, [margin] in from its edges; the pill stays on the
/// rail's edge. The default size draws exactly the original rail.
class RailMetrics {
  RailMetrics(double iconSize)
      : iconSize = iconSize.clamp(minIconSize, maxIconSize).toDouble();

  static const double defaultIconSize = 56;
  static const double minIconSize = 32;
  static const double maxIconSize = 64;

  /// Discord's guild icon size.
  static const double discordIconSize = 40;

  static const double _minRailWidth = 70;

  static RailMetrics get current =>
      RailMetrics(preferences.sidebarIconSize.value);

  final double iconSize;

  /// An entry's square slot; also the size ImageButton draws it at.
  double get slot => iconSize * 1.25;

  double get railWidth => max(_minRailWidth, slot);

  /// From the rail's edge to a slot's.
  double get margin => (railWidth - slot) / 2;

  /// From a slot's edge to its icon's.
  double get sidePadding => (slot - iconSize) / 2;

  /// Above and below each icon: 2 px at the default size, 4 px at Discord's.
  double get rowPadding =>
      max(1, 2 + (defaultIconSize - iconSize) / 8).toDouble();

  EdgeInsets get padding => EdgeInsets.fromLTRB(sidePadding, 0, sidePadding, 0);

  /// Scales one of the rail pill's heights, which suit the default size.
  double pill(double height) => height * iconSize / defaultIconSize;
}
