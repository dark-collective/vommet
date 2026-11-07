// Vommet: local data encryption, the KeyVault (phase 2): the HKDF key
// hierarchy is pinned with fixed vectors, keystore.json round-trips and
// rejects what it can't use, and the startup decision table holds with fake
// key stores: a new install keeps its key in the first store that reads it
// back, falls back to the key file (notice due) without one, reuses a key
// left in a store, and never makes a new key over a recorded one.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/security/key_vault/file_key_store.dart';
import 'package:commet/security/key_vault/key_file_io.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/keystore_file.dart';
import 'package:commet/security/key_vault/master_key_store.dart';
import 'package:commet/utils/disk_space.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class FakeStore extends MasterKeyStore {
  FakeStore({
    this.kind = KeyStoreKind.keyring,
    this.availabilityValue = StoreAvailability.available,
    this.unlockOnPrompt = false,
    this.failWrites = false,
    this.corruptReadBack = false,
  });

  @override
  final KeyStoreKind kind;
  StoreAvailability availabilityValue;
  bool unlockOnPrompt;
  bool failWrites;
  bool corruptReadBack;
  Uint8List? stored;

  /// What [read] returns instead of [stored] (cleared by [archive]).
  StoreReadResult? forcedRead;
  int prompts = 0;
  int writes = 0;

  @override
  String get name => "Fake ${kind.id}";

  @override
  Future<StoreAvailability> availability() async => availabilityValue;

  @override
  Future<StoreReadResult> read({bool interactive = false}) async {
    if (availabilityValue == StoreAvailability.unavailable) {
      return const StoreUnreachable("no daemon");
    }
    if (availabilityValue == StoreAvailability.locked) {
      if (!interactive) return const StoreLocked();
      prompts++;
      if (!unlockOnPrompt) return const StoreLocked();
      availabilityValue = StoreAvailability.available;
    }
    final forced = forcedRead;
    if (forced != null) return forced;
    final key = stored;
    if (key == null) return const StoreEmpty();
    if (corruptReadBack) {
      return StoreFound(Uint8List.fromList(key)..[0] ^= 1);
    }
    return StoreFound(Uint8List.fromList(key));
  }

  @override
  Future<void> write(Uint8List key) async {
    if (failWrites || availabilityValue != StoreAvailability.available) {
      throw KeyStoreException("refused");
    }
    writes++;
    stored = Uint8List.fromList(key);
  }

  @override
  Future<void> delete() async => stored = null;

  /// Keys set aside by [archive], oldest first.
  final archived = <Uint8List>[];

  @override
  Future<void> archive() async {
    if (availabilityValue != StoreAvailability.available) {
      throw KeyStoreException("refused");
    }
    final key = stored;
    if (key != null) archived.add(key);
    stored = null;
    forcedRead = null;
  }

  @override
  Future<List<Uint8List>> archivedKeys() async =>
      [for (final key in archived.reversed) Uint8List.fromList(key)];

  @override
  Future<void> pruneArchives({int keep = MasterKeyStore.archivesKept}) async {
    while (archived.length > keep) {
      archived.removeAt(0);
    }
  }
}

void main() {
  late Directory root;
  late String keys;

  setUp(() async {
    root = await Directory(p.join(Directory.current.path, ".dart_tool"))
        .createTemp("key_vault_test_");
    keys = p.join(root.path, "keys");
  });

  final made = <KeyVault>[];

  tearDown(() async {
    // A vault moves its key to a keyring in the background after unlocking.
    for (final v in made) {
      await v.idle();
    }
    made.clear();
    await root.delete(recursive: true);
  });

  KeyVault vault(List<MasterKeyStore> stores,
      {bool allowCreate = true, String? noKeyringReason}) {
    final v = KeyVault(
        keystoreFile: KeystoreFile(keys),
        fileStore: FileKeyStore(keys),
        preferredStores: stores,
        allowCreate: allowCreate,
        noKeyringReason: noKeyringReason);
    made.add(v);
    return v;
  }

  group("key hierarchy", () {
    final m = Uint8List.fromList(List.generate(32, (i) => i));
    final s = Uint8List.fromList(List.generate(32, (i) => i + 32));

    // Computed independently (Python hmac/hashlib RFC 5869). Changing an
    // info string makes every encrypted database unreadable.
    test("fixed vectors", () async {
      expect(await KeyHierarchy.checkValue(m), "b80db817688808f5");
      expect(
          KeyHierarchy.hex(
              await KeyHierarchy.databaseKey(m, s, DatabaseRole.data)),
          "8da1270f85353e1ef47ccb557a03cc6563c36e3dad488ba7c8906ff9df56cb48");
      expect(
          KeyHierarchy.hex(
              await KeyHierarchy.databaseKey(m, s, DatabaseRole.searchIndex)),
          "9079080dbe83136179b464e00cf9ba7f459b972a44c538fcc3c1c755c98f1968");
      expect(
          KeyHierarchy.hex(
              await KeyHierarchy.databaseKey(m, s, DatabaseRole.appData)),
          "94399d761b7396449a7b52c68841ff335e65538ed4a0eb209ac4bd5953d5cf07");
      expect(KeyHierarchy.hex(await KeyHierarchy.mediaKey(m, s)),
          "ee44a7e6a94b8a8a5039c736db90fcbab8891d57ee570d70b0972db59d70a2d6");
      expect(KeyHierarchy.hex(await KeyHierarchy.filesKey(m, s)),
          "b00a20571b3eda9c69f2368ae14b7801f31c8b6f8f08cd7ed8bb573a28cd2a79");
    });

    test("rejects a short master key", () {
      expect(
          () => KeyHierarchy.derive([1, 2, 3], info: "x"), throwsArgumentError);
    });
  });

  group("keystore.json", () {
    test("round-trips and keeps unknown fields", () {
      final doc =
          KeystoreDocument.create(store: KeyStoreKind.keyring, check: "0" * 16);
      expect(doc.ensureAccountSalt("acc"), isTrue);
      expect(doc.ensureAccountSalt("acc"), isFalse);
      doc.setState(DatabaseRole.data, "acc", DatabaseEncryptionState.encrypted);
      doc.setState(DatabaseRole.appData, null, DatabaseEncryptionState.plain);
      final json = jsonDecode(doc.encode()) as Map<String, dynamic>;
      json["future_field"] = {"x": 1};
      final back = KeystoreDocument.parse(jsonEncode(json));
      expect(back.store, KeyStoreKind.keyring);
      expect(back.accountSalt("acc"), doc.accountSalt("acc"));
      expect(back.state(DatabaseRole.data, "acc"),
          DatabaseEncryptionState.encrypted);
      expect(back.state(DatabaseRole.searchIndex, "acc"), isNull);
      expect(back.state(DatabaseRole.appData, null),
          DatabaseEncryptionState.plain);
      expect(jsonDecode(back.encode())["future_field"], {"x": 1});
      back.removeAccount("acc");
      expect(back.accountSalt("acc"), isNull);
    });

    test("rejects what it can't use", () {
      final good = jsonDecode(
          KeystoreDocument.create(store: KeyStoreKind.file, check: "a" * 16)
              .encode()) as Map<String, dynamic>;
      for (final change in <void Function(Map<String, dynamic>)>[
        (j) => j["v"] = 2,
        (j) => j["store"] = "cloud",
        (j) => j["check"] = "xyz",
        (j) => j["app_salt"] = "c2hvcnQ=",
        (j) => j["accounts"] = [],
      ]) {
        final copy = jsonDecode(jsonEncode(good)) as Map<String, dynamic>;
        change(copy);
        expect(() => KeystoreDocument.parse(jsonEncode(copy)),
            throwsA(isA<KeystoreFormatException>()));
      }
      expect(() => KeystoreDocument.parse("{"),
          throwsA(isA<KeystoreFormatException>()));
    });

    test("atomic write leaves no temporary files and is owner-only", () async {
      final file = KeystoreFile(keys);
      final doc =
          KeystoreDocument.create(store: KeyStoreKind.file, check: "b" * 16);
      await file.locked(() => file.write(doc));
      expect((await file.read())!.check, "b" * 16);
      final names =
          Directory(keys).listSync().map((e) => p.basename(e.path)).toList();
      expect(names, ["keystore.json"]);
      if (Platform.isLinux || Platform.isMacOS) {
        expect(File(file.path).statSync().mode & 0x1FF, 0x180);
        expect(Directory(keys).statSync().mode & 0x1FF, 0x1C0);
      }
    });

    test("a crash between write and rename keeps the old document", () async {
      final file = KeystoreFile(keys);
      await file.locked(() => file.write(
          KeystoreDocument.create(store: KeyStoreKind.file, check: "c" * 16)));
      // What a crash leaves: a complete temporary file never renamed.
      File(p.join(keys, "keystore.json.deadbeef.tmp"))
          .writeAsStringSync("{half");
      expect((await file.read())!.check, "c" * 16);
      await file.sweepTemporaryFiles();
      expect(File(p.join(keys, "keystore.json.deadbeef.tmp")).existsSync(),
          isFalse);
    });

    test("an unreadable document is reported, not replaced", () async {
      Directory(keys).createSync(recursive: true);
      File(p.join(keys, "keystore.json")).writeAsStringSync("garbage");
      final v = vault([FakeStore()]);
      final status = await v.unlock();
      expect(status.state, VaultState.damaged);
      expect(File(p.join(keys, "keystore.json")).readAsStringSync(), "garbage");
    });

    test("the lock excludes a second holder and a stale one is taken over",
        () async {
      final file = KeystoreFile(keys);
      final order = <String>[];
      final first = file.locked(() async {
        order.add("a start");
        await Future<void>.delayed(const Duration(milliseconds: 300));
        order.add("a end");
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await file.locked(() async => order.add("b"));
      await first;
      expect(order, ["a start", "a end", "b"]);

      final lock = File(p.join(keys, ".lock"))..createSync();
      lock.setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 5)));
      expect(await file.locked(() async => "took over"), "took over");
    });
  });

  group("keystore.json lock and durability", () {
    test("a holder that takes longer than the stale time keeps the lock",
        () async {
      // File times are set to the second: a stale time of seconds.
      final file = KeystoreFile(keys,
          staleAfter: const Duration(seconds: 3),
          waitFor: const Duration(seconds: 10));
      final order = <String>[];
      final first = file.locked(() async {
        order.add("a start");
        // An unlock prompt, say: longer than the stale time.
        await Future<void>.delayed(const Duration(seconds: 6));
        order.add("a end");
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await file.locked(() async => order.add("b"));
      await first;
      expect(order, ["a start", "a end", "b"]);
      expect(File(p.join(keys, ".lock")).existsSync(), isFalse);
    });

    test("a stale lock is taken over by one waiter at a time", () async {
      // Over a second: the heartbeat sets file times to the second.
      final file = KeystoreFile(keys,
          staleAfter: const Duration(seconds: 2),
          waitFor: const Duration(seconds: 5));
      await file.ensureDirectory();
      File(p.join(keys, ".lock"))
        ..writeAsStringSync("dead")
        ..setLastModifiedSync(
            DateTime.now().subtract(const Duration(minutes: 5)));
      var inside = 0;
      var most = 0;
      Future<void> holder() => file.locked(() async {
            inside++;
            if (inside > most) most = inside;
            await Future<void>.delayed(const Duration(milliseconds: 100));
            inside--;
          });
      await Future.wait([holder(), holder(), holder()]);
      expect(most, 1);
      final left = Directory(keys)
          .listSync()
          .map((e) => p.basename(e.path))
          .where((n) => n.startsWith(".lock"));
      expect(left, isEmpty);
    });

    test("the keys folder is synced after keystore.json is written", () async {
      final synced = <String>[];
      DiskSpace.debugOnSyncDirectory = synced.add;
      addTearDown(() => DiskSpace.debugOnSyncDirectory = null);
      final file = KeystoreFile(keys);
      await file.locked(() => file.write(
          KeystoreDocument.create(store: KeyStoreKind.file, check: "c" * 16)));
      expect(synced, contains(keys));
      synced.clear();
      await FileKeyStore(keys).write(KeyHierarchy.newMasterKey());
      expect(synced, contains(keys));
    });

    test("a key file that can't be made owner-only isn't kept", () async {
      KeyFileIo.debugIsOwnerOnly = (_) async => false;
      addTearDown(() => KeyFileIo.debugIsOwnerOnly = null);
      await expectLater(FileKeyStore(keys).write(KeyHierarchy.newMasterKey()),
          throwsA(isA<KeyStoreException>()));
      expect(Directory(keys).listSync(), isEmpty);
      // No store keeps the key: the vault fails rather than leave it
      // readable by others.
      final status = await vault([]).unlock();
      expect(status.isReady, isFalse);
      expect(File(p.join(keys, "master.key")).existsSync(), isFalse);
    });
  });

  group("decision table", () {
    test("fresh install keeps the key in the keyring", () async {
      final ring = FakeStore();
      final v = vault([ring]);
      final status = await v.unlock();
      expect(status.state, VaultState.ready);
      expect(status.store, KeyStoreKind.keyring);
      expect(status.fileNoticeDue, isFalse);
      expect(ring.stored, isNotNull);
      expect(File(p.join(keys, "master.key")).existsSync(), isFalse);
      final doc = (await KeystoreFile(keys).read())!;
      expect(doc.check, await KeyHierarchy.checkValue(ring.stored!));
    });

    test("no keyring: key file, notice due, reason recorded", () async {
      final v =
          vault([FakeStore(availabilityValue: StoreAvailability.unavailable)]);
      final status = await v.unlock();
      expect(status.state, VaultState.ready);
      expect(status.store, KeyStoreKind.file);
      expect(status.fileNoticeDue, isTrue);
      expect(status.fallbackReason, contains("not available"));
      expect(File(p.join(keys, "master.key")).lengthSync(), 36);
      await v.acknowledgeFileNotice();
      expect(v.status.fileNoticeDue, isFalse);
      expect((await KeystoreFile(keys).read())!.fileNoticeDue, isFalse);
    });

    test("no preferred stores by design (macOS unsigned): no notice", () async {
      final v = vault([], noKeyringReason: "unsigned build");
      final status = await v.unlock();
      expect(status.store, KeyStoreKind.file);
      expect(status.fileNoticeDue, isFalse);
      expect(status.fallbackReason, "unsigned build");
    });

    test("a keyring that doesn't read back isn't used", () async {
      final ring = FakeStore(corruptReadBack: true);
      final status = await vault([ring]).unlock();
      expect(status.store, KeyStoreKind.file);
      expect(ring.stored, isNull);
      expect(status.fallbackReason, contains("read back"));
    });

    test("a locked keyring is unlocked interactively at creation", () async {
      final ring = FakeStore(
          availabilityValue: StoreAvailability.locked, unlockOnPrompt: true);
      final status = await vault([ring]).unlock(interactive: true);
      expect(status.store, KeyStoreKind.keyring);
      expect(ring.prompts, 1);
    });

    test("a locked keyring without a prompt falls back at creation", () async {
      final ring = FakeStore(availabilityValue: StoreAvailability.locked);
      final status = await vault([ring]).unlock();
      expect(status.store, KeyStoreKind.file);
      expect(status.fallbackReason, contains("locked"));
      expect(ring.prompts, 0);
    });

    test("a locked keyring's key is found, not written over (Start over)",
        () async {
      final old = KeyHierarchy.newMasterKey();
      final ring = FakeStore(
          availabilityValue: StoreAvailability.locked, unlockOnPrompt: true)
        ..stored = Uint8List.fromList(old);
      final status = await vault([ring]).unlock(interactive: true);
      expect(status.store, KeyStoreKind.keyring);
      expect(ring.writes, 0);
      expect(ring.stored, old);
      expect((await KeystoreFile(keys).read())!.check,
          await KeyHierarchy.checkValue(old));
    });

    test("another key in the keyring is set aside before a move to it",
        () async {
      final ring = FakeStore(availabilityValue: StoreAvailability.unavailable);
      final v1 = vault([ring]);
      await v1.unlock();
      await v1.idle();
      expect(v1.status.store, KeyStoreKind.file);
      final other = KeyHierarchy.newMasterKey();
      ring
        ..availabilityValue = StoreAvailability.available
        ..stored = Uint8List.fromList(other);
      final ours = (await FileKeyStore(keys).read()) as StoreFound;
      expect(await v1.moveTo(KeyStoreKind.keyring), isTrue);
      expect(ring.stored, ours.key);
      expect(ring.archived, [other]);
    });

    test("a key that can't be set aside isn't written over", () async {
      final ring = FakeStore(availabilityValue: StoreAvailability.unavailable);
      final v1 = vault([ring]);
      await v1.unlock();
      await v1.idle();
      final other = KeyHierarchy.newMasterKey();
      ring
        ..availabilityValue = StoreAvailability.available
        ..stored = Uint8List.fromList(other);
      final refusing = _NoArchiveStore(ring);
      final v2 = vault([refusing]);
      await v2.unlock();
      await v2.idle();
      expect(await v2.moveTo(KeyStoreKind.keyring), isFalse);
      expect(ring.stored, other);
      expect(v2.status.store, KeyStoreKind.file);
    });

    test("a key left in a store is reused", () async {
      final ring = FakeStore()..stored = KeyHierarchy.newMasterKey();
      final kept = Uint8List.fromList(ring.stored!);
      final status = await vault([ring]).unlock();
      expect(status.store, KeyStoreKind.keyring);
      expect(ring.writes, 0);
      expect((await KeystoreFile(keys).read())!.check,
          await KeyHierarchy.checkValue(kept));
    });

    test("restart finds the same key and derives the same database keys",
        () async {
      final ring = FakeStore();
      final first = vault([ring]);
      await first.unlock();
      final k1 = await first.newDatabaseKey(DatabaseRole.data, "acc");
      final second = vault([ring]);
      expect((await second.unlock()).state, VaultState.ready);
      final k2 = await second.existingDatabaseKey(DatabaseRole.data, "acc");
      expect(k2, k1);
      expect(
          await second.existingDatabaseKey(DatabaseRole.data, "other"), isNull);
      expect(await second.existingDatabaseKey(DatabaseRole.appData, null),
          isNotNull);
      // Different roles and accounts get different keys.
      expect(await second.newDatabaseKey(DatabaseRole.searchIndex, "acc"),
          isNot(k1));
      expect(
          await second.newDatabaseKey(DatabaseRole.data, "other"), isNot(k1));
    });

    test("never a new key when the recorded one is gone", () async {
      final ring = FakeStore();
      await vault([ring]).unlock();
      final before = File(p.join(keys, "keystore.json")).readAsStringSync();

      ring.stored = null;
      expect((await vault([ring]).unlock()).state, VaultState.missing);

      ring.stored = KeyHierarchy.newMasterKey();
      expect((await vault([ring]).unlock()).state, VaultState.missing);

      ring.availabilityValue = StoreAvailability.unavailable;
      expect((await vault([ring]).unlock()).state, VaultState.unavailable);

      ring.availabilityValue = StoreAvailability.locked;
      expect((await vault([ring]).unlock(interactive: true)).state,
          VaultState.locked);

      expect((await vault([]).unlock()).state, VaultState.unavailable);

      expect(File(p.join(keys, "keystore.json")).readAsStringSync(), before);
      expect(File(p.join(keys, "master.key")).existsSync(), isFalse);
    });

    test("a vault that isn't ready derives nothing", () async {
      final ring = FakeStore();
      await vault([ring]).unlock();
      ring.stored = null;
      final v = vault([ring]);
      await v.unlock();
      expect(() => v.existingDatabaseKey(DatabaseRole.appData, null),
          throwsA(isA<VaultNotReady>()));
      expect(() => v.newDatabaseKey(DatabaseRole.data, "acc"),
          throwsA(isA<VaultNotReady>()));
    });

    test("headless engines don't create a keystore or salts", () async {
      final ring = FakeStore();
      final headless = vault([ring], allowCreate: false);
      expect((await headless.unlock()).state, VaultState.noKeystore);
      expect(ring.stored, isNull);
      expect(File(p.join(keys, "keystore.json")).existsSync(), isFalse);

      await vault([ring]).unlock();
      final reader = vault([ring], allowCreate: false);
      expect((await reader.unlock()).state, VaultState.ready);
      expect(() => reader.newDatabaseKey(DatabaseRole.data, "acc"),
          throwsA(isA<VaultNotReady>()));
    });

    test("a salt added by another engine is picked up", () async {
      final ring = FakeStore();
      final ui = vault([ring]);
      await ui.unlock();
      final reader = vault([ring], allowCreate: false);
      await reader.unlock();
      final key = await ui.newDatabaseKey(DatabaseRole.data, "acc");
      expect(await reader.existingDatabaseKey(DatabaseRole.data, "acc"), key);
    });

    test("key file moves to a keyring that appears, unless pinned", () async {
      final ring = FakeStore(availabilityValue: StoreAvailability.unavailable);
      final v1 = vault([ring]);
      await v1.unlock();
      expect(v1.status.store, KeyStoreKind.file);
      final dbKey = await v1.newDatabaseKey(DatabaseRole.data, "acc");

      ring.availabilityValue = StoreAvailability.available;
      final v2 = vault([ring]);
      await v2.unlock();
      // The move runs after unlock returns.
      for (var i = 0; i < 50 && v2.status.store != KeyStoreKind.keyring; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(v2.status.store, KeyStoreKind.keyring);
      expect(v2.status.fileNoticeDue, isFalse);
      expect(File(p.join(keys, "master.key")).existsSync(), isFalse);
      expect(await v2.existingDatabaseKey(DatabaseRole.data, "acc"), dbKey);

      // Back to the file, pinned: no automatic move.
      expect(await v2.moveTo(KeyStoreKind.file, pin: true), isTrue);
      expect(ring.stored, isNull);
      final v3 = vault([ring]);
      await v3.unlock();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(v3.status.store, KeyStoreKind.file);
      expect(await v3.existingDatabaseKey(DatabaseRole.data, "acc"), dbKey);
    });

    test("a key file left by an interrupted move is deleted", () async {
      final ring = FakeStore();
      final v1 = vault([ring]);
      await v1.unlock();
      await FileKeyStore(keys).write(ring.stored!);
      final v2 = vault([ring]);
      await v2.unlock();
      for (var i = 0;
          i < 50 && File(p.join(keys, "master.key")).existsSync();
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(File(p.join(keys, "master.key")).existsSync(), isFalse);
    });

    test("data wiped while running: new files get a recorded salt", () async {
      final ring = FakeStore();
      final v = vault([ring]);
      await v.unlock();
      final oldKey = await v.newDatabaseKey(DatabaseRole.data, "acc");
      final oldAppData = await v.newDatabaseKey(DatabaseRole.appData, null);
      await Directory(keys).delete(recursive: true);

      // appData has a salt in memory, but it isn't recorded any more.
      final appData = await v.newDatabaseKey(DatabaseRole.appData, null);
      expect(v.status.state, VaultState.ready);
      expect(appData, isNot(oldAppData));
      final account = await v.newDatabaseKey(DatabaseRole.data, "acc");
      expect(account, isNot(oldKey));

      // The key in the keyring is reused and the new salts are on disk: a
      // second run derives the same keys.
      expect(ring.writes, 1);
      final again = vault([ring]);
      await again.unlock();
      expect(
          await again.existingDatabaseKey(DatabaseRole.data, "acc"), account);
      expect(await again.newDatabaseKey(DatabaseRole.appData, null), appData);
    });

    test("signing out sweeps copies of the old document a crash left",
        () async {
      final ui = vault([FakeStore()]);
      await ui.unlock();
      await ui.newDatabaseKey(DatabaseRole.data, "acc");
      await ui.idle();
      // A crash mid-write: a copy that still holds the account's salt.
      final leftover = File(p.join(keys, "keystore.json.deadbeef.tmp"))
        ..writeAsStringSync(
            File(p.join(keys, "keystore.json")).readAsStringSync());
      await ui.forgetAccount("acc");
      expect(leftover.existsSync(), isFalse);
      expect(await ui.existingDatabaseKey(DatabaseRole.data, "acc"), isNull);
    });

    test("a headless engine queues a sign-out for the UI engine", () async {
      final ring = FakeStore();
      final ui = vault([ring]);
      await ui.unlock();
      await ui.newDatabaseKey(DatabaseRole.data, "acc");
      await ui.idle();
      final before = File(p.join(keys, "keystore.json")).readAsStringSync();

      final headless = vault([ring], allowCreate: false);
      await headless.unlock();
      await headless.forgetAccount("acc");
      expect(File(p.join(keys, "keystore.json")).readAsStringSync(), before);
      expect(await headless.queuedForgets(), ["acc"]);

      final next = vault([ring]);
      await next.unlock();
      await next.idle();
      expect(await next.existingDatabaseKey(DatabaseRole.data, "acc"), isNull);
      expect(await next.queuedForgets(), isEmpty);
    });

    test("a headless engine that becomes the UI engine forgets the queue",
        () async {
      final ring = FakeStore();
      final ui = vault([ring]);
      await ui.unlock();
      await ui.newDatabaseKey(DatabaseRole.data, "acc");
      await ui.idle();
      final engine = vault([ring], allowCreate: false);
      await engine.unlock();
      await engine.forgetAccount("acc");
      await engine.becomeUiEngine(interactive: false);
      expect(
          await engine.existingDatabaseKey(DatabaseRole.data, "acc"), isNull);
      expect(await engine.queuedForgets(), isEmpty);
    });

    test("forgetting database keys keeps those still needed", () async {
      final ring = FakeStore();
      final v = vault([ring]);
      await v.unlock();
      final a = await v.newDatabaseKey(DatabaseRole.data, "a");
      await v.newDatabaseKey(DatabaseRole.data, "b");
      await v.forgetDatabaseKeys(keep: {"a"});
      expect(await v.existingDatabaseKey(DatabaseRole.data, "a"), a);
      expect(await v.existingDatabaseKey(DatabaseRole.data, "b"), isNull);
      expect(v.hasDatabaseKeysExcept({"a"}), isFalse);
      expect(v.hasDatabaseKeys, isTrue);
    });

    test("status never shows key material", () async {
      final ring = FakeStore();
      final v = vault([ring]);
      await v.unlock();
      final m = ring.stored!;
      for (final text in [v.toString(), v.status.toString()]) {
        expect(text, isNot(contains(KeyHierarchy.hex(m))));
        expect(text, isNot(contains(base64.encode(m))));
      }
      final json = File(p.join(keys, "keystore.json")).readAsStringSync();
      expect(json, isNot(contains(KeyHierarchy.hex(m))));
      expect(json, isNot(contains(base64.encode(m))));
    });
  });

  group("review 2", () {
    test("a lock whose token can't be written is removed and the error thrown",
        () async {
      KeystoreFile.debugWriteToken =
          (lock, token) async => throw const FileSystemException("disk full");
      addTearDown(() => KeystoreFile.debugWriteToken = null);
      final file = KeystoreFile(keys);
      await expectLater(
          file.locked(() async => "ran"), throwsA(isA<FileSystemException>()));
      expect(File(p.join(keys, ".lock")).existsSync(), isFalse);
      KeystoreFile.debugWriteToken = null;
      expect(await file.locked(() async => "ran"), "ran");
    });

    test("a holder that lost the lock doesn't write keystore.json", () async {
      final file = KeystoreFile(keys);
      final first =
          KeystoreDocument.create(store: KeyStoreKind.file, check: "a" * 16);
      await file.locked(() => file.write(first));
      await expectLater(file.locked(() async {
        // Another engine took the lock over meanwhile.
        File(p.join(keys, ".lock")).writeAsStringSync("someone else");
        await file.write(
            KeystoreDocument.create(store: KeyStoreKind.file, check: "b" * 16));
      }), throwsA(isA<KeystoreBusy>()));
      expect((await file.read())!.check, "a" * 16);
      // Outside the lock nothing is checked (tests, tools).
      expect(File(p.join(keys, ".lock")).readAsStringSync(), "someone else");
    });

    test("the temp sweep runs under the lock and keeps fresh lock copies",
        () async {
      final file = KeystoreFile(keys,
          staleAfter: const Duration(seconds: 30),
          waitFor: const Duration(milliseconds: 300));
      await file.ensureDirectory();
      final temp = File(p.join(keys, "keystore.json.cafe.tmp"))
        ..writeAsStringSync("x");
      final fresh = File(p.join(keys, ".lock.stale-1"))..writeAsStringSync("t");
      final old = File(p.join(keys, ".lock.stale-2"))
        ..writeAsStringSync("t")
        ..setLastModifiedSync(
            DateTime.now().subtract(const Duration(minutes: 5)));
      // Held by another engine (mid-write, say): skipped.
      await file.locked(() async {
        await KeystoreFile(keys, waitFor: const Duration(milliseconds: 300))
            .sweepTemporaryFiles();
        expect(temp.existsSync(), isTrue);
      });
      await file.sweepTemporaryFiles();
      expect(temp.existsSync(), isFalse);
      expect(old.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(File(p.join(keys, ".lock")).existsSync(), isFalse);
    });

    test("no keys folder is made by a sweep", () async {
      await KeystoreFile(keys).sweepTemporaryFiles();
      expect(Directory(keys).existsSync(), isFalse);
    });

    test("a store that can't be read now is neither set aside nor written",
        () async {
      final ring = FakeStore(availabilityValue: StoreAvailability.unavailable);
      final v = vault([ring]);
      await v.unlock();
      await v.idle();
      expect(v.status.store, KeyStoreKind.file);
      final other = KeyHierarchy.newMasterKey();
      ring
        ..availabilityValue = StoreAvailability.available
        ..stored = Uint8List.fromList(other)
        ..forcedRead = const StoreUnreachable("D-Bus timeout");
      expect(await v.moveTo(KeyStoreKind.keyring), isFalse);
      expect(ring.archived, isEmpty);
      expect(ring.writes, 0);
      expect(ring.stored, other);
      expect(v.status.store, KeyStoreKind.file);
    });

    test("an item that isn't a key is set aside before a move", () async {
      final ring = FakeStore(availabilityValue: StoreAvailability.unavailable);
      final v = vault([ring]);
      await v.unlock();
      await v.idle();
      final junk = Uint8List.fromList([1, 2, 3]);
      ring
        ..availabilityValue = StoreAvailability.available
        ..stored = junk
        ..forcedRead = const StoreNotAKey("isn't a key");
      expect(await v.moveTo(KeyStoreKind.keyring), isTrue);
      expect(ring.archived, [junk]);
      expect(v.status.store, KeyStoreKind.keyring);
    });

    test("set-aside keys are capped", () async {
      final ring = FakeStore(availabilityValue: StoreAvailability.unavailable);
      final v = vault([ring]);
      await v.unlock();
      await v.idle();
      ring.archived
          .addAll([for (var i = 0; i < 4; i++) KeyHierarchy.newMasterKey()]);
      final other = KeyHierarchy.newMasterKey();
      ring
        ..availabilityValue = StoreAvailability.available
        ..stored = Uint8List.fromList(other);
      expect(await v.moveTo(KeyStoreKind.keyring), isTrue);
      expect(ring.archived.length, MasterKeyStore.archivesKept);
      expect(ring.archived.last, other);
    });

    test("the key file keeps its newest archives only", () async {
      await Directory(keys).create(recursive: true);
      for (final ms in [100, 300, 200, 500, 400]) {
        File(p.join(keys, "master.key.archived-$ms")).writeAsStringSync("k");
      }
      await FileKeyStore(keys).pruneArchives(keep: 3);
      final left = Directory(keys)
          .listSync()
          .map((e) => p.basename(e.path))
          .toList()
        ..sort();
      expect(left, [
        "master.key.archived-300",
        "master.key.archived-400",
        "master.key.archived-500"
      ]);
    });

    test("plaintext key-file archives go once the key is in a keyring",
        () async {
      final ring = FakeStore(availabilityValue: StoreAvailability.unavailable);
      final v1 = vault([ring]);
      await v1.unlock();
      await v1.idle();
      final archive = File(p.join(keys, "master.key.archived-123"))
        ..writeAsStringSync("an old key");
      ring.availabilityValue = StoreAvailability.available;
      expect(await v1.moveTo(KeyStoreKind.keyring), isTrue);
      expect(archive.existsSync(), isFalse);
      expect(File(p.join(keys, "master.key")).existsSync(), isFalse);

      // And at a start where the key is already in the keyring.
      archive.writeAsStringSync("another old key");
      final v2 = vault([ring]);
      await v2.unlock();
      await v2.idle();
      for (var i = 0; i < 50 && archive.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(archive.existsSync(), isFalse);
    });

    test("the recorded key is found among set-aside keys and put back",
        () async {
      final ring = FakeStore();
      final v1 = vault([ring]);
      await v1.unlock();
      final dbKey = await v1.newDatabaseKey(DatabaseRole.data, "acc");
      await v1.idle();
      final ours = Uint8List.fromList(ring.stored!);
      // Set aside (by an older build, or by hand), another key in its place.
      await ring.archive();
      ring.stored = KeyHierarchy.newMasterKey();

      // A headless engine only uses it.
      final reader = vault([ring], allowCreate: false);
      expect((await reader.unlock()).state, VaultState.ready);
      expect(await reader.existingDatabaseKey(DatabaseRole.data, "acc"), dbKey);
      expect(ring.stored, isNot(ours));

      final ui = vault([ring]);
      expect((await ui.unlock()).state, VaultState.ready);
      expect(await ui.existingDatabaseKey(DatabaseRole.data, "acc"), dbKey);
      expect(ring.stored, ours);
      // What was there is set aside in turn, not lost.
      expect(ring.archived.length, 2);
      expect(ring.archived.last, isNot(ours));
    });

    test(
        "restoring from the oldest kept archive with a failing write keeps "
        "that archive", () async {
      final ring = FakeStore();
      final v1 = vault([ring]);
      await v1.unlock();
      final dbKey = await v1.newDatabaseKey(DatabaseRole.data, "acc");
      await v1.idle();
      final ours = Uint8List.fromList(ring.stored!);
      await ring.archive();
      // Two newer archives: ours is the oldest of the three kept.
      ring.archived
          .addAll([KeyHierarchy.newMasterKey(), KeyHierarchy.newMasterKey()]);
      ring
        ..stored = KeyHierarchy.newMasterKey()
        ..failWrites = true;

      final ui = vault([ring]);
      expect((await ui.unlock()).state, VaultState.ready);
      expect(await ui.existingDatabaseKey(DatabaseRole.data, "acc"), dbKey);
      expect(ring.archived.any((k) => KeyHierarchy.equal(k, ours)), isTrue);
      // The next start still finds it.
      final again = vault([ring]);
      expect((await again.unlock()).state, VaultState.ready);
      expect(await again.existingDatabaseKey(DatabaseRole.data, "acc"), dbKey);
    });

    test("a key file with another key isn't deleted next to a keyring key",
        () async {
      final ring = FakeStore();
      final v1 = vault([ring]);
      await v1.unlock();
      await v1.idle();
      // The key of other data (a kept copy restored by hand, say).
      final other = KeyHierarchy.newMasterKey();
      await FileKeyStore(keys).write(other);
      final v2 = vault([ring]);
      await v2.unlock();
      await v2.idle();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final left = await FileKeyStore(keys).read();
      expect(left, isA<StoreFound>());
      expect((left as StoreFound).key, other);
    });

    test("a key file set aside is found and put back", () async {
      final v1 = vault([]);
      await v1.unlock();
      final dbKey = await v1.newDatabaseKey(DatabaseRole.data, "acc");
      await v1.idle();
      await FileKeyStore(keys).archive();
      expect(File(p.join(keys, "master.key")).existsSync(), isFalse);
      final v2 = vault([]);
      expect((await v2.unlock()).state, VaultState.ready);
      expect(await v2.existingDatabaseKey(DatabaseRole.data, "acc"), dbKey);
      expect(File(p.join(keys, "master.key")).existsSync(), isTrue);
    });
  });
}

/// A [FakeStore] whose [archive] fails.
class _NoArchiveStore extends MasterKeyStore {
  _NoArchiveStore(this.inner);
  final FakeStore inner;
  @override
  KeyStoreKind get kind => inner.kind;
  @override
  String get name => inner.name;
  @override
  Future<StoreAvailability> availability() => inner.availability();
  @override
  Future<StoreReadResult> read({bool interactive = false}) =>
      inner.read(interactive: interactive);
  @override
  Future<void> write(Uint8List key) => inner.write(key);
  @override
  Future<void> delete() => inner.delete();
  @override
  Future<void> archive() async => throw KeyStoreException("can't");
}
