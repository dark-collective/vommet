// Vommet: color chat wallpapers (WallpaperFill) and the four-point gradient.

import 'package:commet/client/components/chat_wallpaper/chat_wallpaper_component.dart';
import 'package:commet/ui/organisms/chat_wallpaper/wallpaper_gradient.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("a fill reads #rrggbb colors and drops junk", () {
    final fill = WallpaperFill.fromJson({
      "colors": ["#dbddbb", "red", 5, "#6BA587", "#12345678"],
      "animate": true,
    })!;
    expect(fill.colors, [const Color(0xffdbddbb), const Color(0xff6ba587)]);
    // Two colors are a plain gradient: nothing to animate.
    expect(fill.animate, isFalse);
    expect(WallpaperFill.fromJson({"colors": []}), isNull);
    expect(WallpaperFill.fromJson({"colors": "#ffffff"}), isNull);
    expect(WallpaperFill.fromJson(null), isNull);
  });

  test("a fill keeps at most four colors and round-trips", () {
    final fill = WallpaperFill.fromJson({
      "colors": ["#000001", "#000002", "#000003", "#000004", "#000005"],
      "animate": true,
    })!;
    expect(fill.colors.length, WallpaperFill.maxColors);
    expect(fill.animate, isTrue);
    expect(fill.toJson(), {
      "colors": ["#000001", "#000002", "#000003", "#000004"],
      "animate": true,
    });
    expect(WallpaperFill.fromJson(fill.toJson()), fill);
    expect(fill.source, "fill:#000001,#000002,#000003,#000004");
  });

  test("one color has no animate flag", () {
    expect(const WallpaperFill([Color(0xff112233)]).toJson(), {
      "colors": ["#112233"],
    });
  });

  test("a fill's pattern reads, clamps and round-trips", () {
    final fill = WallpaperFill.fromJson({
      "colors": ["#dbddbb"],
      "pattern": {"name": "telegram", "strength": 3},
    })!;
    expect(fill.pattern, 1.0);
    expect(WallpaperFill.fromJson(fill.toJson()), fill);
    expect(fill.source, isNot(const WallpaperFill([Color(0xffdbddbb)]).source));
    // No strength: the default one.
    expect(
        WallpaperFill.fromJson({
          "colors": ["#dbddbb"],
          "pattern": {"name": "telegram"},
        })!
            .pattern,
        WallpaperFill.defaultPatternStrength);
  });

  test("an unknown or missing pattern is left out", () {
    for (final pattern in [
      null,
      "telegram",
      {"name": "other", "strength": 0.5},
    ]) {
      final fill = WallpaperFill.fromJson({
        "colors": ["#dbddbb"],
        "pattern": pattern,
      })!;
      expect(fill.pattern, isNull);
      expect(fill.toJson().containsKey("pattern"), isFalse);
    }
  });

  test("dark colors count as dark", () {
    expect(const WallpaperFill([Color(0xff1b2836), Color(0xff2b3a55)]).isDark,
        isTrue);
    expect(const WallpaperFill([Color(0xffdbddbb)]).isDark, isFalse);
  });

  test("gradient weights add up to 1, nearest color strongest", () {
    final centers = WallpaperGradient.centers(4, 0);
    for (final point in const [
      Offset(0, 0),
      Offset(0.5, 0.5),
      Offset(1, 1),
      Offset(0.8, 0.1),
    ]) {
      final w = WallpaperGradient.weights(point, centers);
      expect(w.fold(0.0, (a, b) => a + b), closeTo(1, 1e-9));
    }
    final atFirst = WallpaperGradient.weights(centers[0], centers);
    expect(atFirst.indexOf(atFirst.reduce((a, b) => a > b ? a : b)), 0);
  });

  test("colors sit on every other ring point and move one step", () {
    expect(WallpaperGradient.centers(4, 0), [
      WallpaperGradient.ring[0],
      WallpaperGradient.ring[2],
      WallpaperGradient.ring[4],
      WallpaperGradient.ring[6],
    ]);
    expect(WallpaperGradient.centers(4, 1)[3], WallpaperGradient.ring[7]);
    expect(WallpaperGradient.centers(3, 7)[1], WallpaperGradient.ring[1]);
  });

  test("far from every color, the nearest one alone", () {
    final w = WallpaperGradient.weights(
        const Offset(10, 10), const [Offset(0, 0), Offset(1, 1)]);
    expect(w, [0, 1]);
  });

  test("the gradient at a color's own point leans to that color", () {
    const colors = [
      Color(0xffff0000),
      Color(0xff00ff00),
      Color(0xff0000ff),
      Color(0xffffffff),
    ];
    final centers = WallpaperGradient.centers(4, 0);
    final c = WallpaperGradient.colorAt(centers[0], colors, centers);
    expect(c.r, greaterThan(c.g));
    expect(c.r, greaterThan(c.b));
  });
}
