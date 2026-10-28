// Vommet: local data encryption (review 1): a database that doesn't open is
// only called damaged (and offered for Reset, or rebuilt) when it is seen
// damaged twice; anything else that fails (busy, locked, can't open) is
// transient and left alone. Kept copies on Android go where the backup
// rules exclude them.
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/security/local_data_on_disk.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Uint8List keyOf(int seed) =>
    Uint8List.fromList(List.generate(32, (i) => (i * 7 + seed) & 0xff));

void main() {
  late Directory dir;
  const fast = [Duration.zero, Duration.zero, Duration.zero];

  setUp(() async {
    dir = await Directory(p.join(Directory.current.path, ".dart_tool"))
        .createTemp("local_data_on_disk_test_");
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  String path(String name) => p.join(dir.path, name);

  group("checkOpens", () {
    test("the right key opens it", () async {
      EncryptedOpen.open(path("a.db"), key: keyOf(1))
        ..execute("CREATE TABLE t (x)")
        ..close();
      expect(
          await LocalDataOnDisk.checkOpens(path("a.db"), keyOf(1),
              backoff: fast),
          DatabaseOpenCheck.ok);
    });

    test("a wrong key or garbage is damaged", () async {
      EncryptedOpen.open(path("a.db"), key: keyOf(1))
        ..execute("CREATE TABLE t (x)")
        ..close();
      expect(
          await LocalDataOnDisk.checkOpens(path("a.db"), keyOf(2),
              backoff: fast),
          DatabaseOpenCheck.corrupt);
      File(path("g.db")).writeAsBytesSync(List.filled(8192, 0x5a));
      expect(
          await LocalDataOnDisk.checkOpens(path("g.db"), keyOf(1),
              backoff: fast),
          DatabaseOpenCheck.corrupt);
    });

    test("a failure that may pass isn't damaged", () async {
      // A folder where the file should be: SQLite can't open it.
      Directory(path("d.db")).createSync();
      expect(
          await LocalDataOnDisk.checkOpens(path("d.db"), keyOf(1),
              backoff: fast),
          DatabaseOpenCheck.transient);
    });

    test("a file that comes right while it is tried again opens", () async {
      Directory(path("late.db")).createSync();
      var waited = 0;
      final check = LocalDataOnDisk.checkOpens(path("late.db"), keyOf(1),
          backoff: List.filled(4, const Duration(milliseconds: 50)));
      // Fix the file up after the first try.
      Future<void>.delayed(const Duration(milliseconds: 10), () {
        waited++;
        Directory(path("late.db")).deleteSync();
        EncryptedOpen.open(path("late.db"), key: keyOf(1))
          ..execute("CREATE TABLE t (x)")
          ..close();
      });
      expect(await check, DatabaseOpenCheck.ok);
      expect(waited, 1);
    });
  });

  test("kept copies on Android go to vommet-kept, elsewhere next to db", () {
    const db = "/data/user/0/im.nether.chat/files/db";
    expect(LocalDataOnDisk.keptCopyParent(db, android: true),
        "/data/user/0/im.nether.chat/files/vommet-kept");
    expect(
        LocalDataOnDisk.keptCopyParent("/home/u/.local/share/v/db",
            android: false),
        "/home/u/.local/share/v");
  });

  test("Android backups leave out the databases and the kept copies", () {
    const dir = "android/app/src/main/res/xml";
    final backup =
        File(p.join(dir, "vommet_backup_rules.xml")).readAsStringSync();
    final extraction = File(p.join(dir, "vommet_data_extraction_rules.xml"))
        .readAsStringSync();
    bool excludes(String section, String path) => section.contains(
        RegExp('<exclude domain="file" path="${RegExp.escape(path)}" />'));
    String part(String xml, String tag) =>
        RegExp("<$tag>([\\s\\S]*?)</$tag>").firstMatch(xml)!.group(1)!;
    for (final section in [
      part(backup, "full-backup-content"),
      part(extraction, "cloud-backup"),
      part(extraction, "device-transfer"),
    ]) {
      expect(excludes(section, "db/"), isTrue);
      expect(excludes(section, "vommet-kept/"), isTrue);
    }
  });

  test("Start over with a copy: the key files stay out of the copy", () async {
    final kept = path("kept/keys");
    final live = path("db/keys");
    Directory(kept).createSync(recursive: true);
    for (final name in [
      "master.key",
      "master.key.archived-1",
      "keystore.json",
      "data_encryption.json",
    ]) {
      File(p.join(kept, name)).writeAsStringSync(name);
    }
    // One already in the live folder is never written over.
    Directory(live).createSync(recursive: true);
    File(p.join(live, "master.key.archived-1")).writeAsStringSync("live");

    expect(await LocalDataOnDisk.moveKeyFilesBack(kept, live), 1);
    expect(File(p.join(live, "master.key")).readAsStringSync(), "master.key");
    expect(
        File(p.join(live, "master.key.archived-1")).readAsStringSync(), "live");
    expect(File(p.join(kept, "master.key")).existsSync(), isFalse);
    // The copy keeps its keystore.json (salts, check value) and setting.
    expect(File(p.join(kept, "keystore.json")).existsSync(), isTrue);
    expect(File(p.join(kept, "data_encryption.json")).existsSync(), isTrue);
    expect(LocalDataOnDisk.isKeyFile("master.dpapi"), isTrue);
    expect(LocalDataOnDisk.isKeyFile("master.wrapped.tmp"), isTrue);
    expect(LocalDataOnDisk.isKeyFile("keystore.json"), isFalse);
  });
}
