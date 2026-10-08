import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_light.dart';

/// A full-window gradient theme. The palettes are the gradient presets of
/// Discord's Nitro client themes (as unlocked by Vencord's FakeNitro); the
/// look is rebuilt the same way: one gradient behind the whole window, with
/// black (dark) or white (light) panels of fixed opacity on top.
class GradientPreset {
  const GradientPreset(this.id, this.name, this.brightness,
      {required this.angle,
      required this.midpoint,
      required this.colors,
      required this.stops});

  final String id;
  final String name;
  final Brightness brightness;

  /// CSS `linear-gradient` angle in degrees (0 = towards the top, clockwise).
  final double angle;

  /// Where along the gradient the representative colour sits (0..1).
  final double midpoint;
  final List<Color> colors;
  final List<double> stops;

  LinearGradient get gradient {
    var rad = angle * math.pi / 180;
    var x = math.sin(rad);
    var y = -math.cos(rad);
    // CSS stretches the gradient line so the corners land on 0 % and 100 %;
    // in alignment space (exact for a square box) that is |sin| + |cos|.
    var scale = x.abs() + y.abs();
    return LinearGradient(
      begin: Alignment(-x * scale, -y * scale),
      end: Alignment(x * scale, y * scale),
      colors: colors,
      stops: stops,
    );
  }

  /// The gradient's colour at [midpoint], used to tint opaque surfaces.
  Color get tint => sample(midpoint);

  Color sample(double t) {
    if (t <= stops.first) return colors.first;
    if (t >= stops.last) return colors.last;
    for (var i = 1; i < stops.length; i++) {
      if (t <= stops[i]) {
        var span = stops[i] - stops[i - 1];
        var local = span == 0 ? 0.0 : (t - stops[i - 1]) / span;
        return Color.lerp(colors[i - 1], colors[i], local)!;
      }
    }
    return colors.last;
  }
}

class ThemeGradient {
  static const String prefix = "gradient:";

  static GradientPreset? byId(String id) {
    if (id.startsWith(prefix)) id = id.substring(prefix.length);
    for (var preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static ThemeData theme(GradientPreset preset) {
    var dark = preset.brightness == Brightness.dark;
    var overlay = dark ? Colors.black : Colors.white;
    var tint = preset.tint;

    // Panel opacities from Discord's gradient themes (dark / light).
    var lowest = dark ? 0.5 : 0.3; // app frame
    var low = dark ? 0.85 : 0.9; // side bars
    var surface = dark ? 0.8 : 0.9; // chat
    var dim = 0.8;
    var container = 0.7;
    var high = dark ? 0.5 : 0.6;
    var highest = dark ? 0.4 : 0.3;

    // Opaque versions (the overlay over the gradient's tint) for widgets that
    // are not glass tiles: dialogs, menus, popups.
    Color over(double opacity) => Color.lerp(tint, overlay, opacity)!;

    var base = dark ? ThemeDark.theme : ThemeLight.theme;
    var scheme = base.colorScheme.copyWith(
      surface: over(surface),
      surfaceDim: over(dim),
      surfaceBright: over(highest),
      surfaceContainerLowest: over(lowest),
      surfaceContainerLow: over(low),
      surfaceContainer: over(container),
      surfaceContainerHigh: over(high),
      surfaceContainerHighest: over(highest),
      outline: (dark ? Colors.white : Colors.black).withAlpha(24),
    );

    return ThemeBase.theme(scheme).copyWith(extensions: [
      const ThemeSettings(caulkBorders: true, caulkBorderRadius: 1),
      GlassSettings(
        surfaceSigma: 0,
        surfaceOpacity: surface,
        surfaceDimSigma: 0,
        surfaceDimOpacity: dim,
        surfaceContainerLowestSigma: 0,
        surfaceContainerLowestOpacity: lowest,
        surfaceContainerLowSigma: 0,
        surfaceContainerLowOpacity: low,
        surfaceContainerSigma: 0,
        surfaceContainerOpacity: container,
        surfaceContainerHighSigma: 0,
        surfaceContainerHighOpacity: high,
        surfaceContainerHighestSigma: 0,
        surfaceContainerHighestOpacity: highest,
      ),
      FoundationSettings(color: tint, gradient: preset.gradient),
      base.extension<ExtraColors>() ?? ExtraColors.fromScheme(scheme),
    ]);
  }

  static const List<GradientPreset> presets = [
    GradientPreset("mint-apple", "Mint Apple", Brightness.light,
        angle: 180.0,
        midpoint: 0.27,
        colors: [Color(0xff56b69f), Color(0xff63bc61), Color(0xff9eca67)],
        stops: [0.0615, 0.487, 0.9307]),
    GradientPreset("citrus-sherbert", "Citrus Sherbert", Brightness.light,
        angle: 180.0,
        midpoint: 0.27,
        colors: [Color(0xfff3b336), Color(0xffee8558)],
        stops: [0.311, 0.6709]),
    GradientPreset("retro-raincloud", "Retro Raincloud", Brightness.light,
        angle: 148.71,
        midpoint: 0.5,
        colors: [
          Color(0xff3a7ca1),
          Color(0xff7f7eb9),
          Color(0xff7f7eb9),
          Color(0xff3a7ca1)
        ],
        stops: [
          0.0564,
          0.2638,
          0.4992,
          0.7312
        ]),
    GradientPreset("hanami", "Hanami", Brightness.light,
        angle: 38.08,
        midpoint: 0.5,
        colors: [Color(0xffefaab3), Color(0xffefd696), Color(0xffa6daa2)],
        stops: [0.0356, 0.3549, 0.6878]),
    GradientPreset("sunrise", "Sunrise", Brightness.light,
        angle: 154.19,
        midpoint: 0.5,
        colors: [Color(0xff9f4175), Color(0xffc49064), Color(0xffa6953d)],
        stops: [0.0862, 0.4807, 0.7604]),
    GradientPreset("cotton-candy", "Cotton Candy", Brightness.light,
        angle: 180.14,
        midpoint: 0.5,
        colors: [Color(0xfff4abb8), Color(0xffb1c2fc)],
        stops: [0.085, 0.9428]),
    GradientPreset("lofi-vibes", "Lofi Vibes", Brightness.light,
        angle: 179.52,
        midpoint: 0.27,
        colors: [
          Color(0xffa4c0f7),
          Color(0xffa9e4e8),
          Color(0xffb0e2b8),
          Color(0xffcfdfa2)
        ],
        stops: [
          0.0708,
          0.3494,
          0.6512,
          0.9623
        ]),
    GradientPreset("desert-khaki", "Desert Khaki", Brightness.light,
        angle: 38.99,
        midpoint: 0.5,
        colors: [Color(0xffe7dbd0), Color(0xffdfd0b2), Color(0xffe0d6a3)],
        stops: [0.1292, 0.3292, 0.5211]),
    GradientPreset("sunset", "Sunset", Brightness.dark,
        angle: 141.68,
        midpoint: 0.35,
        colors: [Color(0xff48288c), Color(0xffdb7f4b)],
        stops: [0.2757, 0.7125]),
    GradientPreset("chroma-glow", "Chroma Glow", Brightness.dark,
        angle: 128.92,
        midpoint: 0.15,
        colors: [
          Color(0xff0eb5bf),
          Color(0xff4c0ce0),
          Color(0xffa308a7),
          Color(0xff9a53ff),
          Color(0xff218be0)
        ],
        stops: [
          0.0394,
          0.261,
          0.3982,
          0.5689,
          0.7645
        ]),
    GradientPreset("forest", "Forest", Brightness.dark,
        angle: 162.27,
        midpoint: 0.5,
        colors: [
          Color(0xff142215),
          Color(0xff2d4d39),
          Color(0xff454c32),
          Color(0xff5a7c58),
          Color(0xffa98e4b)
        ],
        stops: [
          0.112,
          0.2993,
          0.4864,
          0.6785,
          0.8354
        ]),
    GradientPreset("crimson-moon", "Crimson Moon", Brightness.dark,
        angle: 64.92,
        midpoint: 0.3,
        colors: [Color(0xff950909), Color(0xff000000)],
        stops: [0.1617, 0.72]),
    GradientPreset("midnight-blurple", "Midnight Blurple", Brightness.dark,
        angle: 48.17,
        midpoint: 0.24,
        colors: [Color(0xff5348ca), Color(0xff140730)],
        stops: [0.1121, 0.6192]),
    GradientPreset("mars", "Mars", Brightness.dark,
        angle: 170.82,
        midpoint: 0.5,
        colors: [Color(0xff895240), Color(0xff8f4343)],
        stops: [0.1461, 0.7462]),
    GradientPreset("dusk", "Dusk", Brightness.dark,
        angle: 180.0,
        midpoint: 0.5,
        colors: [Color(0xff665069), Color(0xff91a3d1)],
        stops: [0.1284, 0.8599]),
    GradientPreset("under-the-sea", "Under the Sea", Brightness.dark,
        angle: 179.14,
        midpoint: 0.5,
        colors: [Color(0xff647962), Color(0xff588575), Color(0xff6a8482)],
        stops: [0.0191, 0.4899, 0.9635]),
    GradientPreset("retro-storm", "Retro Storm", Brightness.dark,
        angle: 148.71,
        midpoint: 0.61,
        colors: [
          Color(0xff3a7ca1),
          Color(0xff58579a),
          Color(0xff58579a),
          Color(0xff3a7ca1)
        ],
        stops: [
          0.0564,
          0.2638,
          0.4992,
          0.7312
        ]),
    GradientPreset("neon-nights", "Neon Nights", Brightness.dark,
        angle: 180.0,
        midpoint: 0.5,
        colors: [Color(0xff01a89e), Color(0xff7d60ba), Color(0xffb43898)],
        stops: [0.0, 0.5, 1.0]),
    GradientPreset(
        "strawberry-lemonade", "Strawberry Lemonade", Brightness.dark,
        angle: 161.03,
        midpoint: 0.32,
        colors: [Color(0xffaf1a6c), Color(0xffc26b20), Color(0xffe7a525)],
        stops: [0.1879, 0.4976, 0.8072]),
    GradientPreset("aurora", "Aurora", Brightness.dark,
        angle: 239.16,
        midpoint: 0.34,
        colors: [
          Color(0xff062053),
          Color(0xff191fbb),
          Color(0xff13929a),
          Color(0xff218573),
          Color(0xff051a81)
        ],
        stops: [
          0.1039,
          0.2687,
          0.4831,
          0.6498,
          0.925
        ]),
    GradientPreset("sepia", "Sepia", Brightness.dark,
        angle: 69.98,
        midpoint: 0.5,
        colors: [Color(0xff857664), Color(0xff5b4421)],
        stops: [0.1414, 0.6035]),
    GradientPreset("blurple-twilight", "Blurple Twilight", Brightness.dark,
        angle: 47.61,
        midpoint: 0.5,
        colors: [Color(0xff2c3fe7), Color(0xff261d83)],
        stops: [0.1118, 0.6454]),
  ];
}
