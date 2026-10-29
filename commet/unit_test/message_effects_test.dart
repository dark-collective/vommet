import 'dart:io';

import 'package:commet/client/matrix/components/message_effects/matrix_message_effects_component.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/ui/atoms/reaction_burst.dart';
import 'package:commet/ui/molecules/message_effect_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _copy = ValueKey("reaction-burst-copy");

Widget _chip(int count, {bool reduceMotion = false, bool covered = false}) =>
    MaterialApp(
      home: TickerMode(
        // false = hidden behind another screen, e.g. a fullscreen stream
        enabled: !covered,
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(
              child: ReactionBurst(
                emojiKey: "🎉",
                count: count,
                child: const Text("🎉"),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    ReactionBurstSignal.clear();
  });

  group("effect picker", () {
    test("an effect is sent as its command, with what was typed", () {
      final confetti = MessageEffectPicker.all.first;
      expect(
          confetti.commandText("I got the job!!"), "/confetti I got the job!!");
      expect(confetti.commandText(""), "/confetti");
    });

    test("all nine effects, each with a distinct command", () {
      final commands = MessageEffectPicker.all.map((e) => e.command).toSet();
      expect(commands, {
        "confetti",
        "fireworks",
        "hearts",
        "snowfall",
        "rainfall",
        "spaceinvaders",
        "hug",
        "cuddle",
        "googly",
      });
    });

    test("Element's fireworks, rainfall and hearts are received", () {
      expect(
          MatrixMessageEffectsComponent.knownEffectTypes,
          containsAll([
            "nic.custom.fireworks",
            "io.element.effect.rainfall",
            "io.element.effect.hearts",
            "nic.custom.confetti",
            "io.element.effect.snowfall",
            "io.element.effects.space_invaders",
            "im.fluffychat.cute_event",
          ]));
    });
  });

  test("telemetry schema v39 names the Reaction bursts experiment", () {
    final schema = TelemetrySchema.parse(
        File("assets/telemetry/schema.json").readAsStringSync());
    expect(schema.version, greaterThanOrEqualTo(39));
    expect(schema.enumAllows("experiment_key", experimentReactionBursts.key),
        isTrue);
  });

  group("live reactions", () {
    test("only a reaction sent just now counts as live", () {
      final now = DateTime(2026, 10, 26, 18);
      ReactionBurstSignal.noteLive("👍",
          sentAt: now.subtract(const Duration(minutes: 5)), now: now);
      expect(ReactionBurstSignal.isRecent("👍", now: now), isFalse);

      ReactionBurstSignal.noteLive("🎉", sentAt: now, now: now);
      expect(ReactionBurstSignal.isRecent("🎉", now: now), isTrue);
      expect(
          ReactionBurstSignal.isRecent("🎉",
              now: now.add(const Duration(seconds: 10))),
          isFalse);
    });
  });

  group("reaction burst", () {
    testWidgets("a live reaction bursts, then cleans up", (tester) async {
      await tester.pumpWidget(_chip(1));
      expect(find.byKey(_copy), findsNothing);

      ReactionBurstSignal.noteLive("🎉");
      await tester.pumpWidget(_chip(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(_copy), findsNWidgets(ReactionBurst.copies));

      await tester.pump(ReactionBurst.duration);
      await tester.pump();
      expect(find.byKey(_copy), findsNothing);
    });

    testWidgets("history doesn't burst", (tester) async {
      await tester.pumpWidget(_chip(3));
      await tester.pump();
      await tester.pumpWidget(_chip(4));
      await tester.pump();
      expect(find.byKey(_copy), findsNothing);
    });

    testWidgets("a new chip for a live reaction bursts", (tester) async {
      ReactionBurstSignal.noteLive("🎉");
      await tester.pumpWidget(_chip(1));
      await tester.pump();
      expect(find.byKey(_copy), findsNWidgets(ReactionBurst.copies));
      await tester.pump(ReactionBurst.duration);
    });

    testWidgets("off with reduced motion, the experiment or effects off",
        (tester) async {
      Future<void> expectNoBurst({bool reduceMotion = false}) async {
        await tester.pumpWidget(_chip(1, reduceMotion: reduceMotion));
        ReactionBurstSignal.noteLive("🎉");
        await tester.pumpWidget(_chip(2, reduceMotion: reduceMotion));
        await tester.pump();
        expect(find.byKey(_copy), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }

      await expectNoBurst(reduceMotion: true);

      await experimentReactionBursts.set(false);
      await expectNoBurst();
      await experimentReactionBursts.set(true);

      await preferences.messageEffectsEnabled.set(false);
      await expectNoBurst();
    });

    testWidgets("not while covered by a fullscreen stream", (tester) async {
      await tester.pumpWidget(_chip(1, covered: true));
      ReactionBurstSignal.noteLive("🎉");
      await tester.pumpWidget(_chip(2, covered: true));
      await tester.pump();
      expect(find.byKey(_copy), findsNothing);
    });

    testWidgets("a running burst ends when the chat gets covered",
        (tester) async {
      await tester.pumpWidget(_chip(1));
      ReactionBurstSignal.noteLive("🎉");
      await tester.pumpWidget(_chip(2));
      await tester.pump();
      expect(find.byKey(_copy), findsNWidgets(ReactionBurst.copies));

      await tester.pumpWidget(_chip(2, covered: true));
      await tester.pump();
      expect(find.byKey(_copy), findsNothing);
    });
  });
}
