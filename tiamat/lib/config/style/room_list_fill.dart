import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_gradient.dart';

/// Vommet issue 1194: one optional static navigation fill, not a color role.
class RoomListFill extends ThemeExtension<RoomListFill> {
  RoomListFill(List<Color> colors, List<double> stops,
      {this.angle = 135, this.opacity = 1})
      : colors = List.unmodifiable(colors),
        stops = List.unmodifiable(stops);

  final List<Color> colors;
  final List<double> stops;
  final double angle;
  final double opacity;

  LinearGradient get gradient =>
      GradientPreset('room-list', '', Brightness.dark,
              angle: angle, midpoint: 0.5, colors: colors, stops: stops)
          .gradient;

  LinearGradient get paintGradient {
    final g = gradient;
    return LinearGradient(
        begin: g.begin,
        end: g.end,
        stops: stops,
        colors: colors.map((c) => c.withValues(alpha: c.a * opacity)).toList());
  }

  static String hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0')}';

  Map<String, dynamic> toJson() => {
        'gradient': {
          'colors': colors.map(hex).toList(),
          'stops': stops,
          'angle': angle,
        },
        'opacity': opacity,
      };

  static RoomListFill? fromJson(Object? value) {
    if (value is! Map || value['gradient'] is! Map) {
      return null;
    }
    final g = value['gradient'] as Map;
    final raw = g['colors'];
    if (raw is! List || raw.length < 2 || raw.length > 5) {
      return null;
    }
    final colors = <Color>[];
    for (final c in raw) {
      if (c is! String ||
          !RegExp(r'^#(?:[\da-fA-F]{6}|[\da-fA-F]{8})$').hasMatch(c)) {
        return null;
      }
      colors.add(Color(int.parse(
          c.length == 7 ? 'ff${c.substring(1)}' : c.substring(1),
          radix: 16)));
    }
    final positions = g['stops'] ??
        [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)];
    if (positions is! List || positions.length != colors.length) {
      return null;
    }
    final stops = <double>[];
    for (final p in positions) {
      if (p is! num ||
          !p.isFinite ||
          p < 0 ||
          p > 1 ||
          (stops.isNotEmpty && p < stops.last)) {
        return null;
      }
      stops.add(p.toDouble());
    }
    final angle = g['angle'] ?? 135;
    final opacity = value['opacity'] ?? 1;
    if (angle is! num ||
        !angle.isFinite ||
        angle < 0 ||
        angle > 360 ||
        opacity is! num ||
        !opacity.isFinite ||
        opacity < 0 ||
        opacity > 1) {
      return null;
    }
    return RoomListFill(colors, stops,
        angle: angle.toDouble(), opacity: opacity.toDouble());
  }

  @override
  RoomListFill copyWith(
          {List<Color>? colors,
          List<double>? stops,
          double? angle,
          double? opacity}) =>
      RoomListFill(colors ?? this.colors, stops ?? this.stops,
          angle: angle ?? this.angle, opacity: opacity ?? this.opacity);

  @override
  RoomListFill lerp(covariant RoomListFill? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
