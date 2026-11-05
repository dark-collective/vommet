import 'package:flutter/painting.dart';

/// A named power level from MSC3949 power level tags.
class PowerLevelTag {
  final String name;
  final Color? color;

  /// An emoji icon.
  final String? emoji;

  /// An image icon (`mxc://`).
  final Uri? iconMxc;

  const PowerLevelTag(
      {required this.name, this.color, this.emoji, this.iconMxc});
}

/// MSC3949 power level tags: names, colours and icons for power levels.
/// Read from `m.room.power_level_tags`, or Cinny's unstable
/// `in.cinny.room.power_level_tags`.
class PowerLevelTags {
  static const stableType = "m.room.power_level_tags";
  static const unstableType = "in.cinny.room.power_level_tags";

  /// Tagged levels, highest first.
  final List<(int, PowerLevelTag)> levels;

  const PowerLevelTags(this.levels);

  bool get isEmpty => levels.isEmpty;

  /// Lenient parse of the event content; entries without a numeric key or a
  /// name are skipped. Returns null when nothing usable is left.
  static PowerLevelTags? fromContent(Map<String, Object?>? content) {
    if (content == null) return null;

    final levels = <(int, PowerLevelTag)>[];
    for (final entry in content.entries) {
      final level = int.tryParse(entry.key);
      final value = entry.value;
      if (level == null || value is! Map) continue;

      final name = value["name"];
      if (name is! String || name.trim().isEmpty) continue;

      final icon = value["icon"];
      final key = icon is Map ? icon["key"] : null;
      final emoji = key is String && key.isNotEmpty && !key.startsWith("mxc://")
          ? key
          : null;

      final iconMxc =
          key is String && key.startsWith("mxc://") ? Uri.tryParse(key) : null;

      levels.add((
        level,
        PowerLevelTag(
            name: name.trim(),
            color: parseColor(value["color"]),
            emoji: emoji,
            iconMxc: iconMxc)
      ));
    }

    if (levels.isEmpty) return null;
    levels.sort((a, b) => b.$1.compareTo(a.$1));
    return PowerLevelTags(levels);
  }

  /// The tag for [powerLevel]: its own, or the nearest lower tagged level.
  /// Null when no tagged level is at or below it.
  (int, PowerLevelTag)? tagFor(int powerLevel) {
    for (final entry in levels) {
      if (entry.$1 <= powerLevel) return entry;
    }
    return null;
  }

  /// `#rrggbb` (or `#rgb`) to an opaque colour.
  static Color? parseColor(Object? value) {
    if (value is! String) return null;
    var hex = value.trim();
    if (!hex.startsWith("#")) return null;
    hex = hex.substring(1);
    if (hex.length == 3) hex = hex.split("").map((c) => "$c$c").join();
    if (hex.length != 6) return null;
    final rgb = int.tryParse(hex, radix: 16);
    if (rgb == null) return null;
    return Color(0xFF000000 | rgb);
  }

  /// [color] made readable on [background]: blended toward [towards] (the
  /// theme's text colour) until it reaches a WCAG contrast of [minContrast],
  /// as MSC3949 allows. Tag colours are picked for one theme; a dark red
  /// would vanish on a dark background.
  static Color readableColor(Color color, Color background, Color towards,
      {double minContrast = 4.5}) {
    for (var step = 0; step <= 10; step++) {
      final candidate = Color.lerp(color, towards, step / 10)!;
      if (contrastRatio(candidate, background) >= minContrast) {
        return candidate;
      }
    }
    return towards;
  }

  /// WCAG contrast ratio of two opaque colours (1 to 21).
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
  }
}
