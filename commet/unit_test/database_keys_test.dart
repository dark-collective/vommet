// Vommet: local data encryption, phase 3: which key a database is opened
// with, and the database isolate's connect protocol. A new file is created
// encrypted; a plaintext file keeps opening untouched; an encrypted file
// whose key can't be had fails closed with a typed error and is neither
// replaced nor deleted; a wrong key reaches the caller of the database
// isolate as a DatabaseKeyError and isn't cached; the search index worker
// opens an encrypted index; no key ever reaches the log. Local data
// encryption is opt-in: with the setting off (the default) a new file is
// created plaintext and no key is made.
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/matrix/components/encrypted_search_index/search_index_store.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_worker.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/security/database_keys.dart';
import 'package:commet/security/key_vault/file_key_store.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/keystore_file.dart';
import 'package:commet/security/local_data_on_disk.dart';
import 'package:commet/security/local_data_setting.dart';
import 'package:commet/security/migration/database_migration.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:commet/utils/database/multiple_database_server.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const _account = "test-account";

String _hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, "0")).join();

void _expectKeyError(Object e, DatabaseKeyErrorKind kind) {
  expect(e, isA<DatabaseKeyError>());
  expect((e as DatabaseKeyError).kind, kind);
}

void main() {
  late Directory root;
  late String keys;
  late KeyVault vault;

  KeyVault newVault({bool allowCreate = true}) => KeyVault(
        keystoreFile: KeystoreFile(keys),
        fileStore: FileKeyStore(keys),
        preferredStores: const [],
        allowCreate: allowCreate,
        noKeyringReason: "test",
      );

  setUp(() async {
    root = await Directory(p.join(Directory.current.path, ".dart_tool"))
        .createTemp("database_keys_test_");
    keys = p.join(root.path, "keys");
    vault = newVault();
    expect((await vault.unlock()).isReady, isTrue);
    DatabaseKeys.debugVault = vault;
    LocalDataSetting.debugOverride =
        const LocalDataSetting(encrypt: true, chosen: true);
  });

  tearDown(() async {
    LocalDataSetting.debugOverride = null;
    DatabaseKeys.debugVault = null;
    await vault.dispose();
    await root.delete(recursive: true);
  });

  test("a new database is created encrypted and reopens with its key",
      () async {
    final path = p.join(root.path, "data.db");
    final key = await DatabaseKeys.forFile(path, DatabaseRole.data, _account);
    expect(key, isNotNull);
    expect(vault.recordedState(DatabaseRole.data, _account),
        DatabaseEncryptionState.encrypted);

    EncryptedOpen.open(path, key: key)
      ..execute("CREATE TABLE t (x TEXT)")
      ..execute("INSERT INTO t VALUES ('hello')")
      ..close();
    expect(EncryptedOpen.fileState(path), DatabaseFileState.encrypted);
    final head = File(path).readAsBytesSync().sublist(0, 16);
    expect(utf8.decode(head, allowMalformed: true),
        isNot(startsWith("SQLite format 3")));

    // A second engine (a fresh vault on the same keystore) gets the same key.
    final other = newVault(allowCreate: false);
    await other.unlock();
    DatabaseKeys.debugVault = other;
    final again = await DatabaseKeys.forFile(path, DatabaseRole.data, _account);
    expect(again, key);
    final db = EncryptedOpen.open(path, key: again);
    expect(db.select("SELECT x FROM t").single["x"], "hello");
    db.close();
    await other.dispose();
  });

  test("off by default: a new database is created plaintext, no key made",
      () async {
    LocalDataSetting.debugOverride = null;
    expect(LocalDataSetting.read(keys), LocalDataSetting.byDefault);
    final path = p.join(root.path, "data.db");
    expect(
        await DatabaseKeys.forFile(path, DatabaseRole.data, _account), isNull);
    expect(vault.recordedState(DatabaseRole.data, _account),
        DatabaseEncryptionState.plain);
    expect(vault.hasDatabaseKeys, isFalse);
    expect(
        await vault.existingDatabaseKey(DatabaseRole.data, _account), isNull);
  });

  test("the setting file turns it on, and is read back as written", () async {
    LocalDataSetting.debugOverride = null;
    await const LocalDataSetting(encrypt: true, chosen: true).write(keys);
    expect(LocalDataSetting.read(keys),
        const LocalDataSetting(encrypt: true, chosen: true));
    if (!Platform.isWindows) {
      expect(
          File(LocalDataSetting.pathIn(keys)).statSync().mode & 0x1ff, 0x180);
    }
    final path = p.join(root.path, "data.db");
    expect(await DatabaseKeys.forFile(path, DatabaseRole.data, _account),
        isNotNull);
    await const LocalDataSetting(encrypt: false, chosen: true).write(keys);
    expect(
        await DatabaseKeys.forFile(
            p.join(root.path, "other.db"), DatabaseRole.data, "other"),
        isNull);
    // A damaged file reads as the default.
    File(LocalDataSetting.pathIn(keys)).writeAsStringSync("{nope");
    expect(LocalDataSetting.read(keys), LocalDataSetting.byDefault);
  });

  test("a plaintext database keeps opening unencrypted and untouched",
      () async {
    final path = p.join(root.path, "data.db");
    sqlite3.open(path)
      ..execute("CREATE TABLE t (x TEXT)")
      ..close();
    final before = File(path).readAsBytesSync();

    expect(
        await DatabaseKeys.forFile(path, DatabaseRole.data, _account), isNull);
    expect(vault.recordedState(DatabaseRole.data, _account),
        DatabaseEncryptionState.plain);
    expect(File(path).readAsBytesSync(), before);
    // Even with a vault that isn't ready.
    DatabaseKeys.debugVault = newVault(allowCreate: false);
    expect(
        await DatabaseKeys.forFile(path, DatabaseRole.data, _account), isNull);
  });

  test("an encrypted database without its key fails closed", () async {
    final path = p.join(root.path, "data.db");
    final key = await DatabaseKeys.forFile(path, DatabaseRole.data, _account);
    EncryptedOpen.open(path, key: key)
      ..execute("CREATE TABLE t (x TEXT)")
      ..close();
    final before = File(path).readAsBytesSync();

    // The key file is gone: the vault can't be ready.
    await File(p.join(keys, FileKeyStore.fileName)).delete();
    final lost = newVault();
    expect((await lost.unlock()).state, VaultState.missing);
    DatabaseKeys.debugVault = lost;

    for (final role in [DatabaseRole.data]) {
      try {
        await DatabaseKeys.forFile(path, role, _account);
        fail("expected a DatabaseKeyError");
      } catch (e) {
        _expectKeyError(e, DatabaseKeyErrorKind.keyUnavailable);
      }
    }
    // A new database isn't created in plaintext either.
    final fresh = p.join(root.path, "other.db");
    try {
      await DatabaseKeys.forFile(fresh, DatabaseRole.data, "other");
      fail("expected a DatabaseKeyError");
    } catch (e) {
      _expectKeyError(e, DatabaseKeyErrorKind.keyUnavailable);
    }
    expect(File(fresh).existsSync(), isFalse);
    expect(File(path).readAsBytesSync(), before);
    await lost.dispose();
  });

  test("an encrypted file with no recorded salt fails closed", () async {
    final path = p.join(root.path, "data.db");
    final stranger = KeyHierarchy.randomBytes(32);
    EncryptedOpen.open(path, key: stranger)
      ..execute("CREATE TABLE t (x TEXT)")
      ..close();
    try {
      await DatabaseKeys.forFile(path, DatabaseRole.data, "unknown");
      fail("expected a DatabaseKeyError");
    } catch (e) {
      _expectKeyError(e, DatabaseKeyErrorKind.keyUnavailable);
    }
    expect(File(path).existsSync(), isTrue);
  });

  group("the setting comes from the disk and fails closed", () {
    String store(String account) =>
        p.join(root.path, "account", "drift", account, "data.db");

    Future<void> makeEncryptedStore(String account) async {
      final path = store(account);
      Directory(p.dirname(path)).createSync(recursive: true);
      final key = await DatabaseKeys.forFile(path, DatabaseRole.data, account);
      expect(key, isNotNull);
      EncryptedOpen.open(path, key: key)
        ..execute("CREATE TABLE t (x TEXT)")
        ..close();
    }

    test("an unreadable setting file never turns encryption off", () async {
      LocalDataSetting.debugOverride = null;
      await const LocalDataSetting(encrypt: true, chosen: true).write(keys);
      await makeEncryptedStore(_account);
      // Truncated by a power loss.
      const truncated = '{"v": 1, "encr';
      File(LocalDataSetting.pathIn(keys)).writeAsStringSync(truncated);
      expect(LocalDataSetting.load(keys).state,
          LocalDataSettingFileState.unreadable);
      final (setting, state) = await LocalDataOnDisk.setting(root.path);
      expect(state, LocalDataSettingFileState.unreadable);
      expect(setting.encrypt, isTrue);
      expect(await DatabaseKeys.encryptsNewFiles(), isTrue);
      final other = store("other");
      Directory(p.dirname(other)).createSync(recursive: true);
      expect(await DatabaseKeys.forFile(other, DatabaseRole.data, "other"),
          isNotNull);
      // Nothing was rewritten or forgotten because of it.
      expect(File(LocalDataSetting.pathIn(keys)).readAsStringSync(), truncated);
      expect(await vault.existingDatabaseKey(DatabaseRole.data, _account),
          isNotNull);
    });

    test("only a setting that was read turns encryption off", () {
      const unreadable =
          LocalDataSettingFile(LocalDataSettingFileState.unreadable, null);
      const missing =
          LocalDataSettingFile(LocalDataSettingFileState.missing, null);
      const off = LocalDataSettingFile(LocalDataSettingFileState.ok,
          LocalDataSetting(encrypt: false, chosen: true));
      expect(LocalDataSetting.resolve(unreadable, encryptedOnDisk: true),
          const LocalDataSetting(encrypt: true, chosen: false));
      expect(LocalDataSetting.resolve(missing, encryptedOnDisk: true).encrypt,
          isTrue);
      expect(LocalDataSetting.resolve(unreadable, encryptedOnDisk: false),
          LocalDataSetting.byDefault);
      expect(LocalDataSetting.resolve(off, encryptedOnDisk: true).encrypt,
          isFalse);
    });

    test(
        "without a setting file, an unreadable keystore.json alone doesn't "
        "turn it on", () async {
      LocalDataSetting.debugOverride = null;
      Directory(keys).createSync(recursive: true);
      File(p.join(keys, "keystore.json")).writeAsStringSync("{nope");
      // Unknown is no evidence: a plaintext user stays on the default (off)
      // and never needs the key (no "key missing" screen).
      expect(await LocalDataOnDisk.keystoreHasDatabaseKeys(keys), isNull);
      final (setting, state) = await LocalDataOnDisk.setting(root.path);
      expect(state, LocalDataSettingFileState.missing);
      expect(setting, LocalDataSetting.byDefault);
      expect(await DatabaseKeys.encryptsNewFiles(), isFalse);
      expect(LocalDataSetting.existsIn(keys), isFalse);
    });

    test("an unreadable keystore.json with an encrypted file stays on",
        () async {
      await makeEncryptedStore(_account);
      LocalDataSetting.debugOverride = null;
      File(p.join(keys, "keystore.json")).writeAsStringSync("{nope");
      expect(LocalDataOnDisk.anyEncryptedFile(root.path), isTrue);
      expect(await DatabaseKeys.encryptsNewFiles(), isTrue);
    });

    test(
        "keys/ wiped under a vault that still holds keys: new files follow "
        "the disk, not the vault", () async {
      LocalDataSetting.debugOverride = null;
      await const LocalDataSetting(encrypt: true, chosen: true).write(keys);
      await makeEncryptedStore(_account);
      expect(vault.hasDatabaseKeys, isTrue);
      await Directory(keys).delete(recursive: true);
      // The encrypted store is still on disk: on.
      expect(await DatabaseKeys.encryptsNewFiles(), isTrue);
      await Directory(p.join(root.path, "account")).delete(recursive: true);
      // Nothing encrypted left and no setting: the default (off), whatever
      // the vault in memory still holds.
      expect(await DatabaseKeys.encryptsNewFiles(), isFalse);
    });

    test("with the setting on, no path creates a plaintext database", () async {
      LocalDataSetting.debugOverride = null;
      final otherRoot = Directory(p.join(root.path, "elsewhere"))..createSync();
      final otherKeys = p.join(otherRoot.path, "keys");
      await const LocalDataSetting(encrypt: true, chosen: true)
          .write(otherKeys);
      // A vault that can't be ready (a headless engine with no keystore).
      final notReady = KeyVault(
        keystoreFile: KeystoreFile(otherKeys),
        fileStore: FileKeyStore(otherKeys),
        preferredStores: const [],
        allowCreate: false,
        noKeyringReason: "test",
      );
      await notReady.unlock();
      expect(notReady.status.isReady, isFalse);
      DatabaseKeys.debugVault = notReady;
      final fresh = p.join(otherRoot.path, "account", "drift", "x", "data.db");
      Directory(p.dirname(fresh)).createSync(recursive: true);
      for (final role in DatabaseRole.values) {
        try {
          await DatabaseKeys.forFile(fresh, role, "x");
          fail("expected a DatabaseKeyError");
        } catch (e) {
          _expectKeyError(e, DatabaseKeyErrorKind.keyUnavailable);
        }
      }
      expect(File(fresh).existsSync(), isFalse);
      DatabaseKeys.debugVault = vault;
      await notReady.dispose();
    });

    test("a failed setting write is tried again; the old file stays", () async {
      LocalDataSetting.debugOverride = null;
      await const LocalDataSetting(encrypt: false, chosen: true).write(keys);
      var calls = 0;
      LocalDataSetting.debugBeforeWrite = (attempt) {
        calls++;
        if (attempt == 1) throw const FileSystemException("simulated");
      };
      addTearDown(() => LocalDataSetting.debugBeforeWrite = null);
      await const LocalDataSetting(encrypt: true, chosen: true).write(keys);
      expect(calls, 2);
      expect(LocalDataSetting.read(keys).encrypt, isTrue);
      LocalDataSetting.debugBeforeWrite =
          (_) => throw const FileSystemException("simulated");
      await expectLater(
          const LocalDataSetting(encrypt: false, chosen: true).write(keys),
          throwsA(isA<FileSystemException>()));
      expect(LocalDataSetting.read(keys).encrypt, isTrue,
          reason: "the previous setting is kept");
    });

    test("an engine with no vault yet refuses a file being migrated", () async {
      final path = p.join(root.path, "plain.db");
      sqlite3.open(path)
        ..execute("CREATE TABLE t (x TEXT)")
        ..close();
      await vault.recordState(
          DatabaseRole.data, _account, DatabaseEncryptionState.migrating);
      DatabaseKeys.debugVault = null;
      DatabaseKeys.debugKeysDirectory = keys;
      addTearDown(() => DatabaseKeys.debugKeysDirectory = null);
      expect(KeyVault.instance, isNull);
      try {
        await DatabaseKeys.forFile(path, DatabaseRole.data, _account);
        fail("expected a DatabaseKeyError");
      } catch (e) {
        _expectKeyError(e, DatabaseKeyErrorKind.migrating);
      }
      DatabaseKeys.debugVault = vault;
    });
  });

  test(
      "an engine with no vault refuses a file with migration copies when "
      "keystore.json can't be read", () async {
    final path = p.join(root.path, "plain.db");
    sqlite3.open(path)
      ..execute("CREATE TABLE t (x TEXT)")
      ..close();
    File(DatabaseMigrator.tempPath(path)).writeAsStringSync("copy");
    File(p.join(keys, "keystore.json")).writeAsStringSync("{nope");
    DatabaseKeys.debugVault = null;
    DatabaseKeys.debugKeysDirectory = keys;
    addTearDown(() => DatabaseKeys.debugKeysDirectory = null);
    try {
      await DatabaseKeys.forFile(path, DatabaseRole.data, _account);
      fail("expected a DatabaseKeyError");
    } catch (e) {
      _expectKeyError(e, DatabaseKeyErrorKind.migrating);
    }
    // No copies: the file opens as before.
    File(DatabaseMigrator.tempPath(path)).deleteSync();
    expect(
        await DatabaseKeys.forFile(path, DatabaseRole.data, _account), isNull);
    DatabaseKeys.debugVault = vault;
  });

  test("a read-only open of a missing file asks for no key", () async {
    final path = p.join(root.path, "data.db");
    expect(
        await DatabaseKeys.forFile(path, DatabaseRole.data, _account,
            readOnly: true),
        isNull);
    expect(File(path).existsSync(), isFalse);
  });

  test("the database isolate reports a wrong key and doesn't cache it",
      () async {
    final path = p.join(root.path, "data.db");
    final key = await DatabaseKeys.forFile(path, DatabaseRole.data, _account);
    EncryptedOpen.open(path, key: key)
      ..execute("CREATE TABLE t (x TEXT)")
      ..execute("INSERT INTO t VALUES ('hello')")
      ..close();

    final wrong = Uint8List.fromList(key!)..[0] ^= 1;
    try {
      await DatabaseIsolate.connect(path, key: wrong);
      fail("expected a DatabaseKeyError");
    } catch (e) {
      _expectKeyError(e, DatabaseKeyErrorKind.wrongKey);
      expect(e.toString(), isNot(contains(_hexOf(wrong))));
    }
    try {
      await DatabaseIsolate.connect(path);
      fail("expected a DatabaseOpenError");
    } catch (e) {
      // Without a key an encrypted file is "not a database".
      expect(e, isA<DatabaseOpenError>());
    }

    final connection = await DatabaseIsolate.connect(path, key: key);
    final db = _Db(connection);
    final rows = await db.customSelect("SELECT x FROM t").get();
    expect(rows.single.read<String>("x"), "hello");
    await db.close();
  });

  test("the search index worker opens an encrypted index", () async {
    final path = p.join(root.path, "search_index.db");
    final key =
        await DatabaseKeys.forFile(path, DatabaseRole.searchIndex, _account);
    expect(key, isNotNull);
    final worker = await SearchIndexWorker.spawn(path, key: key);
    expect(await worker.run(_hasFullText, null), isTrue);
    final reader = await SearchIndexWorker.spawn(path, key: key, reader: true);
    await reader.close();
    await worker.close();
    expect(EncryptedOpen.fileState(path), DatabaseFileState.encrypted);

    final wrong = Uint8List.fromList(key!)..[0] ^= 1;
    try {
      await SearchIndexWorker.spawn(path, key: wrong);
      fail("expected a DatabaseKeyError");
    } catch (e) {
      _expectKeyError(e, DatabaseKeyErrorKind.wrongKey);
    }
  });

  test("no key material reaches the log", () async {
    final start = Log.log.length;
    final path = p.join(root.path, "data.db");
    final key = await DatabaseKeys.forFile(path, DatabaseRole.data, _account);
    EncryptedOpen.open(path, key: key).close();
    final wrong = Uint8List.fromList(key!)..[0] ^= 1;
    try {
      EncryptedOpen.open(path, key: wrong);
    } on DatabaseKeyError catch (e) {
      Log.w("open failed: $e");
    }
    Log.i("vault: $vault, ${vault.status}");
    final logged = Log.log.skip(start).map((e) => e.rawContent).join("\n");
    for (final secret in [key, wrong]) {
      expect(logged, isNot(contains(_hexOf(secret))));
      expect(logged, isNot(contains(base64.encode(secret))));
    }
  });
}

bool _hasFullText(SearchIndexStore store, Object? _) => store.hasFullText;

class _Db extends GeneratedDatabase {
  _Db(super.e);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}
