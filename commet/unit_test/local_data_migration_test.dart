// Vommet: local data encryption, the start-up migration of an install
// (phase 4): app_data.db, data.db and search_index.db are encrypted with
// the vault's keys and then open through DatabaseKeys; a message store
// without space or failing stays plaintext (and stops being retried after
// three failures, until Try again), while the derived files are deleted to
// be made again only when damaged or after three failures; an account left
// out of a decrypting run keeps its keys; a file another engine of the process has open is skipped;
// a headless engine doesn't open a file while it is being migrated; a
// second run doesn't start while one holds the lock; forgetting an account
// makes its databases undecryptable.
import 'dart:io';

import 'package:commet/security/database_in_use.dart';
import 'package:commet/security/database_keys.dart';
import 'package:commet/security/key_vault/file_key_store.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/keystore_file.dart';
import 'package:commet/security/local_data_setting.dart';
import 'package:commet/security/migration/database_migration.dart';
import 'package:commet/security/migration/local_data_migration.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const _account = "client-a";

void makePlain(String path, {int rows = 50, int version = 3}) {
  Directory(p.dirname(path)).createSync(recursive: true);
  final db = sqlite3.open(path);
  db.execute("PRAGMA journal_mode = wal");
  db.execute("PRAGMA user_version = $version");
  db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, body TEXT)");
  for (var i = 0; i < rows; i++) {
    db.execute("INSERT INTO t (body) VALUES (?)", ["row $i"]);
  }
  db.close();
}

int rowsIn(Database db) =>
    db.select("SELECT count(*) AS n FROM t").first["n"] as int;

void main() {
  late Directory root;
  late String dbDir;
  late String keys;
  late KeyVault vault;

  KeyVault newVault({bool allowCreate = true}) => KeyVault(
        keystoreFile: KeystoreFile(keys),
        fileStore: FileKeyStore(keys),
        preferredStores: const [],
        allowCreate: allowCreate,
        noKeyringReason: "test",
      );

  String appData() => p.join(dbDir, "app", "app_data.db");
  String data([String account = _account]) =>
      p.join(dbDir, "account", "drift", account, "data.db");
  String search([String account = _account]) =>
      p.join(dbDir, "account", "drift", account, "search_index.db");

  LocalDataMigration migration(
          {DatabaseMigrator? migrator,
          List<String> accounts = const [_account],
          bool Function(String)? inUse,
          bool decrypt = false}) =>
      LocalDataMigration(
          decrypt: decrypt,
          vault: vault,
          databaseDirectory: dbDir,
          accounts: accounts,
          migrator: migrator ?? DatabaseMigrator(useIsolate: false),
          inUse: inUse ?? (_) => false);

  DatabaseMigrator failingFor(String path, {Object? error}) => DatabaseMigrator(
      useIsolate: false,
      beforeStep: (step, at) {
        if (at == path && step == MigrationStep.verify) {
          throw error ?? const MigrationError("simulated failure");
        }
      });

  setUp(() async {
    root = await Directory(p.join(Directory.current.path, ".dart_tool"))
        .createTemp("local_data_migration_test_");
    dbDir = p.join(root.path, "db");
    keys = p.join(dbDir, "keys");
    vault = newVault();
    expect((await vault.unlock()).isReady, isTrue);
    DatabaseKeys.debugVault = vault;
    LocalDataSetting.debugOverride =
        const LocalDataSetting(encrypt: true, chosen: true);
  });

  tearDown(() async {
    LocalDataSetting.debugOverride = null;
    DatabaseKeys.debugVault = null;
    DatabaseInUse.debugClear();
    await vault.dispose();
    await root.delete(recursive: true);
  });

  test("every plaintext database is encrypted and opens with its vault key",
      () async {
    makePlain(appData(), rows: 5);
    makePlain(data(), rows: 80, version: 12);
    makePlain(search(), rows: 30, version: 2);
    final m = migration();
    expect(m.needed, isTrue);

    final seen = <String>[];
    final report = await m.run(onProgress: (pr) {
      seen.add("${pr.index}/${pr.count}");
    });
    expect(report, isNotNull);
    expect(report!.allEncrypted, isTrue);
    expect(seen.first, "1/3");
    expect(seen.last, "3/3");
    expect(m.needed, isFalse);

    for (final (path, role, account, rows) in [
      (appData(), DatabaseRole.appData, null, 5),
      (data(), DatabaseRole.data, _account, 80),
      (search(), DatabaseRole.searchIndex, _account, 30),
    ]) {
      expect(EncryptedOpen.fileState(path), DatabaseFileState.encrypted);
      expect(vault.recordedState(role, account),
          DatabaseEncryptionState.encrypted);
      final key = await DatabaseKeys.forFile(path, role, account);
      final db = EncryptedOpen.open(path, key: key);
      expect(rowsIn(db), rows);
      db.close();
    }
    // Nothing left to do: a second run is a no-op.
    final again = await migration().run();
    expect(again!.outcomes, isEmpty);
  });

  test("a message store without space stays plaintext and says how much",
      () async {
    makePlain(data());
    makePlain(search());
    final report = await migration(
            migrator: DatabaseMigrator(useIsolate: false, freeSpace: (_) => 10))
        .run();
    expect(report!.bytesToFree, greaterThan(50 * 1024 * 1024));
    expect(report.allEncrypted, isFalse);
    expect(EncryptedOpen.fileState(data()), DatabaseFileState.plaintext);
    expect(vault.recordedState(DatabaseRole.data, _account),
        DatabaseEncryptionState.plain);
    // Not a damaged file: the search index is kept too (rebuilding it may
    // not get everything back), and both are retried on every start.
    expect(EncryptedOpen.fileState(search()), DatabaseFileState.plaintext);
    expect(vault.migrationFailures(DatabaseRole.data, _account), 0);
    expect(vault.migrationFailures(DatabaseRole.searchIndex, _account), 0);
  });

  test("a failing message store is retried three times, then on request",
      () async {
    makePlain(data());
    for (var i = 1; i <= 3; i++) {
      final report = await migration(migrator: failingFor(data())).run();
      expect(report!.outcomes.values.single.result, MigrationResult.failed);
      expect(vault.migrationFailures(DatabaseRole.data, _account), i);
      expect(EncryptedOpen.fileState(data()), DatabaseFileState.plaintext);
      expect(DatabaseMigrator.hasLeftovers(data()), isFalse);
    }
    final stopped = await migration().run();
    expect(stopped!.stoppedRetrying, isTrue);
    expect(stopped.skipped.single.path, data());
    expect(EncryptedOpen.fileState(data()), DatabaseFileState.plaintext);

    final retried = await migration().run(retryFailed: true);
    expect(retried!.allEncrypted, isTrue);
    expect(EncryptedOpen.fileState(data()), DatabaseFileState.encrypted);
    expect(vault.migrationFailures(DatabaseRole.data, _account), 0);
  });

  test(
      "a failing app_data.db or search index is kept and retried, then "
      "deleted to be made again after three failures", () async {
    makePlain(appData());
    makePlain(search());
    final m = DatabaseMigrator(
        useIsolate: false,
        beforeStep: (step, at) {
          if (step == MigrationStep.verify) {
            throw const MigrationError("simulated failure");
          }
        });
    for (var run = 1; run < LocalDataMigration.maxFailures; run++) {
      await migration(migrator: m).run();
      // A failure that may pass (not a damaged file): kept as it was.
      expect(EncryptedOpen.fileState(appData()), DatabaseFileState.plaintext);
      expect(EncryptedOpen.fileState(search()), DatabaseFileState.plaintext);
      expect(vault.migrationFailures(DatabaseRole.appData, null), run);
      expect(vault.migrationFailures(DatabaseRole.searchIndex, _account), run);
    }
    await migration(migrator: m).run();
    expect(File(appData()).existsSync(), isFalse);
    expect(File(search()).existsSync(), isFalse);
    expect(vault.migrationFailures(DatabaseRole.appData, null), 0);
    // Made again encrypted on the next open.
    final key =
        await DatabaseKeys.forFile(appData(), DatabaseRole.appData, null);
    expect(key, isNotNull);
  });

  test("running out of disk never makes derived data be deleted", () async {
    makePlain(search());
    final failing = DatabaseMigrator(
        useIsolate: false,
        beforeStep: (step, at) {
          if (step == MigrationStep.verify) {
            throw const MigrationError("simulated failure");
          }
        });
    for (var run = 1; run < LocalDataMigration.maxFailures; run++) {
      await migration(migrator: failing).run();
    }
    expect(vault.migrationFailures(DatabaseRole.searchIndex, _account),
        LocalDataMigration.maxFailures - 1);
    // One short of the limit, then no space, more than once: kept.
    final full = DatabaseMigrator(useIsolate: false, freeSpace: (_) => 1024);
    await migration(migrator: full).run();
    await migration(migrator: full).run();
    expect(EncryptedOpen.fileState(search()), DatabaseFileState.plaintext);
    expect(vault.migrationFailures(DatabaseRole.searchIndex, _account),
        LocalDataMigration.maxFailures - 1);
  });

  test("a damaged app_data.db or search index is deleted to be made again",
      () async {
    makePlain(appData());
    makePlain(search());
    final m = DatabaseMigrator(
        useIsolate: false,
        beforeStep: (step, at) {
          if (step == MigrationStep.verify) {
            throw const MigrationError("simulated damage", corrupt: true);
          }
        });
    await migration(migrator: m).run();
    expect(File(appData()).existsSync(), isFalse);
    expect(File(search()).existsSync(), isFalse);
  });

  test("a source SQLite reports as damaged counts as damaged", () async {
    // NOTADB while reading the file to convert: the file's fault.
    final path = data();
    Directory(p.dirname(path)).createSync(recursive: true);
    File(path).writeAsBytesSync(List.filled(8192, 7));
    final key = await vault.newDatabaseKey(DatabaseRole.data, _account);
    final outcome =
        await DatabaseMigrator(useIsolate: false).decrypt(path, key);
    expect(outcome.result, MigrationResult.failed);
    expect(outcome.corrupt, isTrue);
    // A failing check of the copy isn't.
    makePlain(search());
    final failed = await failingFor(search()).migrate(search(), key);
    expect(failed.result, MigrationResult.failed);
    expect(failed.corrupt, isFalse);
  });

  test("a file another engine of this process opened is left for later",
      () async {
    makePlain(data());
    DatabaseInUse.mark(data());
    final report = await LocalDataMigration(
            vault: vault,
            databaseDirectory: dbDir,
            accounts: const [_account],
            migrator: DatabaseMigrator(useIsolate: false))
        .run();
    expect(report!.skipped.single.path, data());
    expect(EncryptedOpen.fileState(data()), DatabaseFileState.plaintext);
    expect(vault.recordedState(DatabaseRole.data, _account),
        DatabaseEncryptionState.plain);
    expect(vault.migrationFailures(DatabaseRole.data, _account), 0);
  });

  test("a headless engine is refused a file recorded as migrating", () async {
    makePlain(data());
    await vault.recordState(
        DatabaseRole.data, _account, DatabaseEncryptionState.migrating);
    final headless = newVault(allowCreate: false);
    await headless.unlock();
    DatabaseKeys.debugVault = headless;
    await expectLater(
        DatabaseKeys.forFile(data(), DatabaseRole.data, _account),
        throwsA(isA<DatabaseKeyError>()
            .having((e) => e.kind, "kind", DatabaseKeyErrorKind.migrating)));
    // And the migration now skips it (the open marked it).
    DatabaseKeys.debugVault = vault;
    final report = await LocalDataMigration(
            vault: vault,
            databaseDirectory: dbDir,
            accounts: const [_account],
            migrator: DatabaseMigrator(useIsolate: false))
        .run();
    expect(report!.skipped.single.path, data());
    await headless.dispose();
  });

  test("only one run at a time; a stale lock is taken over", () async {
    makePlain(data());
    await vault.keystoreFile.ensureDirectory();
    final lock = File(p.join(keys, ".migrate.lock"))..createSync();
    expect(await migration().run(), isNull);
    lock.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    expect((await migration().run())!.allEncrypted, isTrue);
    expect(lock.existsSync(), isFalse);
  });

  test("an interrupted run is finished at the next start", () async {
    makePlain(data());
    await expectLater(
        migration(
            migrator: DatabaseMigrator(
                useIsolate: false,
                beforeStep: (step, _) {
                  if (step == MigrationStep.renameTemp) {
                    throw SimulatedCrash(step);
                  }
                })).run(),
        throwsA(isA<SimulatedCrash>()));
    // keys/.migrate.lock is released by the finally even here; a real kill
    // leaves it, and it goes stale.
    expect(migration().needed, isTrue);
    final report = await migration().run();
    expect(report!.allEncrypted, isTrue);
    final key = await DatabaseKeys.forFile(data(), DatabaseRole.data, _account);
    final db = EncryptedOpen.open(data(), key: key);
    expect(rowsIn(db), 50);
    db.close();
  });

  test("forgetting an account makes its databases undecryptable", () async {
    makePlain(data());
    await migration().run();
    expect(await vault.existingDatabaseKey(DatabaseRole.data, _account),
        isNotNull);
    await vault.forgetAccount(_account);
    expect(
        await vault.existingDatabaseKey(DatabaseRole.data, _account), isNull);
    await expectLater(
        DatabaseKeys.forFile(data(), DatabaseRole.data, _account),
        throwsA(isA<DatabaseKeyError>().having(
            (e) => e.kind, "kind", DatabaseKeyErrorKind.keyUnavailable)));
    // A new vault (next start) doesn't have it either.
    final next = newVault();
    await next.unlock();
    expect(await next.existingDatabaseKey(DatabaseRole.data, _account), isNull);
    await next.dispose();
  });

  group("turned off: decrypting", () {
    Future<void> encryptAll() async {
      makePlain(appData(), rows: 5);
      makePlain(data(), rows: 80, version: 12);
      makePlain(search(), rows: 30, version: 2);
      final report = await migration().run();
      expect(report!.allEncrypted, isTrue);
      LocalDataSetting.debugOverride =
          const LocalDataSetting(encrypt: false, chosen: true);
    }

    test("every encrypted database is decrypted, then the keys are forgotten",
        () async {
      await encryptAll();
      final mediaStamp = vault.mediaKeyStamp;
      final m = migration(decrypt: true);
      expect(m.needed, isTrue);
      final seen = <String>[];
      final report =
          await m.run(onProgress: (pr) => seen.add("${pr.index}/${pr.count}"));
      expect(report!.allPlain, isTrue);
      expect(report.forgotKeys, isTrue);
      expect(seen.last, "3/3");
      expect(m.needed, isFalse);
      for (final (path, role, account, rows) in [
        (appData(), DatabaseRole.appData, null, 5),
        (data(), DatabaseRole.data, _account, 80),
        (search(), DatabaseRole.searchIndex, _account, 30),
      ]) {
        expect(EncryptedOpen.fileState(path), DatabaseFileState.plaintext);
        expect(await DatabaseKeys.forFile(path, role, account), isNull);
        final db = sqlite3.open(path);
        expect(rowsIn(db), rows);
        db.close();
        expect(DatabaseMigrator.hasLeftovers(path), isFalse);
      }
      expect(
          await vault.existingDatabaseKey(DatabaseRole.data, _account), isNull);
      expect(vault.hasDatabaseKeys, isFalse);
      // The media key stays (the media cache is always encrypted).
      expect(vault.mediaKeyStamp, mediaStamp);
      // A new file is made plaintext now.
      expect(
          await DatabaseKeys.forFile(
              data("client-b"), DatabaseRole.data, "client-b"),
          isNull);
    });

    test("a failing message store stays encrypted and keeps its key", () async {
      await encryptAll();
      final report =
          await migration(decrypt: true, migrator: failingFor(data())).run();
      expect(report!.allPlain, isFalse);
      expect(report.forgotKeys, isFalse);
      expect(report.failedStep, MigrationStep.verify);
      expect(EncryptedOpen.fileState(data()), DatabaseFileState.encrypted);
      expect(vault.recordedState(DatabaseRole.data, _account),
          DatabaseEncryptionState.encrypted);
      expect(vault.migrationFailures(DatabaseRole.data, _account), 1);
      // Still opens with its key in the meantime.
      final key =
          await DatabaseKeys.forFile(data(), DatabaseRole.data, _account);
      final db = EncryptedOpen.open(data(), key: key);
      expect(rowsIn(db), 80);
      db.close();

      final next = await migration(decrypt: true).run();
      expect(next!.allPlain, isTrue);
      expect(next.forgotKeys, isTrue);
      expect(EncryptedOpen.fileState(data()), DatabaseFileState.plaintext);
    });

    test(
        "a failing search index is kept encrypted with its key, a damaged "
        "one is deleted to be made again plaintext", () async {
      await encryptAll();
      final report =
          await migration(decrypt: true, migrator: failingFor(search())).run();
      expect(EncryptedOpen.fileState(search()), DatabaseFileState.encrypted);
      expect(EncryptedOpen.fileState(data()), DatabaseFileState.plaintext);
      expect(report!.forgotKeys, isFalse);
      expect(
          await vault.existingDatabaseKey(DatabaseRole.searchIndex, _account),
          isNotNull);

      final damaged = await migration(
              decrypt: true,
              migrator: failingFor(search(),
                  error:
                      const MigrationError("simulated damage", corrupt: true)))
          .run();
      expect(File(search()).existsSync(), isFalse);
      expect(damaged!.forgotKeys, isTrue);
      expect(vault.hasDatabaseKeys, isFalse);
    });

    test(
        "an account left out (Continue without) keeps its keys; the others' "
        "are forgotten", () async {
      makePlain(data("client-b"), rows: 4);
      await encryptAll();
      await migration(accounts: const [_account, "client-b"]).run();
      expect(EncryptedOpen.fileState(data("client-b")),
          DatabaseFileState.encrypted);
      // client-b's store wasn't opened this run: left out.
      final report = await LocalDataMigration(
          decrypt: true,
          vault: vault,
          databaseDirectory: dbDir,
          accounts: const [_account],
          keepKeysFor: const {"client-b"},
          migrator: DatabaseMigrator(useIsolate: false),
          inUse: (_) => false).run();
      expect(report!.allPlain, isTrue);
      expect(report.forgotKeys, isFalse);
      expect(
          await vault.existingDatabaseKey(DatabaseRole.data, _account), isNull);
      final kept =
          await vault.existingDatabaseKey(DatabaseRole.data, "client-b");
      expect(kept, isNotNull);
      final db = EncryptedOpen.open(data("client-b"), key: kept);
      expect(rowsIn(db), 4);
      db.close();

      // The next start decrypts it, then forgets its keys too.
      final next =
          await migration(decrypt: true, accounts: const [_account, "client-b"])
              .run();
      expect(next!.forgotKeys, isTrue);
      expect(vault.hasDatabaseKeys, isFalse);
      expect(EncryptedOpen.fileState(data("client-b")),
          DatabaseFileState.plaintext);
    });

    test("keys a killed run kept are forgotten at the next start", () async {
      await encryptAll();
      // Killed after the files were decrypted, before the keys went.
      for (final (path, role, account) in [
        (appData(), DatabaseRole.appData, null),
        (data(), DatabaseRole.data, _account),
        (search(), DatabaseRole.searchIndex, _account),
      ]) {
        final key = (await vault.existingDatabaseKey(role, account))!;
        await DatabaseMigrator(useIsolate: false).decrypt(path, key);
      }
      expect(vault.hasDatabaseKeys, isTrue);
      final m = migration(decrypt: true);
      expect(m.needed, isFalse);
      final report = await m.run();
      expect(report!.forgotKeys, isTrue);
      expect(vault.hasDatabaseKeys, isFalse);
    });

    test("an interrupted decryption is finished at the next start", () async {
      await encryptAll();
      await expectLater(
          migration(
              decrypt: true,
              migrator: DatabaseMigrator(
                  useIsolate: false,
                  beforeStep: (s, at) {
                    if (at == data() && s == MigrationStep.renameTemp) {
                      throw SimulatedCrash(s);
                    }
                  })).run(),
          throwsA(isA<SimulatedCrash>()));
      final m = migration(decrypt: true);
      expect(m.needed, isTrue);
      final report = await m.run();
      expect(report!.forgotKeys, isTrue);
      final db = sqlite3.open(data());
      expect(rowsIn(db), 80);
      db.close();
    });
  });
}
