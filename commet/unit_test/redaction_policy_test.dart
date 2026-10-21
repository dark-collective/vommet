import 'package:commet/main.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:commet/utils/redaction/redaction_preferences.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 400: redacted mode.
void main() {
  const salt = [1, 2, 3, 4];
  RedactionPolicy policy(RedactionSettings s, {List<int> salt = salt}) =>
      RedactionPolicy(s, salt: salt);

  group('presets', () {
    test('the six levels map onto the switches as the issue describes', () {
      final base = const RedactionSettings(roomNames: true);
      final s = {
        for (final p in RedactionPreset.values) p.level: p.applyTo(base)
      };

      expect(s[1]!.names, NameRedaction.hide);
      expect(s[1]!.text, TextRedaction.hide);
      expect(s[1]!.distinguishable, isFalse);
      expect(s[2]!.distinguishable, isTrue);
      expect(s[3]!.text, TextRedaction.keep);
      expect(s[3]!.distinguishable, isFalse);
      expect(s[4]!.text, TextRedaction.keep);
      expect(s[4]!.distinguishable, isTrue);
      expect(s[5]!.names, NameRedaction.scramble);
      expect(s[5]!.text, TextRedaction.keep);
      expect(s[6]!.names, NameRedaction.scramble);
      expect(s[6]!.text, TextRedaction.scramble);

      for (final settings in s.values) {
        expect(settings.avatars, isTrue);
        // Room names stay the user's own choice.
        expect(settings.roomNames, isTrue);
        // Pictures are blurred whenever text isn't kept.
        expect(settings.images, settings.text != TextRedaction.keep);
      }
    });

    test('matching finds the preset, or none after a manual change', () {
      for (final p in RedactionPreset.values) {
        expect(RedactionPreset.matching(p.applyTo(RedactionSettings.off)), p);
      }
      final changed = RedactionPreset.hideIdentity
          .applyTo(RedactionSettings.off)
          .copyWith(images: true);
      expect(RedactionPreset.matching(changed), isNull);
    });
  });

  test('off changes nothing', () {
    final p = RedactionPolicy.off;
    expect(p.isActive, isFalse);
    expect(p.name("Alice", "@a:x"), "Alice");
    expect(p.text("hello world"), "hello world");
    expect(p.roomName("General", "!r:x"), "General");
    expect(
        p.nameColor(const Color(0xFF123456), "@a:x"), const Color(0xFF123456));
    expect(p.hidesAvatars, isFalse);
    expect(p.blursImages, isFalse);
  });

  group('names', () {
    test('hidden and indistinguishable: everyone looks the same', () {
      final p = policy(const RedactionSettings(
          names: NameRedaction.hide, distinguishable: false));
      expect(p.name("Alice", "@a:x"), p.name("Bob", "@b:x"));
      expect(p.nameColor(const Color(0xFFFF0000), "@a:x"),
          RedactionPolicy.neutralColor);
      expect(p.avatarLetter("@a:x"), "");
      expect(p.identityColor("@a:x"), p.identityColor("@b:x"));
    });

    test('hidden but distinguishable: stable per person, not the name', () {
      final p = policy(const RedactionSettings(names: NameRedaction.hide));
      final alice = p.name("Alice", "@a:x");
      expect(alice, isNot(contains("Alice")));
      expect(alice, p.name("Alice (renamed)", "@a:x"));
      expect(alice, isNot(p.name("Alice", "@b:x")));
      expect(p.identityColor("@a:x"), p.identityColor("@a:x"));
      expect(p.avatarLetter("@a:x"), p.tag("@a:x").substring(0, 1));
    });

    test('tags and colours depend on the per-session salt', () {
      const s = RedactionSettings(names: NameRedaction.hide);
      final ids = List.generate(20, (i) => "@user$i:example.org");
      final a = ids.map(policy(s, salt: [1]).tag).toList();
      final b = ids.map(policy(s, salt: [2]).tag).toList();
      expect(a, isNot(b));
      expect(RedactionPolicy.sessionSalt, hasLength(32));
    });

    test('lorem ipsum names are two capitalised words, per person', () {
      final p = policy(const RedactionSettings(names: NameRedaction.scramble));
      final name = p.name("Alice", "@a:x");
      expect(name, matches(RegExp(r"^[A-Z][a-z]+ [A-Z][a-z]+$")));
      expect(name, p.name("Alice", "@a:x"));
      final names = {for (var i = 0; i < 20; i++) p.name("x", "@u$i:x")};
      expect(names.length, greaterThan(1));
    });
  });

  group('text', () {
    test('hide keeps only capped word lengths', () {
      final p = policy(const RedactionSettings(text: TextRedaction.hide));
      expect(p.text("hi there\nsupercalifragilistic"), "•• •••••\n${"•" * 12}");
      expect(p.drawsTextAsBars, isTrue);
    });

    test('lorem ipsum keeps the word count and layout', () {
      final p = policy(const RedactionSettings(text: TextRedaction.scramble));
      final out = p.text("Hello there,\nhow are you");
      expect(out, isNot(contains("Hello")));
      expect(out.split("\n").map((l) => l.split(" ").length), [2, 3]);
      expect(out[0], out[0].toUpperCase());
      expect(out, p.text("Hello there,\nhow are you"));
      expect(p.drawsTextAsBars, isFalse);
    });
  });

  group('room names', () {
    test('kept unless the room switch is on', () {
      final p = policy(const RedactionSettings(names: NameRedaction.hide));
      expect(p.roomName("General", "!r:x"), "General");
    });

    test('hidden with the room switch, distinguishable per room', () {
      final p = policy(const RedactionSettings(roomNames: true));
      expect(p.roomName("General", "!r:x"), startsWith("Room "));
      expect(p.roomName("General", "!r:x"), isNot(p.roomName("Off", "!o:x")));
    });

    test('a DM follows the name switch, keyed on the other person', () {
      final p = policy(const RedactionSettings(names: NameRedaction.hide));
      expect(p.roomName("Alice", "!dm:x", dmPartnerId: "@a:x"),
          p.name("Alice", "@a:x"));
    });
  });

  group('preferences', () {
    setUp(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
    });

    test('off by default, even with the experiment on', () async {
      expect(preferences.effectiveRedaction, RedactionSettings.off);
      await preferences.experimentRedactedMode.set(true);
      expect(preferences.effectiveRedaction, RedactionSettings.off);
    });

    test('switches round-trip and apply once turned on', () async {
      final s = RedactionPreset.loremEverything
          .applyTo(const RedactionSettings(roomNames: false));
      await preferences.setRedactionSwitches(s);
      expect(preferences.redactionSwitches, s);

      await preferences.redactionEnabled.set(true);
      expect(preferences.effectiveRedaction, RedactionSettings.off,
          reason: "experiment still off");
      await preferences.experimentRedactedMode.set(true);
      expect(preferences.effectiveRedaction, s);
    });
  });
}
