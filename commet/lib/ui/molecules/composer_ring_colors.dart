import 'dart:math' as math;
import 'dart:ui' show Color;

// ignore: depend_on_referenced_packages
import 'package:material_color_utilities/material_color_utilities.dart';

/// Vommet composer round 5: the colored ring on the composer's +, one color
/// per hidden setting that changes what gets sent or shown. Pure, so it can
/// be checked against any theme.
enum ComposerRingState {
  /// "Translate this room": others' messages show translated.
  reading(265),

  /// "Translate what I write": what you write goes out translated.
  writing(175);

  const ComposerRingState(this.homeHue);

  /// The hue it has before the theme moves it.
  final double homeHue;
}

/// What the ring around + shows.
class ComposerRing {
  const ComposerRing(this.segments, {this.more = 0});

  static const none = ComposerRing([]);

  /// One color per segment: one = a whole ring, two or three = arcs with
  /// gaps, never more than three.
  final List<Color> segments;

  /// The "+N" badge: how many are on beyond the three segments.
  final int more;

  bool get isEmpty => segments.isEmpty;
}

/// The most a home hue moves toward the theme's primary color.
const double ringMaxHarmonize = 15;

/// The least hue distance kept from the primary color, so a ring never
/// reads as the accent.
const double ringMinFromPrimary = 28;

/// The least contrast against the surface the box sits on.
const double ringMinContrast = 3;

const double _ringChroma = 48;

/// The ring for the settings that are [on], over [surface], in a theme
/// whose primary color is [primary].
ComposerRing composerRing(
    List<ComposerRingState> on, Color primary, Color surface) {
  if (on.isEmpty) return ComposerRing.none;
  final colors = [for (final s in on) ringColor(s.homeHue, primary, surface)];
  return ComposerRing(colors.take(3).toList(),
      more: colors.length > 3 ? colors.length - 3 : 0);
}

/// [homeHue] harmonized toward [primary] (at most [ringMaxHarmonize]
/// degrees, like Blend.harmonize), pushed [ringMinFromPrimary] degrees
/// away from it when they'd collide, at a tone that stands out on
/// [surface]: lighter on dark themes, darker on light ones.
Color ringColor(double homeHue, Color primary, Color surface) {
  final p = Hct.fromInt(primary.toARGB32());
  final hue = ringHue(homeHue, p.hue, primaryChroma: p.chroma);
  final surfaceTone = Hct.fromInt(surface.toARGB32()).tone;
  final dark = surfaceTone < 50;
  double tone;
  if (dark) {
    final t = Contrast.lighter(tone: surfaceTone, ratio: ringMinContrast);
    tone = t < 0 ? 100 : math.max(t, 70);
  } else {
    final t = Contrast.darker(tone: surfaceTone, ratio: ringMinContrast);
    tone = t < 0 ? 0 : math.min(t, 45);
  }
  return Color(Hct.from(hue, _ringChroma, tone).toInt());
}

/// The hue part of [ringColor]. A gray primary (no real hue) leaves the
/// home hue as it is.
double ringHue(double homeHue, double primaryHue, {double primaryChroma = 50}) {
  if (primaryChroma < 8) return homeHue;
  final d = _signedDifference(homeHue, primaryHue);
  var hue =
      _sanitize(homeHue + d.sign * math.min(d.abs() * 0.5, ringMaxHarmonize));
  final fromPrimary = _signedDifference(primaryHue, hue);
  if (fromPrimary.abs() < ringMinFromPrimary) {
    hue = _sanitize(primaryHue +
        (fromPrimary >= 0 ? ringMinFromPrimary : -ringMinFromPrimary));
  }
  return hue;
}

/// How far [to] is from [from], -180..180 (positive = counterclockwise).
double _signedDifference(double from, double to) =>
    ((to - from + 540) % 360) - 180;

double _sanitize(double hue) => ((hue % 360) + 360) % 360;

/// Shortest distance between two hues, 0..180.
double hueDistance(double a, double b) => _signedDifference(a, b).abs();
