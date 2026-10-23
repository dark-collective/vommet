// Recovery key check-ins shared across the user's Vommet devices: the
// schedule's merge rules, its encryption (a pure-Dart copy of the secret
// storage construction, since the SDK's needs the native library), the
// migration from the separate local values, "put off 3 times", the
// Settings switch (no flip before the warning is answered), the check-in's
// wording per setup method, and reading a recovery key from a file.

import 'dart:convert';
import 'dart:math';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/recovery_checkins_sync.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/pages/secure_setup/recovery_key_file.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_gate.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/recovery_checkins_row.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' show EventTypes;
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';

/// SSSS's construction in pure Dart: HKDF-SHA256 (8 zero bytes of salt) of
/// the key into an AES-256-CTR key and an HMAC-SHA256 key.
class _DartCipher extends CheckInCipher {
  static (Uint8List, Uint8List) _keys(Uint8List key, String info) {
    final prk = crypto.Hmac(crypto.sha256, Uint8List(8)).convert(key).bytes;
    final t1 = crypto.Hmac(crypto.sha256, prk)
        .convert([...utf8.encode(info), 1]).bytes;
    final t2 = crypto.Hmac(crypto.sha256, prk)
        .convert([...t1, ...utf8.encode(info), 2]).bytes;
    return (Uint8List.fromList(t1), Uint8List.fromList(t2));
  }

  static Uint8List _ctr(Uint8List key, Uint8List iv, Uint8List data) {
    final c = pc.CTRStreamCipher(pc.AESEngine())
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return c.process(data);
  }

  @override
  Future<EncryptedContent> encrypt(
      String plain, Uint8List key, String info) async {
    final (aes, hmac) = _keys(key, info);
    final rng = Random.secure();
    final iv = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    iv[8] &= 0x7f;
    final ct = _ctr(aes, iv, Uint8List.fromList(utf8.encode(plain)));
    final mac = crypto.Hmac(crypto.sha256, hmac).convert(ct).bytes;
    return EncryptedContent(
        iv: base64.encode(iv),
        ciphertext: base64.encode(ct),
        mac: base64.encode(mac));
  }

  @override
  Future<String> decrypt(
      EncryptedContent data, Uint8List key, String info) async {
    final (aes, hmac) = _keys(key, info);
    final ct = base64.decode(data.ciphertext);
    final mac =
        base64.encode(crypto.Hmac(crypto.sha256, hmac).convert(ct).bytes);
    if (mac.replaceAll("=", "") != data.mac.replaceAll("=", "")) {
      throw Exception("Bad MAC");
    }
    return utf8.decode(_ctr(aes, base64.decode(data.iv), ct));
  }
}

class _MatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Uint8List _key(int seed) =>
    Uint8List.fromList(List.generate(32, (i) => (i * 7 + seed) & 0xff));

void main() {
  final t0 = DateTime(2026, 10, 21, 9);
  const day = Duration(days: 1);
  DateTime d(int days) => t0.add(day * days);
  var n = 0;

  Future<void> prefs([Map<String, Object> values = const {}]) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(values);
    Preference.preferences = await SharedPreferences.getInstance();
  }

  setUp(() => prefs());

  /// Both ways round, and the merge is the same.
  CheckInState merge(CheckInState a, CheckInState b) {
    final ab = CheckInState.merge(a, b), ba = CheckInState.merge(b, a);
    expect(ab, ba, reason: "order doesn't matter");
    expect(CheckInState.merge(ab, a), ab, reason: "merging again: no change");
    expect(CheckInState.merge(ab, b), ab, reason: "merging again: no change");
    return ab;
  }

  group("merge rules", () {
    test("the newest pass wins, with its streak and next check", () {
      final a = CheckInState(lastPass: d(0), streak: 1, passDue: d(30));
      final b = CheckInState(lastPass: d(40), streak: 2, passDue: d(130));
      final m = merge(a, b);
      expect(m.lastPass, d(40));
      expect(m.streak, 2);
      expect(m.due, d(130));
    });

    test("the same pass seen twice: the lower streak, then the later check",
        () {
      expect(
          merge(CheckInState(lastPass: d(0), streak: 3, passDue: d(180)),
                  CheckInState(lastPass: d(0), streak: 1, passDue: d(30)))
              .streak,
          1);
      expect(
          merge(CheckInState(lastPass: d(0), streak: 1, passDue: d(30)),
                  CheckInState(lastPass: d(0), streak: 1, passDue: d(31)))
              .due,
          d(31));
    });

    test("a failure after the last pass resets the streak everywhere", () {
      final passed = CheckInState(lastPass: d(0), streak: 2, passDue: d(90));
      final failed = CheckInState(
          lastPass: d(0), streak: 2, passDue: d(90), failedAt: d(5));
      final m = merge(passed, failed);
      expect(m.currentStreak, 0);
      // A later pass ends the reset.
      final again =
          merge(m, CheckInState(lastPass: d(10), streak: 1, passDue: d(40)));
      expect(again.currentStreak, 1);
    });

    test("a setup after the last pass: first check 2 weeks later, streak 0",
        () {
      final passed = CheckInState(lastPass: d(0), streak: 2, passDue: d(90));
      final setUp = CheckInState(setupAt: d(20));
      final m = merge(passed, setUp);
      expect(m.due, d(34));
      expect(m.currentStreak, 0);
      // A setup before the pass changes nothing.
      expect(merge(passed, CheckInState(setupAt: d(-5))).due, d(90));
    });

    test("snoozes after the last pass carry across, older ones don't", () {
      final shared = CheckInState(lastPass: d(0), streak: 1, passDue: d(30));
      final a = shared.copyWith(snoozedAt: d(30), snoozes: 1);
      final b = shared.copyWith(snoozedAt: d(33), snoozes: 2);
      final m = merge(a, b);
      expect(m.snoozesInRow, 2);
      expect(m.due, d(36), reason: "3 days after the newest snooze");
      final passedAfter =
          merge(m, CheckInState(lastPass: d(34), streak: 2, passDue: d(124)));
      expect(passedAfter.snoozesInRow, 0, reason: "a pass ends the run");
      expect(passedAfter.due, d(124));
    });

    test("on/off: the newest change wins; the same time goes to on", () {
      final off = CheckInState(enabled: false, enabledAt: d(5));
      final on = CheckInState(enabled: true, enabledAt: d(3));
      expect(merge(off, on).enabled, false);
      expect(merge(off, CheckInState(enabled: true, enabledAt: d(6))).enabled,
          true);
      expect(merge(off, CheckInState(enabled: true, enabledAt: d(5))).enabled,
          true);
      expect(merge(off, const CheckInState()).enabled, false,
          reason: "never changed: the default doesn't count as a change");
    });

    test("setup method: the newest wins; the same time picks one either way",
        () {
      final key = CheckInState(method: RecoveryMethod.key, methodAt: d(0));
      final phrase =
          CheckInState(method: RecoveryMethod.phrase, methodAt: d(9));
      expect(merge(key, phrase).method, RecoveryMethod.phrase);
      expect(merge(key, const CheckInState()).method, RecoveryMethod.key);
      merge(key, CheckInState(method: RecoveryMethod.password, methodAt: d(0)));
    });

    test("empty merges to the other side", () {
      final s = CheckInState(
          lastPass: d(0),
          streak: 1,
          passDue: d(30),
          method: RecoveryMethod.password,
          methodAt: d(-3),
          setupAt: d(-3));
      expect(merge(s, const CheckInState()), s);
      expect(const CheckInState().isEmpty, true);
    });

    test("JSON round trip; junk and unknown versions are absent", () {
      final s = CheckInState(
          lastPass: d(0),
          streak: 2,
          passDue: d(90),
          setupAt: d(-40),
          failedAt: d(-20),
          snoozedAt: d(91),
          snoozes: 1,
          enabled: false,
          enabledAt: d(92),
          method: RecoveryMethod.phrase,
          methodAt: d(-40));
      expect(CheckInState.fromJson(jsonDecode(jsonEncode(s.toJson()))), s);
      expect(CheckInState.fromJson("nope"), isNull);
      expect(CheckInState.fromJson({"streak": 1}), isNull);
      expect(CheckInState.fromJson({"version": 0}), isNull);
    });
  });

  group("encryption", () {
    // ignore: invalid_use_of_visible_for_testing_member
    setUp(() => RecoveryCheckInsSync.cipher = _DartCipher());
    // ignore: invalid_use_of_visible_for_testing_member
    tearDown(() => RecoveryCheckInsSync.cipher = const SsssCheckInCipher());

    final state = CheckInState(
        lastPass: DateTime(2026, 10, 21), streak: 1, passDue: d(30));

    test("round trip with the backup key; the server sees no fields", () async {
      final sealed = await RecoveryCheckInsSync.seal(state, _key(1));
      expect(sealed["algorithm"], RecoveryCheckInsSync.algorithm);
      expect(sealed["version"], CheckInState.version);
      expect(sealed.keys.toSet(),
          {"version", "algorithm", "iv", "ciphertext", "mac"});
      expect(jsonEncode(sealed), isNot(contains("last_pass")));
      expect(await RecoveryCheckInsSync.open(sealed, _key(1)), state);
    });

    test("another key (a rotated backup), tampering, junk: absent", () async {
      final sealed = await RecoveryCheckInsSync.seal(state, _key(1));
      expect(await RecoveryCheckInsSync.open(sealed, _key(2)), isNull);
      final ct = base64.decode(sealed["ciphertext"] as String);
      ct[0] ^= 1;
      expect(
          await RecoveryCheckInsSync.open(
              {...sealed, "ciphertext": base64.encode(ct)}, _key(1)),
          isNull);
      expect(
          await RecoveryCheckInsSync.open(
              {...sealed, "algorithm": "m.secret_storage.v1.aes-hmac-sha2"},
              _key(1)),
          isNull);
      expect(await RecoveryCheckInsSync.open({"iv": 1}, _key(1)), isNull);
      expect(await RecoveryCheckInsSync.open(null, _key(1)), isNull);
    });

    test("not the secret storage's own key: another info string", () async {
      expect(RecoveryCheckInsSync.info, isNot(""));
      expect(RecoveryCheckInsSync.info, isNot(EventTypes.MegolmBackup));
      final sealed = await RecoveryCheckInsSync.seal(state, _key(1));
      // The same key under another info string doesn't open it.
      await expectLater(
          () => _DartCipher().decrypt(
              EncryptedContent(
                  iv: sealed["iv"] as String,
                  ciphertext: sealed["ciphertext"] as String,
                  mac: sealed["mac"] as String),
              _key(1),
              EventTypes.MegolmBackup),
          throwsException);
    });
  });

  group("local copy", () {
    test("migrates from the separate values of an older Vommet", () async {
      await prefs({
        "vommet_secure_confirmed_@old:x": d(0).millisecondsSinceEpoch,
        "vommet_secure_checkin_due_@old:x": d(90).millisecondsSinceEpoch,
        "vommet_secure_checkin_streak_@old:x": 2
      });
      final r = SecureSetupRecords("@old:x");
      expect(r.state.lastPass, d(0));
      expect(r.state.streak, 2);
      expect(r.nextCheckInAt, d(90));
      expect(r.checkInsEnabled, true);
      expect(r.method, isNull, reason: "neutral wording");
      // Saving keeps the separate values for an older Vommet.
      await r.confirmed(now: d(90));
      expect(Preference.preferences!.getInt("vommet_secure_checkin_due_@old:x"),
          d(270).millisecondsSinceEpoch);
      expect(
          Preference.preferences!.getInt("vommet_secure_checkin_streak_@old:x"),
          3);
    });

    test("migrated and shared copies merge", () async {
      await prefs({
        "vommet_secure_confirmed_@mig:x": d(0).millisecondsSinceEpoch,
        "vommet_secure_checkin_due_@mig:x": d(30).millisecondsSinceEpoch,
        "vommet_secure_checkin_streak_@mig:x": 1
      });
      final r = SecureSetupRecords("@mig:x");
      expect(
          await r
              .adopt(CheckInState(lastPass: d(25), streak: 2, passDue: d(115))),
          true);
      expect(r.nextCheckInAt, d(115));
      expect(await r.adopt(r.state), false, reason: "nothing new");
    });

    test("no records at all: nothing scheduled", () {
      expect(SecureSetupRecords("@new${n++}:x").checkInDue(now: d(400)), false);
    });

    test("approval adopts, it isn't a pass", () async {
      final here = SecureSetupRecords("@ap:x", deviceScope: "new");
      final shared = CheckInState(
          lastPass: d(0),
          streak: 2,
          passDue: d(90),
          method: RecoveryMethod.phrase,
          methodAt: d(-50));
      await here.adopt(shared);
      expect(here.lastConfirmed, d(0), reason: "no new pass");
      expect(here.nextCheckInAt, d(90));
      expect(here.method, RecoveryMethod.phrase);
    });

    test("turned off: never due; on again: as scheduled", () async {
      final r = SecureSetupRecords("@off${n++}:x");
      await r.setUp(method: RecoveryMethod.key, now: d(0));
      expect(r.checkInDue(now: d(14)), true);
      await r.setCheckInsEnabled(false, now: d(1));
      expect(r.checkInDue(now: d(400)), false);
      await r.setCheckInsEnabled(true, now: d(2));
      expect(r.checkInDue(now: d(14)), true);
    });
  });

  group("put off 3 times", () {
    test("the 4th check-in can't be put off; a pass starts over", () async {
      final r = SecureSetupRecords("@ult${n++}:x");
      await r.setUp(method: RecoveryMethod.key, now: d(0));
      for (var i = 0; i < 3; i++) {
        expect(r.ultimatum, false);
        await r.snoozed(now: d(14 + 3 * i));
      }
      expect(r.snoozesInRow, 3);
      expect(r.ultimatum, true);
      expect(r.checkInDue(now: d(23)), true);
      await r.confirmed(now: d(23));
      expect(r.ultimatum, false);
    });

    test("counted across devices", () async {
      final a = SecureSetupRecords("@both:x", deviceScope: "a");
      final b = SecureSetupRecords("@both:x", deviceScope: "b");
      await a.setUp(method: RecoveryMethod.key, now: d(0));
      await b.adopt(a.state);
      await a.snoozed(now: d(14));
      await b.adopt(a.state);
      await b.snoozed(now: d(17));
      await a.adopt(b.state);
      await a.snoozed(now: d(20));
      await b.adopt(a.state);
      expect(b.snoozesInRow, 3);
      expect(b.ultimatum, true);
      expect(b.nextCheckInAt, d(23));
    });

    test("a new key starts over", () async {
      final r = SecureSetupRecords("@ult${n++}:x");
      await r.setUp(now: d(0));
      for (var i = 0; i < 3; i++) {
        await r.snoozed(now: d(14 + i));
      }
      expect(r.ultimatum, true);
      await r.setUp(method: RecoveryMethod.phrase, now: d(10));
      expect(r.ultimatum, false);
    });
  });

  group("Settings switch", () {
    late SecureSetupRecords r;

    Future<void> pump(WidgetTester tester) async {
      r = SecureSetupRecords("@sw${n++}:x");
      await r.setUp(method: RecoveryMethod.key, now: DateTime(2027, 4, 1));
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ListView(children: [RecoveryCheckInsRow(r)]))));
      await tester.pump();
    }

    bool switchOn(WidgetTester tester) =>
        tester.widget<Switch>(find.byType(Switch)).value;

    testWidgets("on: next check, explainer collapsed until asked",
        (tester) async {
      await pump(tester);
      expect(find.text("Recovery key check-ins"), findsOneWidget);
      expect(find.text("Next check: around April 2027"), findsOneWidget);
      expect(find.text("How often Vommet asks"), findsNothing);
      await tester.tap(find.text("How often?"));
      await tester.pump();
      expect(find.text("How often Vommet asks"), findsOneWidget);
      expect(find.text("After that, about twice a year."), findsOneWidget);
    });

    testWidgets("off only after the hold; no flip before; on again directly",
        (tester) async {
      await pump(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text("Turn off check-ins?"), findsOneWidget);
      expect(switchOn(tester), true, reason: "no flip while asking");
      expect(r.checkInsEnabled, true);

      // Kept on.
      await tester.tap(find.text("Keep check-ins on"));
      await tester.pumpAndSettle();
      expect(find.text("Turn off check-ins?"), findsNothing);
      expect(switchOn(tester), true);
      expect(r.checkInsEnabled, true);

      // A short press of the hold button does nothing.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      final hold = find.text("Hold to turn off");
      var g = await tester.startGesture(tester.getCenter(hold));
      await tester.pump(const Duration(milliseconds: 500));
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text("Turn off check-ins?"), findsOneWidget);
      expect(r.checkInsEnabled, true);

      // Held: off.
      g = await tester.startGesture(tester.getCenter(hold));
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text("Turn off check-ins?"), findsNothing);
      expect(r.checkInsEnabled, false);
      expect(switchOn(tester), false);
      expect(find.text("Off. Vommet won't check that you still have your key."),
          findsOneWidget);
      expect(find.textContaining("Not recommended."), findsOneWidget);
      expect(find.textContaining("Next check"), findsNothing);

      // Back on: no dialog.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(r.checkInsEnabled, true);
      expect(switchOn(tester), true);
    });
  });

  group("check-in dialog", () {
    String? result;
    late List<String> checked;

    Future<void> open(WidgetTester tester,
        {RecoveryMethod? method,
        bool ultimatum = false,
        String? file,
        bool keyIsRight = false}) async {
      result = "not closed";
      checked = [];
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () async => result =
                          await showCheckInDialogForTest(
                              context, _MatrixClient(),
                              method: method,
                              ultimatum: ultimatum,
                              pickFile: () async => file,
                              check: (k) async {
                                checked.add(k);
                                return keyIsRight;
                              }),
                      child: const Text("open"))))));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();
    }

    Future<void> enterWrong(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), "nope");
      await tester.tap(find.text("Check"));
      await tester.pumpAndSettle();
    }

    final wording = {
      RecoveryMethod.key: (
        "Still have your recovery key?",
        "Recovery key",
        "That's not it. Check your password manager has the whole key."
      ),
      RecoveryMethod.phrase: (
        "Still remember your recovery phrase?",
        "Recovery phrase (6 words)",
        "That's not it. Check the words and their order. If you saved them in a password manager, look there."
      ),
      RecoveryMethod.password: (
        "Still remember your recovery password?",
        "Recovery password",
        "That's not it. Capitals count. If you saved it in a password manager, look there."
      ),
      null: (
        "Can you still unlock your messages?",
        "Recovery key, phrase, or password",
        "That didn't work. Check for typos, or try your recovery key if you used a phrase (or the other way round)."
      )
    };
    for (final e in wording.entries) {
      testWidgets("worded for ${e.key?.name ?? "an unknown method"}",
          (tester) async {
        final (title, label, wrong) = e.value;
        await open(tester, method: e.key);
        expect(find.text(title), findsOneWidget);
        expect(find.text(label), findsOneWidget);
        final fileOption = e.key == null || e.key == RecoveryMethod.key;
        expect(find.text("Open a file"),
            fileOption ? findsOneWidget : findsNothing);
        expect(find.text("Have a recovery key or key file instead?"),
            fileOption ? findsNothing : findsOneWidget);
        expect(find.text("Remind me later"), findsOneWidget);
        await enterWrong(tester);
        expect(find.text(wrong), findsOneWidget);
      });
    }

    testWidgets("phrase: switch to a key or file", (tester) async {
      await open(tester, method: RecoveryMethod.phrase);
      await tester.tap(find.text("Have a recovery key or key file instead?"));
      await tester.pumpAndSettle();
      expect(find.text("Can you still unlock your messages?"), findsOneWidget);
      expect(find.text("Open a file"), findsOneWidget);
    });

    testWidgets("put off 3 times: no later, no dismissing, Settings link",
        (tester) async {
      await open(tester, method: RecoveryMethod.key, ultimatum: true);
      expect(find.text("You've put this off 3 times"), findsOneWidget);
      expect(find.text("Remind me later"), findsNothing);
      await tester.tapAt(const Offset(5, 5)); // the barrier
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(
          find.text("Rather not be asked? Turn off check-ins in Settings"));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(result, "settings");
    });

    testWidgets("not put off yet: closes on a tap outside (later)",
        (tester) async {
      await open(tester, method: RecoveryMethod.key);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(result, isNull);
    });

    final validKey = SSSS.encodeRecoveryKey(_key(3));

    testWidgets("a key file: checked", (tester) async {
      await open(tester,
          method: RecoveryMethod.key,
          file: "Recovery key:\n$validKey\n",
          keyIsRight: true);
      await tester.tap(find.text("Open a file"));
      await tester.pump();
      expect(checked, [validKey]);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(result, "ok");
    });

    testWidgets("a key export: told so, not checked", (tester) async {
      await open(tester,
          file: "-----BEGIN MEGOLM SESSION DATA-----\nAbc=\n"
              "-----END MEGOLM SESSION DATA-----\n");
      await tester.tap(find.text("Open a file"));
      await tester.pumpAndSettle();
      expect(find.textContaining("That's a key export"), findsOneWidget);
      expect(checked, isEmpty);
    });

    testWidgets("no key in the file / nothing picked", (tester) async {
      await open(tester, file: "my shopping list");
      await tester.tap(find.text("Open a file"));
      await tester.pumpAndSettle();
      expect(
          find.text("There's no recovery key in that file."), findsOneWidget);
      expect(checked, isEmpty);
    });
  });

  group("recovery key file", () {
    final key = SSSS.encodeRecoveryKey(_key(5));
    final compact = key.replaceAll(" ", "");

    test("a text file with just the key", () {
      final r = RecoveryKeyFile.parse("$key\n");
      expect(r.kind, RecoveryKeyFileKind.key);
      expect(r.key, key);
    });

    test("Element's recovery-key.txt: grouped, split over lines", () {
      final groups = key.split(" ");
      final text = "${groups.sublist(0, 6).join(" ")}\n"
          "${groups.sublist(6).join(" ")}\n";
      final r = RecoveryKeyFile.parse(text);
      expect(r.kind, RecoveryKeyFileKind.key);
      expect(r.key!.replaceAll(" ", ""), compact);
    });

    test("ungrouped, with text around it", () {
      final r = RecoveryKeyFile.parse("My Element key. Everything: $compact "
          "(saved 2026-10-21)");
      expect(r.key!.replaceAll(" ", ""), compact);
    });

    test("a typo is still offered (reported as a wrong key)", () {
      final i = compact.length - 3;
      final typo =
          compact.replaceRange(i, i + 1, compact[i] == "a" ? "b" : "a");
      final r = RecoveryKeyFile.parse(typo);
      expect(r.kind, RecoveryKeyFileKind.key);
      expect(r.key!.replaceAll(" ", ""), typo);
    });

    test("a Megolm key export", () {
      expect(
          RecoveryKeyFile.parse("-----BEGIN MEGOLM SESSION DATA-----\nQUJD\n"
                  "-----END MEGOLM SESSION DATA-----")
              .kind,
          RecoveryKeyFileKind.keyExport);
    });

    test("an empty file, or one without a key", () {
      expect(RecoveryKeyFile.parse("").kind, RecoveryKeyFileKind.none);
      expect(RecoveryKeyFile.parse("Everything is fine").kind,
          RecoveryKeyFileKind.none);
    });
  });
}
