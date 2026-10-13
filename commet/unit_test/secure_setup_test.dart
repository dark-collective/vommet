import 'dart:math';

import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/pages/secure_setup/login_password_memory.dart';
import 'package:commet/ui/pages/secure_setup/password_strength.dart';
import 'package:commet/ui/pages/secure_setup/recovery_phrase.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group("state", () {
    SecureMessagingState state({
      bool encryption = true,
      bool storage = true,
      bool master = true,
      bool signed = true,
    }) =>
        SecureMessaging.fromParts(
                encryption: encryption,
                hasSecretStorage: storage,
                hasMasterKey: master,
                thisDeviceSigned: signed,
                hasKeyBackup: true)
            .state;

    test("never set up: nothing on the server at all", () {
      expect(state(storage: false, master: false, signed: false),
          SecureMessagingState.notSetUp);
    });
    test("anything existing means an existing account, never 'not set up'", () {
      expect(state(storage: false, signed: false),
          SecureMessagingState.thisDeviceUnverified,
          reason: "master key on the server, no secret storage");
      expect(state(master: false, signed: false),
          SecureMessagingState.thisDeviceUnverified,
          reason: "secret storage, no master key");
    });
    test("set up, this device not verified", () {
      expect(state(signed: false), SecureMessagingState.thisDeviceUnverified);
    });
    test("ready", () => expect(state(), SecureMessagingState.ready));
    test("no encryption: unknown, never asks",
        () => expect(state(encryption: false), SecureMessagingState.unknown));
  });

  group("phrase", () {
    final list = [for (var i = 0; i < 7776; i++) "w$i"];
    test("6 words from the list", () {
      final p = RecoveryPhrase.fromList(list, random: Random(1));
      expect(p.words, hasLength(6));
      expect(p.words.every(list.contains), isTrue);
      expect(p.passphrase.split(" "), p.words);
    });
    test("confirm asks two different positions", () {
      for (var seed = 0; seed < 200; seed++) {
        final (a, b) = RecoveryPhrase.confirmPositions(random: Random(seed));
        expect(a, lessThan(b));
        expect(b, lessThan(6));
      }
    });
    test("matching ignores case and spaces", () {
      final p = RecoveryPhrase(["otter", "lantern", "a", "b", "c", "d"]);
      expect(p.matches(1, "  Lantern "), isTrue);
      expect(p.matches(1, "lanterns"), isFalse);
    });
    test("typed phrases are tried as typed and normalised", () {
      expect(SecureSetupController.candidates("  Otter  Lantern\nmaple "), [
        "  Otter  Lantern\nmaple ",
        "Otter  Lantern\nmaple",
        "otter lantern maple"
      ]);
      expect(SecureSetupController.candidates("CaseMatters"),
          ["CaseMatters", "casematters"]);
    });
  });

  group("password strength", () {
    test("short and common are too easy", () {
      expect(PasswordStrength.score("abc"), 0);
      expect(PasswordStrength.score("password123"), 0);
      expect(PasswordStrength.score("12345678901"), 0);
    });
    test("long sentences are strong", () {
      expect(PasswordStrength.score("my cat sleeps on the radiator"), 4);
      expect(
          PasswordStrength.acceptable("my cat sleeps on the radiator"), isTrue);
    });
    test("short mixed is okay at best", () {
      expect(PasswordStrength.score("Tr0ub4dor&3"), 2);
    });
  });

  test("login password memory", () {
    LoginPasswordMemory.remember("@a:x", "hunter22");
    expect(LoginPasswordMemory.isLoginPassword("@a:x", "hunter22"), isTrue);
    expect(LoginPasswordMemory.isLoginPassword("@a:x", "other"), isFalse);
    expect(LoginPasswordMemory.isLoginPassword("@b:x", "hunter22"), isNull);
    LoginPasswordMemory.forget("@a:x");
    expect(LoginPasswordMemory.isLoginPassword("@a:x", "hunter22"), isNull);
  });

  test("check-in schedule", () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    final r = SecureSetupRecords("@a:x");
    final t0 = DateTime(2026, 10, 9);
    expect(r.checkInDue(now: t0), isFalse, reason: "never confirmed");
    await r.confirmed(now: t0, firstTime: true);
    expect(r.checkInDue(now: t0.add(const Duration(days: 2))), isFalse);
    expect(r.checkInDue(now: t0.add(const Duration(days: 3))), isTrue);
    await r.snoozed(now: t0.add(const Duration(days: 3)));
    expect(r.checkInDue(now: t0.add(const Duration(days: 5))), isFalse);
    await r.confirmed(now: t0.add(const Duration(days: 7)));
    expect(r.checkInDue(now: t0.add(const Duration(days: 30))), isFalse);
    expect(r.checkInDue(now: t0.add(const Duration(days: 37))), isTrue);
    await r.setSkipped(true);
    expect(r.skipped, isTrue);
  });
}
