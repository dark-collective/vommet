import 'package:commet/ui/molecules/composer_plus_menu.dart';
import 'package:commet/ui/molecules/composer_ring_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_color_utilities/material_color_utilities.dart';

// Vommet composer round 5: the ring on + keeps its meaning (reading =
// blue-violet, writing = teal) on every theme, stays clear of the accent
// and stands out on the box.
class _Theme {
  const _Theme(this.name, this.primaryHue, this.surface, {required this.dark});

  final String name;
  final double primaryHue;
  final Color surface;
  final bool dark;

  Color get primary => Color(Hct.from(primaryHue, 60, 60).toInt());
}

const themes = [
  _Theme("dark", 255, Color(0xff2b2c32), dark: true),
  _Theme("red", 356, Color(0xff4a1a20), dark: true),
  _Theme("light amber", 42, Color(0xfffffaf0), dark: false),
  _Theme("Telegram Day", 201, Color(0xffffffff), dark: false),
];

double tone(Color c) => Hct.fromInt(c.toARGB32()).tone;
double hue(Color c) => Hct.fromInt(c.toARGB32()).hue;

void main() {
  group("ringHue", () {
    for (final theme in themes) {
      for (final state in ComposerRingState.values) {
        test("${theme.name} / ${state.name}: near home, clear of primary", () {
          final h = ringHue(state.homeHue, theme.primaryHue);
          expect(hueDistance(h, theme.primaryHue),
              greaterThanOrEqualTo(ringMinFromPrimary - 1e-9));
          // Only the push away from the primary may move it further.
          if (hueDistance(h, theme.primaryHue) > ringMinFromPrimary + 1e-9) {
            expect(hueDistance(h, state.homeHue),
                lessThanOrEqualTo(ringMaxHarmonize + 1e-9));
          }
        });
      }
    }

    test("moves toward the primary, at most 15 degrees", () {
      // Red (356): reading 265 moves up, writing 175 moves down.
      expect(ringHue(265, 356), closeTo(280, 1e-9));
      expect(ringHue(175, 356), closeTo(160, 1e-9));
      // Light amber (42).
      expect(ringHue(265, 42), closeTo(280, 1e-9));
      expect(ringHue(175, 42), closeTo(160, 1e-9));
      // Telegram Day (201): reading moves 15 toward it.
      expect(ringHue(265, 201), closeTo(250, 1e-9));
    });

    test("pushed 28 degrees off a primary it would collide with", () {
      // Dark theme (255): reading 265 harmonizes to 260, then sits on the
      // far side of the primary.
      expect(ringHue(265, 255), closeTo(283, 1e-9));
      // Telegram Day (201): writing 175 harmonizes to 188, pushed to 173.
      expect(ringHue(175, 201), closeTo(173, 1e-9));
    });

    test("a gray primary leaves the home hue", () {
      expect(ringHue(265, 255, primaryChroma: 2), 265);
    });

    test("hueDistance wraps around", () {
      expect(hueDistance(350, 10), closeTo(20, 1e-9));
      expect(hueDistance(10, 350), closeTo(20, 1e-9));
      expect(hueDistance(0, 180), closeTo(180, 1e-9));
    });
  });

  group("ringColor", () {
    for (final theme in themes) {
      for (final state in ComposerRingState.values) {
        test("${theme.name} / ${state.name}: contrast and direction", () {
          final c = ringColor(state.homeHue, theme.primary, theme.surface);
          final surfaceTone = tone(theme.surface);
          final ringTone = tone(c);
          if (theme.dark) {
            expect(ringTone, greaterThan(surfaceTone));
          } else {
            expect(ringTone, lessThan(surfaceTone));
          }
          expect(Contrast.ratioOfTones(surfaceTone, ringTone),
              greaterThanOrEqualTo(ringMinContrast - 0.1));
          // Still its own hue, clear of the accent (a little slack for
          // the trip through RGB).
          final primaryHue = hue(theme.primary);
          expect(hueDistance(hue(c), primaryHue),
              greaterThanOrEqualTo(ringMinFromPrimary - 4));
        });
      }
    }

    test("reading and writing stay apart", () {
      for (final theme in themes) {
        final r = ringColor(265, theme.primary, theme.surface);
        final w = ringColor(175, theme.primary, theme.surface);
        expect(hueDistance(hue(r), hue(w)), greaterThan(60),
            reason: theme.name);
      }
    });
  });

  group("composerRing", () {
    final theme = themes.first;
    ComposerRing ring(List<ComposerRingState> on) =>
        composerRing(on, theme.primary, theme.surface);

    test("nothing on = no ring", () {
      expect(ring(const []).isEmpty, isTrue);
      expect(ring(const []).more, 0);
    });

    test("one on = one solid ring", () {
      final r = ring(const [ComposerRingState.reading]);
      expect(r.segments.length, 1);
      expect(r.more, 0);
    });

    test("two or three on = that many segments", () {
      expect(
          ring(const [ComposerRingState.reading, ComposerRingState.writing])
              .segments
              .length,
          2);
      final three = ring(const [
        ComposerRingState.reading,
        ComposerRingState.writing,
        ComposerRingState.reading
      ]);
      expect(three.segments.length, 3);
      expect(three.more, 0);
    });

    test("four or more = three segments and +N", () {
      final four = ring(List.filled(4, ComposerRingState.reading));
      expect(four.segments.length, 3);
      expect(four.more, 1);
      final six = ring(List.filled(6, ComposerRingState.writing));
      expect(six.segments.length, 3);
      expect(six.more, 3);
    });
  });

  group("composerLanguageShortList", () {
    test("current first, then recent, then downloaded, no repeats", () {
      expect(
          composerLanguageShortList(
              current: "es",
              recent: const ["fr", "es"],
              downloaded: const ["de", "fr"]),
          ["es", "fr", "de"]);
    });

    test("only reachable languages, at most five", () {
      expect(
          composerLanguageShortList(
              current: "es",
              recent: const ["fr", "xx"],
              downloaded: const ["de", "it", "pt", "nl", "ja"],
              reachable: const {"es", "fr", "de", "it", "pt", "nl", "ja"}),
          ["es", "fr", "de", "it", "pt"]);
    });
  });
}
