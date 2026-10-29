// Vommet: local data encryption, the one-time migration (phase 4). A
// plaintext database is copied encrypted, verified and swapped in, with its
// data, user_version, FTS5 index and triggers intact; a kill before any step
// leaves a whole copy and the next run finishes the job; not enough space,
// a full disk, a damaged source, a write during the copy or a failed rename
// keep the plaintext as it was; the leftover plaintext is overwritten before
// it is deleted; errors never carry the key.
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/security/migration/database_migration.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

Uint8List keyOf(int seed) =>
    Uint8List.fromList(List.generate(32, (i) => (i * 7 + seed) & 0xff));

String hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, "0")).join();

/// A plaintext database like data.db: WAL, user_version, FTS5 trigram with
/// triggers, an index.
void makePlain(String path, {int rows = 300}) {
  final db = sqlite3.open(path);
  db.execute("PRAGMA journal_mode = wal");
  db.execute("PRAGMA user_version = 7");
  db.execute("CREATE TABLE events (id INTEGER PRIMARY KEY, room TEXT, "
      "body TEXT)");
  db.execute("CREATE INDEX events_room ON events (room)");
  db.execute("CREATE VIRTUAL TABLE events_fts USING fts5(body, "
      "content='events', content_rowid='id', tokenize='trigram')");
  db.execute("CREATE TRIGGER events_ai AFTER INSERT ON events BEGIN "
      "INSERT INTO events_fts(rowid, body) VALUES (new.id, new.body); END");
  final insert = db.prepare("INSERT INTO events (room, body) VALUES (?, ?)");
  for (var i = 0; i < rows; i++) {
    insert.execute(["!room${i % 5}", "message number $i about migration"]);
  }
  insert.close();
  db.execute("INSERT INTO events (room, body) VALUES ('!late', 'in the wal')");
  db.close();
}

void expectEncryptedCopy(String path, Uint8List key, {int rows = 300}) {
  expect(EncryptedOpen.fileState(path), DatabaseFileState.encrypted);
  final db = EncryptedOpen.open(path, key: key);
  try {
    expect(db.select("PRAGMA user_version").first.values.first, 7);
    expect(db.select("SELECT count(*) AS n FROM events").first["n"], rows + 1);
    expect(
        db
            .select("SELECT count(*) AS n FROM events_fts "
                "WHERE events_fts MATCH 'number 12'")
            .first["n"],
        greaterThan(0));
    expect(
        db
            .select("SELECT count(*) AS n FROM sqlite_master "
                "WHERE type IN ('index', 'trigger')")
            .first["n"],
        2);
    // Still writable, and the trigger still runs (rolled back: the file is
    // checked again after a resumed run).
    db.execute("BEGIN");
    db.execute("INSERT INTO events (room, body) VALUES ('!x', 'after')");
    expect(
        db
            .select("SELECT count(*) AS n FROM events_fts "
                "WHERE events_fts MATCH 'after'")
            .first["n"],
        1);
    db.execute("ROLLBACK");
    expect(db.select("PRAGMA quick_check").first.values.first, "ok");
  } finally {
    db.close();
  }
}

void main() {
  late Directory dir;
  late String db;
  final key = keyOf(3);

  setUp(() async {
    dir = await Directory(p.join(Directory.current.path, ".dart_tool"))
        .createTemp("database_migration_test_");
    db = p.join(dir.path, "data.db");
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  List<String> files() =>
      dir.listSync().map((e) => p.basename(e.path)).toList()..sort();

  test("a plaintext database is encrypted with its data intact", () async {
    makePlain(db);
    final fractions = <double>[];
    final outcome =
        await DatabaseMigrator().migrate(db, key, onProgress: fractions.add);
    expect(outcome.result, MigrationResult.encrypted);
    expectEncryptedCopy(db, key);
    expect(fractions.last, 1);
    // Only the database is left (no temp file, no plaintext copy).
    expect(files().where((f) => f.contains("plain-old") || f.contains("tmp")),
        isEmpty);
    expect(() => EncryptedOpen.open(db, key: keyOf(4)),
        throwsA(isA<DatabaseKeyError>()));
  });

  test("the copy is 0600 and has no plaintext header", () async {
    makePlain(db);
    await DatabaseMigrator(useIsolate: false).migrate(db, key);
    final head = File(db).openSync()..setPositionSync(0);
    final bytes = head.readSync(16);
    head.closeSync();
    expect(bytes, isNot(EncryptedOpen.plaintextHeader));
    if (!Platform.isWindows) {
      expect(File(db).statSync().mode & 0x1ff, 0x180); // 0600
    }
  });

  test("encrypted and missing files are left alone", () async {
    expect((await DatabaseMigrator().migrate(db, key)).result,
        MigrationResult.missing);
    final enc = EncryptedOpen.open(db, key: key);
    enc.execute("CREATE TABLE t (x)");
    enc.close();
    final before = File(db).readAsBytesSync();
    expect((await DatabaseMigrator().migrate(db, key)).result,
        MigrationResult.alreadyEncrypted);
    expect(File(db).readAsBytesSync(), before);
  });

  for (final step in MigrationStep.values) {
    test("a kill before ${step.name} loses nothing and the next run finishes",
        () async {
      makePlain(db);
      final crashing = DatabaseMigrator(
          useIsolate: false,
          beforeStep: (s, _) {
            if (s == step) throw SimulatedCrash(s);
          });
      await expectLater(
          crashing.migrate(db, key), throwsA(isA<SimulatedCrash>()));

      // Whatever the kill left, one whole copy is there: the plaintext at
      // its place or moved aside, or the encrypted one.
      final old = DatabaseMigrator.oldPath(db);
      final temp = DatabaseMigrator.tempPath(db);
      final state = EncryptedOpen.fileState(db);
      if (state == DatabaseFileState.plaintext) {
        final plain = sqlite3.open(db);
        expect(
            plain.select("SELECT count(*) AS n FROM events").first["n"], 301);
        plain.close();
      } else if (state == DatabaseFileState.missing) {
        expect(File(old).existsSync(), isTrue);
        expect(File(temp).existsSync(), isTrue);
      } else {
        expectEncryptedCopy(db, key);
      }

      final outcome = await DatabaseMigrator().migrate(db, key);
      expect(outcome.isEncrypted, isTrue, reason: "$outcome");
      expectEncryptedCopy(db, key);
      expect(File(old).existsSync(), isFalse);
      expect(File(temp).existsSync(), isFalse);
    });
  }

  test("a kill between the renames is finished by resume alone", () async {
    makePlain(db);
    await expectLater(
        DatabaseMigrator(
            useIsolate: false,
            beforeStep: (s, _) {
              if (s == MigrationStep.renameTemp) throw SimulatedCrash(s);
            }).migrate(db, key),
        throwsA(isA<SimulatedCrash>()));
    expect(File(db).existsSync(), isFalse);
    await DatabaseMigrator().resume(db);
    expectEncryptedCopy(db, key);
    expect(DatabaseMigrator.hasLeftovers(db), isFalse);
  });

  test("a plaintext copy moved aside with no encrypted one goes back",
      () async {
    makePlain(db);
    await File(db).rename(DatabaseMigrator.oldPath(db));
    await DatabaseMigrator().resume(db);
    expect(EncryptedOpen.fileState(db), DatabaseFileState.plaintext);
    expect(DatabaseMigrator.hasLeftovers(db), isFalse);
  });

  test(
      "an empty file made where the source was moved aside isn't trusted "
      "over the copies", () async {
    makePlain(db);
    final rows = sqlite3.open(db);
    final count = rows.select("SELECT count(*) AS n FROM sqlite_master");
    rows.close();
    await File(db).rename(DatabaseMigrator.oldPath(db));
    // Something opened the path meanwhile and left an empty file.
    File(db).writeAsBytesSync(const []);
    await DatabaseMigrator().resume(db);
    expect(EncryptedOpen.fileState(db), DatabaseFileState.plaintext);
    final back = sqlite3.open(db);
    expect(back.select("SELECT count(*) AS n FROM sqlite_master").first["n"],
        count.first["n"]);
    back.close();
    expect(DatabaseMigrator.hasLeftovers(db), isFalse);
  });

  test("an empty file next to a verified copy: the copy is put in place",
      () async {
    makePlain(db);
    await expectLater(
        DatabaseMigrator(
            useIsolate: false,
            beforeStep: (s, _) {
              if (s == MigrationStep.renameTemp) throw SimulatedCrash(s);
            }).migrate(db, key),
        throwsA(isA<SimulatedCrash>()));
    File(db).writeAsBytesSync(const []);
    await DatabaseMigrator().resume(db);
    expectEncryptedCopy(db, key);
    expect(DatabaseMigrator.hasLeftovers(db), isFalse);
  });

  test(
      "a file with data made next to both copies isn't trusted: the "
      "verified copy is put in place", () async {
    makePlain(db);
    await expectLater(
        DatabaseMigrator(
            useIsolate: false,
            beforeStep: (s, _) {
              if (s == MigrationStep.renameTemp) throw SimulatedCrash(s);
            }).migrate(db, key),
        throwsA(isA<SimulatedCrash>()));
    // Something opened the path meanwhile and wrote to a new database.
    sqlite3.open(db)
      ..execute("CREATE TABLE intruder (x TEXT)")
      ..execute("INSERT INTO intruder VALUES ('x')")
      ..close();
    expect(EncryptedOpen.fileState(db), DatabaseFileState.plaintext);
    await DatabaseMigrator().resume(db);
    expectEncryptedCopy(db, key);
    expect(DatabaseMigrator.hasLeftovers(db), isFalse);
  });

  test("not enough free space keeps the plaintext and says how much", () async {
    makePlain(db);
    final before = File(db).readAsBytesSync();
    final outcome =
        await DatabaseMigrator(freeSpace: (_) => 1024).migrate(db, key);
    expect(outcome.result, MigrationResult.noSpace);
    expect(outcome.bytesFree, 1024);
    expect(outcome.bytesNeeded, greaterThan(50 * 1024 * 1024));
    expect(EncryptedOpen.fileState(db), DatabaseFileState.plaintext);
    expect(File(db).readAsBytesSync(), before);
    expect(DatabaseMigrator.hasLeftovers(db), isFalse);
  });

  test("an unknown free space goes ahead", () async {
    makePlain(db);
    final outcome =
        await DatabaseMigrator(freeSpace: (_) => null).migrate(db, key);
    expect(outcome.result, MigrationResult.encrypted);
  });

  test("this machine's free space is read", () {
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) return;
    final free = DatabaseMigrator().freeSpace(dir.path);
    expect(free, isNotNull);
    expect(free, greaterThan(0));
  });

  test("a full disk while copying keeps the plaintext", () async {
    makePlain(db);
    final outcome = await DatabaseMigrator(
        useIsolate: false,
        beforeStep: (s, _) {
          if (s == MigrationStep.verify) {
            throw SqliteException(
                extendedResultCode: 13, message: "database or disk is full");
          }
        }).migrate(db, key);
    expect(outcome.result, MigrationResult.noSpace);
    expect(EncryptedOpen.fileState(db), DatabaseFileState.plaintext);
    expect(DatabaseMigrator.hasLeftovers(db), isFalse);
  });

  test("a damaged source fails, keeps it and leaves no temp file", () async {
    makePlain(db, rows: 2000);
    // Overwrite pages in the middle of the file (after the checkpoint the
    // rows are there).
    final c = sqlite3.open(db);
    c.execute("PRAGMA wal_checkpoint(TRUNCATE)");
    c.close();
    final raf = File(db).openSync(mode: FileMode.append);
    raf.setPositionSync(4096 * 2);
    raf.writeFromSync(List.filled(4096 * 6, 0x5a));
    raf.closeSync();
    final before = File(db).readAsBytesSync();

    final outcome = await DatabaseMigrator().migrate(db, key);
    expect(outcome.result, MigrationResult.failed);
    expect(outcome.step, anyOf(MigrationStep.export, MigrationStep.verify));
    expect(File(db).readAsBytesSync(), before);
    expect(DatabaseMigrator.hasLeftovers(db), isFalse);
  });

  test("a write after the copy fails the run instead of losing it", () async {
    makePlain(db);
    final outcome = await DatabaseMigrator(
        useIsolate: false,
        beforeStep: (s, path) {
          if (s == MigrationStep.deletePlainWal) {
            final other = sqlite3.open(path);
            other.execute(
                "INSERT INTO events (room, body) VALUES ('!y', 'late write')");
            other.close();
          }
        }).migrate(db, key);
    expect(outcome.result, MigrationResult.failed);
    expect(outcome.step, MigrationStep.deletePlainWal);
    final plain = sqlite3.open(db);
    expect(plain.select("SELECT count(*) AS n FROM events").first["n"], 302);
    plain.close();
    expect(DatabaseMigrator.hasLeftovers(db), isFalse);
  });

  test("errors carry no key material", () async {
    makePlain(db);
    final outcome = await DatabaseMigrator(
        useIsolate: false,
        beforeStep: (s, _) {
          if (s == MigrationStep.verify) {
            throw SqliteException(
                extendedResultCode: 1,
                message: "boom",
                causingStatement: "VACUUM INTO ?",
                parametersToStatement: ["file:x?key=x'${hexOf(key)}'"]);
          }
        }).migrate(db, key);
    expect(outcome.result, MigrationResult.failed);
    expect(outcome.toString(), isNot(contains(hexOf(key))));
    expect(outcome.toString(), isNot(contains("VACUUM")));
  });

  test("secureDelete overwrites before deleting", () async {
    final file = File(p.join(dir.path, "secret"));
    file.writeAsBytesSync(List.filled(3 * 1024 * 1024 + 5, 0x41));
    // Keep a second name for the same data to look at it after the wipe.
    final link = p.join(dir.path, "secret-link");
    if (Platform.isWindows) return;
    await Process.run("ln", [file.path, link]);
    await DatabaseMigrator.secureDelete(file.path);
    expect(file.existsSync(), isFalse);
    final left = File(link).readAsBytesSync();
    expect(left.length, 3 * 1024 * 1024 + 5);
    expect(left.every((b) => b == 0), isTrue);
  });

  group("decrypting (local data encryption turned off)", () {
    Future<void> makeEncrypted() async {
      makePlain(db);
      final outcome =
          await DatabaseMigrator(useIsolate: false).migrate(db, key);
      expect(outcome.result, MigrationResult.encrypted);
    }

    void expectPlainCopy(String path, {int rows = 300}) {
      expect(EncryptedOpen.fileState(path), DatabaseFileState.plaintext);
      final plain = sqlite3.open(path);
      try {
        expect(plain.select("PRAGMA user_version").first.values.first, 7);
        expect(plain.select("SELECT count(*) AS n FROM events").first["n"],
            rows + 1);
        expect(
            plain
                .select("SELECT count(*) AS n FROM events_fts "
                    "WHERE events_fts MATCH 'number 12'")
                .first["n"],
            greaterThan(0));
        expect(plain.select("PRAGMA quick_check").first.values.first, "ok");
      } finally {
        plain.close();
      }
    }

    test("an encrypted database is decrypted with its data intact", () async {
      await makeEncrypted();
      final fractions = <double>[];
      final outcome =
          await DatabaseMigrator().decrypt(db, key, onProgress: fractions.add);
      expect(outcome.result, MigrationResult.decrypted);
      expect(outcome.isPlain, isTrue);
      expectPlainCopy(db);
      expect(fractions.last, 1);
      expect(DatabaseMigrator.hasLeftovers(db), isFalse);
      if (!Platform.isWindows) {
        expect(File(db).statSync().mode & 0x1ff, 0x180); // 0600
      }
    });

    test("plaintext and missing files are left alone", () async {
      expect((await DatabaseMigrator().decrypt(db, key)).result,
          MigrationResult.missing);
      makePlain(db);
      final before = File(db).readAsBytesSync();
      expect((await DatabaseMigrator().decrypt(db, key)).result,
          MigrationResult.alreadyPlain);
      expect(File(db).readAsBytesSync(), before);
    });

    test("the wrong key fails and keeps the encrypted file", () async {
      await makeEncrypted();
      final before = File(db).readAsBytesSync();
      final outcome = await DatabaseMigrator().decrypt(db, keyOf(9));
      expect(outcome.result, MigrationResult.failed);
      // The file can't be read with it: damaged or wrong key.
      expect(outcome.corrupt, isTrue);
      expect(File(db).readAsBytesSync(), before);
      expect(DatabaseMigrator.hasLeftovers(db), isFalse);
      expectEncryptedCopy(db, key);
    });

    for (final step in MigrationStep.values) {
      test("a kill before ${step.name} loses nothing and the next run finishes",
          () async {
        await makeEncrypted();
        final crashing = DatabaseMigrator(
            useIsolate: false,
            beforeStep: (s, _) {
              if (s == step) throw SimulatedCrash(s);
            });
        await expectLater(
            crashing.decrypt(db, key), throwsA(isA<SimulatedCrash>()));

        final old = DatabaseMigrator.decryptOldPath(db);
        final temp = DatabaseMigrator.decryptTempPath(db);
        final state = EncryptedOpen.fileState(db);
        if (state == DatabaseFileState.encrypted) {
          expectEncryptedCopy(db, key);
        } else if (state == DatabaseFileState.missing) {
          expect(File(old).existsSync(), isTrue);
          expect(File(temp).existsSync(), isTrue);
        } else {
          expectPlainCopy(db);
        }

        final outcome = await DatabaseMigrator().decrypt(db, key);
        expect(outcome.isPlain, isTrue, reason: "$outcome");
        expectPlainCopy(db);
        expect(DatabaseMigrator.hasLeftovers(db), isFalse);
      });
    }

    test("an encrypted copy moved aside with no plaintext one goes back",
        () async {
      await makeEncrypted();
      await File(db).rename(DatabaseMigrator.decryptOldPath(db));
      await DatabaseMigrator().resume(db);
      expectEncryptedCopy(db, key);
      expect(DatabaseMigrator.hasLeftovers(db), isFalse);
    });

    test("not enough free space keeps the encrypted file", () async {
      await makeEncrypted();
      final before = File(db).readAsBytesSync();
      final outcome =
          await DatabaseMigrator(freeSpace: (_) => 1024).decrypt(db, key);
      expect(outcome.result, MigrationResult.noSpace);
      expect(File(db).readAsBytesSync(), before);
      expect(DatabaseMigrator.hasLeftovers(db), isFalse);
    });

    test("a full disk while copying keeps the encrypted file", () async {
      await makeEncrypted();
      final outcome = await DatabaseMigrator(
          useIsolate: false,
          beforeStep: (s, _) {
            if (s == MigrationStep.verify) {
              throw SqliteException(
                  extendedResultCode: 13, message: "database or disk is full");
            }
          }).decrypt(db, key);
      expect(outcome.result, MigrationResult.noSpace);
      expectEncryptedCopy(db, key);
      expect(DatabaseMigrator.hasLeftovers(db), isFalse);
    });

    test("a write after the copy fails the run instead of losing it", () async {
      await makeEncrypted();
      final outcome = await DatabaseMigrator(
          useIsolate: false,
          beforeStep: (s, path) {
            if (s == MigrationStep.deletePlainWal) {
              final other = EncryptedOpen.open(path, key: key);
              other.execute("INSERT INTO events (room, body) "
                  "VALUES ('!y', 'late write')");
              other.close();
            }
          }).decrypt(db, key);
      expect(outcome.result, MigrationResult.failed);
      expect(outcome.step, MigrationStep.deletePlainWal);
      expectEncryptedCopy(db, key, rows: 301);
      expect(DatabaseMigrator.hasLeftovers(db), isFalse);
    });

    test("errors carry no key material", () async {
      await makeEncrypted();
      final outcome = await DatabaseMigrator().decrypt(db, keyOf(9));
      expect(outcome.toString(), isNot(contains(hexOf(keyOf(9)))));
      expect(outcome.toString(), isNot(contains(hexOf(key))));
    });

    test("encrypt then decrypt round-trips", () async {
      await makeEncrypted();
      await DatabaseMigrator().decrypt(db, key);
      expect((await DatabaseMigrator().migrate(db, key)).result,
          MigrationResult.encrypted);
      expectEncryptedCopy(db, key);
    });
  });
}
