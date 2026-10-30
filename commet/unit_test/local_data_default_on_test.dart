// Vommet: local data encryption is on by default since 10-30. A new
// install (nothing stored yet) starts encrypted; the setting file records
// where an answer came from and to which generation of the question, so a
// "Not now" to the opt-in question is asked once more (never one from the
// settings switch), and never a third time.
import 'dart:io';

import 'package:commet/security/local_data_on_disk.dart';
import 'package:commet/security/local_data_setting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory(p.join(Directory.current.path, ".dart_tool"))
        .createTemp("local_data_default_on_test_");
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  String keys() => p.join(dir.path, "keys");

  group("the setting file", () {
    test("a file from before 10-30 reads as an answer to the opt-in question",
        () {
      final old =
          LocalDataSetting.parse('{"v": 1, "encrypt": false, "chosen": true}')!;
      expect(old.offer, 1);
      expect(old.source, isNull);
      expect(old.offerDue, isTrue, reason: "unknown source: asked once more");
    });

    test("source and generation are kept", () async {
      const setting =
          LocalDataSetting(encrypt: false, chosen: true, source: "settings");
      await setting.write(keys());
      final read = LocalDataSetting.read(keys());
      expect(read, setting);
      expect(read.offer, LocalDataSetting.currentOffer);
      expect(read.offerDue, isFalse);
      // Older builds still read it (same version, extra fields ignored).
      final json = File(LocalDataSetting.pathIn(keys())).readAsStringSync();
      expect(json, contains('"v": 1'));
    });

    test("who is offered", () {
      bool due(bool encrypt, bool chosen, String? source, int offer) =>
          LocalDataSetting(
                  encrypt: encrypt,
                  chosen: chosen,
                  source: source,
                  offer: offer)
              .offerDue;
      // Never answered.
      expect(LocalDataSetting.byDefault.offerDue, isTrue);
      expect(due(false, false, null, 1), isTrue);
      // "Not now" to the opt-in question: once more.
      expect(due(false, true, "first_run", 1), isTrue);
      expect(due(false, true, "notice", 1), isTrue);
      expect(due(false, true, null, 1), isTrue);
      // Turned off in the settings: an explicit decision.
      expect(due(false, true, "settings", 1), isFalse);
      expect(due(false, true, "settings", 2), isFalse);
      // Answered the current question: never a third ask.
      expect(due(false, true, "notice", 2), isFalse);
      expect(due(false, true, "first_run", 2), isFalse);
      // Encrypted.
      expect(due(true, true, "first_run", 1), isFalse);
      expect(due(true, false, null, 2), isFalse);
      expect(LocalDataSetting.newInstall.offerDue, isFalse);
    });
  });

  group("a new install", () {
    test("nothing stored and no account: new, encrypted by default", () {
      expect(
          LocalDataOnDisk.isNewInstall(dir.path, accounts: const []), isTrue);
      expect(LocalDataSetting.newInstall.encrypt, isTrue);
      expect(LocalDataSetting.newInstall.chosen, isFalse);
      // A missing folder is new too.
      expect(
          LocalDataOnDisk.isNewInstall(p.join(dir.path, "none"),
              accounts: const []),
          isTrue);
    });

    test("an account signed in: not new", () {
      expect(LocalDataOnDisk.isNewInstall(dir.path, accounts: const ["a"]),
          isFalse);
    });

    test("keystore.json there (signed out of every account): not new", () {
      Directory(keys()).createSync(recursive: true);
      File(p.join(keys(), "keystore.json")).writeAsStringSync("{}");
      expect(
          LocalDataOnDisk.isNewInstall(dir.path, accounts: const []), isFalse);
    });

    test("a setting file there: not new", () async {
      await LocalDataSetting.byDefault.write(keys());
      expect(
          LocalDataOnDisk.isNewInstall(dir.path, accounts: const []), isFalse);
    });

    test("app_data.db there (an install from before encryption): not new", () {
      final app = Directory(p.join(dir.path, "app"))
        ..createSync(recursive: true);
      File(p.join(app.path, "app_data.db")).writeAsStringSync("x");
      expect(
          LocalDataOnDisk.isNewInstall(dir.path, accounts: const []), isFalse);
    });

    test("an account folder left: not new", () {
      Directory(p.join(dir.path, "account", "drift", "client-a"))
          .createSync(recursive: true);
      expect(
          LocalDataOnDisk.isNewInstall(dir.path, accounts: const []), isFalse);
    });
  });
}
