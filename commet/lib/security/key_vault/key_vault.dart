// Vommet: local data encryption, the KeyVault: finds (or, on a fresh
// install, creates) the install's master key M in the platform's key store,
// verifies it against keystore.json, and derives the per-file keys from it.
// M never leaves this object; only derived keys do.
//
// The decision table (LOCAL-DATA-ENCRYPTION.md §4):
// - no keystore.json: reuse a key a store still holds (reinstall), else make
//   a new M; keep it in the first preferred store that takes it and reads it
//   back, else in the key file (a "no keyring" notice is then due).
// - keystore.json says store X: X's key must match the check value, else
//   the vault is "missing" / "locked" / "unavailable". It never makes a new
//   key over a recorded one: data encrypted with the old one would be lost.
// - only the UI engine ([allowCreate]) creates keys, moves them between
//   stores or writes keystore.json; headless engines (Android push) read
//   (a sign-out there is queued for the UI engine, see [forgetAccount]).
// - a store holding another key is never written over: that key is set
//   aside first ([MasterKeyStore.archive]), so data that still depends on
//   it (a kept copy, another install) isn't lost.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/debug/log.dart';
import 'package:commet/security/key_vault/file_key_store.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/keystore_file.dart';
import 'package:commet/security/key_vault/master_key_store.dart';
import 'package:commet/utils/disk_space.dart';
import 'package:commet/utils/private_files/owner_only.dart';
import 'package:path/path.dart' as p;

enum VaultState {
  /// [KeyVault.unlock] hasn't finished yet.
  starting,

  /// The master key is loaded and matches keystore.json.
  ready,

  /// No keystore.json and this engine may not create one (headless).
  noKeystore,

  /// The store holding the key is locked (keyring not unlocked).
  locked,

  /// The store answered but doesn't have the recorded key (it was deleted,
  /// or holds a different one).
  missing,

  /// The store couldn't be reached (no keyring daemon, D-Bus error, the
  /// key file can't be read, or the store isn't in this build).
  unavailable,

  /// keystore.json is there but can't be read or is from a newer version.
  damaged,

  /// Another engine held keys/.lock for too long.
  busy,
}

class VaultStatus {
  const VaultStatus(this.state,
      {this.store,
      this.fileNoticeDue = false,
      this.fallbackReason,
      this.detail});

  final VaultState state;

  /// Where the key is (or is recorded to be).
  final KeyStoreKind? store;

  /// The one-time "your key is kept in a file" notice is still to be shown.
  final bool fileNoticeDue;

  /// Why the key file is used instead of a keyring, when it is a fallback.
  final String? fallbackReason;

  /// What went wrong, for the error screen's Details (never key material).
  final String? detail;

  bool get isReady => state == VaultState.ready;

  @override
  String toString() =>
      "VaultStatus(${state.name}, store: ${store?.id ?? "none"}"
      "${fileNoticeDue ? ", file notice due" : ""}"
      "${detail != null ? ", $detail" : ""})";
}

/// The vault isn't ready, so a key can't be derived. The database layer
/// turns this into its own typed error.
class VaultNotReady implements Exception {
  VaultNotReady(this.status);
  final VaultStatus status;
  @override
  String toString() => "VaultNotReady: $status";
}

class KeyVault {
  KeyVault({
    required this.keystoreFile,
    required this.fileStore,
    required List<MasterKeyStore> preferredStores,
    required bool allowCreate,
    this.noKeyringReason,
    this.noticeWhenNoKeyring = true,
  })  : _allowCreate = allowCreate,
        preferredStores = List.unmodifiable(preferredStores);

  /// The process-wide vault of this engine, set up by `initKeyVault`.
  static KeyVault? instance;

  final KeystoreFile keystoreFile;
  final FileKeyStore fileStore;

  /// Stores to keep a new key in, best first. The key file is the fallback
  /// after all of them and isn't listed.
  final List<MasterKeyStore> preferredStores;

  /// Whether this engine may create the key, move it or write keystore.json.
  bool get allowCreate => _allowCreate;
  bool _allowCreate;

  /// A headless engine that became the app's UI engine (Android: opened
  /// after a push started it) may now create keys; an unlock that failed
  /// because there was no keystore yet is tried again. [interactive] is
  /// false while local data encryption is off: the media key alone never
  /// asks for the keyring's password.
  Future<VaultStatus> becomeUiEngine({bool interactive = true}) async {
    final wasReady = _status.isReady;
    _allowCreate = true;
    final status = await unlock(interactive: interactive);
    // Ready already as a headless engine: the UI engine's housekeeping
    // (sign-outs queued by headless engines) runs now.
    if (wasReady && status.isReady) {
      try {
        await _forgetQueued();
      } catch (_) {
        // Tried again at the next start.
      }
    }
    return status;
  }

  /// Recorded as the fallback reason when there are no preferred stores at
  /// all (e.g. "macOS builds aren't signed yet").
  final String? noKeyringReason;

  /// Whether falling back to the key file marks the one-time notice as due.
  final bool noticeWhenNoKeyring;

  Uint8List? _master;
  KeystoreDocument? _doc;
  VaultStatus _status = const VaultStatus(VaultState.starting);
  Future<VaultStatus>? _unlocking;
  final _changes = StreamController<VaultStatus>.broadcast();

  VaultStatus get status => _status;
  Stream<VaultStatus> get onStatusChanged => _changes.stream;

  void _setStatus(VaultStatus status) {
    _status = status;
    _changes.add(status);
  }

  VaultStatus _statusFor(VaultState state, {KeyStoreKind? store, String? d}) {
    final doc = _doc;
    return VaultStatus(state,
        store: store ?? doc?.store,
        fileNoticeDue: doc?.fileNoticeDue ?? false,
        fallbackReason: doc?.fallbackReason,
        detail: d);
  }

  MasterKeyStore? storeFor(KeyStoreKind kind) {
    if (kind == KeyStoreKind.file) return fileStore;
    for (final store in preferredStores) {
      if (store.kind == kind) return store;
    }
    return null;
  }

  /// Loads (or creates) the master key. Safe to call again (Retry); a call
  /// while one is running joins it. [interactive] lets a locked keyring ask
  /// the user for its password.
  Future<VaultStatus> unlock({bool interactive = false}) {
    if (_status.isReady) return Future.value(_status);
    return _unlocking ??= _unlock(interactive).whenComplete(() {
      _unlocking = null;
    });
  }

  Future<VaultStatus> _unlock(bool interactive) async {
    VaultStatus result;
    try {
      result = await _load(interactive);
    } on KeystoreUnreadable catch (e) {
      result = VaultStatus(VaultState.damaged, detail: e.message);
    } on KeystoreBusy catch (e) {
      result = VaultStatus(VaultState.busy, detail: e.toString());
    } on KeyStoreException catch (e) {
      result = _statusFor(VaultState.unavailable, d: e.reason);
    } on FileSystemException catch (e) {
      result = _statusFor(VaultState.unavailable,
          d: "can't read the keys folder: ${e.message}");
    }
    _setStatus(result);
    if (result.isReady && allowCreate) {
      final after = _afterReady();
      _housekeeping = after;
      unawaited(after);
    }
    return result;
  }

  Future<void>? _housekeeping;

  /// Completes when the background work after unlocking (moving the key to
  /// a keyring, deleting a key file left behind) is done. For tests, which
  /// delete the keys folder afterwards.
  Future<void> idle() async => await _housekeeping;

  Future<VaultStatus> _load(bool interactive) async {
    var doc = await keystoreFile.read();
    if (doc == null) {
      if (!allowCreate) {
        return const VaultStatus(VaultState.noKeystore);
      }
      await keystoreFile.sweepTemporaryFiles();
      // A locked keyring is unlocked before the lock is taken: its prompt
      // may take minutes, and keys/.lock is never held across one. The key
      // it may hide must be found before a new one is made (Start over
      // with a kept copy relies on it).
      if (interactive) await _unlockPreferredStores();
      final (created, again) = await keystoreFile.locked(() async {
        // Another engine may have created it while this one waited.
        final again = await keystoreFile.read();
        if (again != null) return (null, again);
        return (await _create(false), null);
      });
      if (created != null) return created;
      return _open(again!, interactive);
    }
    return _open(doc, interactive);
  }

  Future<VaultStatus> _open(KeystoreDocument doc, bool interactive) async {
    _doc = doc;
    final kind = doc.store!;
    final store = storeFor(kind);
    if (store == null) {
      return _statusFor(VaultState.unavailable,
          d: "the key is kept in the ${kind.id} store, which this build "
              "doesn't support");
    }
    final result = await store.read(interactive: interactive);
    switch (result) {
      case StoreFound(:final key):
        if (key.length == KeyHierarchy.keyLength &&
            await KeyHierarchy.checkValue(key) == doc.check) {
          _master = key;
          return _statusFor(VaultState.ready);
        }
        return await _fromArchive(doc, store) ??
            _statusFor(VaultState.missing,
                d: "the ${store.name} holds a different key");
      case StoreEmpty():
        return await _fromArchive(doc, store) ??
            _statusFor(VaultState.missing,
                d: "the ${store.name} doesn't have the key");
      case StoreLocked():
        return _statusFor(VaultState.locked, d: "the ${store.name} is locked");
      case StoreUnreachable(:final reason):
        return _statusFor(VaultState.unavailable, d: reason);
    }
  }

  /// The recorded key, found among the keys the stores set aside
  /// ([MasterKeyStore.archive]) when [store] doesn't have it: the check
  /// value in keystore.json tells which. The UI engine puts it back in
  /// [store] (setting aside what is there now); a headless engine only
  /// uses it. Null when no archive holds it.
  Future<VaultStatus?> _fromArchive(
      KeystoreDocument doc, MasterKeyStore store) async {
    Uint8List? found;
    for (final candidate in {store, ...preferredStores, fileStore}) {
      final List<Uint8List> keys;
      try {
        keys = await candidate.archivedKeys();
      } catch (_) {
        continue;
      }
      for (final key in keys) {
        if (found == null && await KeyHierarchy.checkValue(key) == doc.check) {
          found = key;
        } else {
          key.fillRange(0, key.length, 0);
        }
      }
      if (found != null) break;
    }
    if (found == null) return null;
    _master = found;
    if (allowCreate) {
      try {
        final reason =
            // No pruning on the way: the archive being restored from may be
            // the oldest kept one, and the write may still fail.
            await keystoreFile
                .locked(() => _tryKeep(store, found!, false, prune: false));
        if (reason != null) {
          Log.w("The local data key was found set aside, but couldn't be "
              "put back in the ${store.name}: $reason (used from its archive, "
              "which stays)");
        } else {
          Log.i("The local data key was found set aside and put back in the "
              "${store.name}");
        }
      } catch (e) {
        Log.w("Couldn't put the local data key back: ${e.runtimeType}");
      }
    }
    return _statusFor(VaultState.ready);
  }

  /// A fresh keystore. Call holding the lock.
  Future<VaultStatus> _create(bool interactive) async {
    // A store may still hold a key from before the app's data was wiped
    // (iOS keeps the Keychain across reinstalls). Reusing it is harmless
    // and keeps any database it encrypted readable.
    // A store that is still locked here may hide a key: [_tryKeep] never
    // writes over it (it reads and sets aside what it finds first).
    Uint8List? master;
    MasterKeyStore? holder;
    for (final store in [...preferredStores, fileStore]) {
      final found = await store.read(interactive: interactive);
      if (found is StoreFound && found.key.length == KeyHierarchy.keyLength) {
        master = found.key;
        holder = store;
        break;
      }
    }
    master ??= KeyHierarchy.newMasterKey();

    MasterKeyStore? chosen = holder != fileStore ? holder : null;
    final failures = <String>[];
    if (chosen == null) {
      for (final store in preferredStores) {
        final reason = await _tryKeep(store, master, interactive);
        if (reason == null) {
          chosen = store;
          break;
        }
        failures.add("${store.name}: $reason");
      }
    }

    final String? fallbackReason;
    if (chosen == null) {
      final reason = await _tryKeep(fileStore, master, false);
      if (reason != null) {
        throw KeyStoreException("no store could keep the key (${[
          ...failures,
          reason
        ].join("; ")})");
      }
      chosen = fileStore;
      fallbackReason = failures.isEmpty ? noKeyringReason : failures.join("; ");
    } else {
      fallbackReason = null;
    }

    final doc = KeystoreDocument.create(
        store: chosen.kind, check: await KeyHierarchy.checkValue(master));
    if (chosen == fileStore) {
      doc.setFileFallback(
          noticeDue: noticeWhenNoKeyring &&
              (preferredStores.isNotEmpty || noKeyringReason == null),
          reason: fallbackReason);
    }
    await keystoreFile.write(doc);
    _doc = doc;
    _master = master;
    return _statusFor(VaultState.ready);
  }

  /// Asks each locked preferred store to unlock (the system's prompt).
  Future<void> _unlockPreferredStores() async {
    for (final store in preferredStores) {
      try {
        if (await store.availability() != StoreAvailability.locked) continue;
        final found = await store.read(interactive: true);
        if (found is StoreFound) found.key.fillRange(0, found.key.length, 0);
      } catch (_) {}
    }
  }

  /// Writes [key] to [store] and reads it back. Null on success, else why
  /// not (the store is left without a half-written key where possible).
  ///
  /// Never writes over another key: what the store holds is read first
  /// (unlocking it, when [interactive]); the same key is already kept, and a
  /// different one (or an item that isn't a key) is set aside with
  /// [MasterKeyStore.archive] before [key] is written. When it can't be set
  /// aside, [key] isn't kept there. A store that can't be read right now
  /// ([StoreUnreachable], not [StoreNotAKey]) is left alone: a read that
  /// failed once is no evidence that the key there is gone. Old archives
  /// are pruned ([MasterKeyStore.pruneArchives]) only once [key] reads back
  /// from the store, and never with [prune] false.
  Future<String?> _tryKeep(
      MasterKeyStore store, Uint8List key, bool interactive,
      {bool prune = true}) async {
    final availability = await store.availability();
    if (availability == StoreAvailability.unavailable) return "not available";
    if (availability == StoreAvailability.locked && !interactive) {
      return "locked";
    }
    // Unlocking happens through a read.
    final current = await store.read(
        interactive: availability == StoreAvailability.locked && interactive);
    switch (current) {
      case StoreLocked():
        return "locked";
      case StoreEmpty():
        break;
      case StoreFound(key: final held) when KeyHierarchy.equal(held, key):
        return null;
      case StoreFound():
      case StoreNotAKey():
        // Known for sure to be another key (or not a key at all): set
        // aside, never written over.
        final reason = current is StoreNotAKey ? current.reason : null;
        try {
          await store.archive();
        } on KeyStoreException catch (e) {
          return reason ??
              "it holds another key, which couldn't be set aside (${e.reason})";
        }
        if (await store.read() is! StoreEmpty) {
          return reason ?? "it holds another key, which couldn't be set aside";
        }
      case StoreUnreachable(:final reason):
        // May pass (a D-Bus hiccup, a timeout): what the store holds is
        // left alone, not set aside on a guess.
        return reason;
    }
    try {
      await store.write(key);
    } on KeyStoreException catch (e) {
      return e.reason;
    }
    final back = await store.read();
    if (back is StoreFound && KeyHierarchy.equal(back.key, key)) {
      if (prune) {
        try {
          await store.pruneArchives();
        } catch (_) {}
      }
      return null;
    }
    try {
      await store.delete();
    } catch (_) {}
    return "the key didn't read back";
  }

  /// Housekeeping once the key is loaded: a key file left by an
  /// interrupted move is deleted, and a key in the file moves to a keyring
  /// that has appeared (unless the user chose the file).
  Future<void> _afterReady() async {
    final doc = _doc;
    if (doc == null) return;
    try {
      await _forgetQueued();
    } catch (_) {
      // Tried again at the next start.
    }
    try {
      if (doc.store != KeyStoreKind.file) {
        // Only once the keyring is seen holding the key (it may be in use
        // from an archive this run, [_fromArchive]).
        if (!await _holdsMaster(storeFor(doc.store!))) return;
        // A key file is deleted only when it holds this same key (left by
        // an interrupted move); another key there is never deleted on a
        // guess (it may be the only key of other data).
        final left = await fileStore.read();
        if (left is StoreFound) {
          final same = KeyHierarchy.equal(left.key, _master!);
          left.key.fillRange(0, left.key.length, 0);
          if (same) {
            await fileStore.delete();
          } else {
            Log.w("A key file with another key is next to the local data; "
                "it is left as it is");
          }
        }
        // Plaintext keys set aside by the key file: not left next to the
        // databases once the key is protected by a keyring.
        await fileStore.pruneArchives(keep: 0);
      } else if (!doc.pinnedToFile && preferredStores.isNotEmpty) {
        for (final store in preferredStores) {
          if (await store.availability() != StoreAvailability.available) {
            continue;
          }
          if (await moveTo(store.kind)) break;
        }
      }
    } catch (_) {
      // Retried on the next start.
    }
  }

  /// Whether [store] reads back the loaded master key.
  Future<bool> _holdsMaster(MasterKeyStore? store) async {
    final master = _master;
    if (store == null || master == null) return false;
    final found = await store.read();
    if (found is! StoreFound) return false;
    final same = KeyHierarchy.equal(found.key, master);
    found.key.fillRange(0, found.key.length, 0);
    return same;
  }

  /// Moves the key to [target] (the settings page; automatic for file →
  /// keyring). With [pin], a move to the key file sticks (no automatic move
  /// back). Returns false when [target] couldn't keep it; the key stays
  /// where it was.
  Future<bool> moveTo(KeyStoreKind target,
      {bool pin = false, bool interactive = false}) async {
    final master = _master;
    if (master == null || !allowCreate) throw VaultNotReady(_status);
    final store = storeFor(target);
    if (store == null) return false;
    // Unlocked before keys/.lock is taken (never held across a prompt).
    if (interactive && await store.availability() == StoreAvailability.locked) {
      final found = await store.read(interactive: true);
      if (found is StoreFound) found.key.fillRange(0, found.key.length, 0);
    }
    return keystoreFile.locked(() async {
      final doc = await keystoreFile.read();
      if (doc == null || doc.check != _doc?.check) return false;
      final from = doc.store!;
      if (from == target) {
        if (target == KeyStoreKind.file && doc.pinnedToFile != pin) {
          doc.pinnedToFile = pin;
          await keystoreFile.write(doc);
          _doc = doc;
        }
        return true;
      }
      if (await _tryKeep(store, master, false) != null) return false;
      doc.store = target;
      if (target == KeyStoreKind.file) {
        doc.pinnedToFile = pin;
      } else {
        doc.pinnedToFile = false;
        doc.clearFileFallback();
      }
      // keystore.json decides: once it names the new store, the old copy is
      // only a leftover.
      await keystoreFile.write(doc);
      _doc = doc;
      try {
        await storeFor(from)?.delete();
      } catch (_) {}
      if (target != KeyStoreKind.file) {
        // The key file's plaintext archives go with it.
        try {
          await fileStore.pruneArchives(keep: 0);
        } catch (_) {}
      }
      _setStatus(_statusFor(VaultState.ready));
      return true;
    });
  }

  /// The notice was shown; it isn't due any more.
  Future<void> acknowledgeFileNotice() async {
    if (!allowCreate) return;
    final doc = await keystoreFile.update((doc) {
      if (!doc.fileNoticeDue) return false;
      doc.markFileNoticeShown();
      return true;
    });
    if (doc != null) {
      _doc = doc;
      _setStatus(_statusFor(_status.state));
    }
  }

  Uint8List _requireMaster() {
    final master = _master;
    if (master == null) throw VaultNotReady(_status);
    return master;
  }

  /// The database key of an existing encrypted file, or null when there is
  /// no salt for it (it was never encrypted here). Re-reads keystore.json
  /// when the salt isn't known yet (another engine may have added it).
  Future<Uint8List?> existingDatabaseKey(
      DatabaseRole role, String? account) async {
    final master = _requireMaster();
    var salt = _doc?.saltFor(role, account);
    if (salt == null) {
      final fresh = await keystoreFile.read();
      if (fresh != null && fresh.check == _doc?.check) {
        _doc = fresh;
        salt = fresh.saltFor(role, account);
      }
    }
    if (salt == null) return null;
    return KeyHierarchy.databaseKey(master, salt, role);
  }

  /// The key for a database about to be created encrypted. Gives the
  /// account a salt first (recorded in keystore.json before any file is
  /// written with it).
  ///
  /// The UI engine checks keystore.json first: when it is gone (the app's
  /// data was wiped while it ran) the vault starts over as on a first run,
  /// so a new file is never keyed with a salt that is no longer recorded.
  Future<Uint8List> newDatabaseKey(DatabaseRole role, String? account) async {
    _requireMaster();
    if (role.perAccount && account == null) {
      throw ArgumentError("an account database needs an account");
    }
    if (!allowCreate) {
      // Headless engines don't write keystore.json: a known salt only.
      final salt = _doc?.saltFor(role, account);
      if (salt == null) throw VaultNotReady(_status);
      return KeyHierarchy.databaseKey(_requireMaster(), salt, role);
    }
    // appData always has a salt, so only an account may need one.
    bool addSalt(KeystoreDocument doc) =>
        role.perAccount && doc.ensureAccountSalt(account!);
    KeystoreDocument? doc;
    try {
      doc = await keystoreFile.update(addSalt);
      if (doc == null) {
        // Files encrypted before the wipe keep failing closed: their salts
        // went with it and are never made up again.
        final status = await _restartAfterWipe();
        if (!status.isReady) throw VaultNotReady(status);
        doc = await keystoreFile.update(addSalt);
      }
    } on KeystoreBusy catch (e) {
      throw VaultNotReady(_statusFor(VaultState.busy, d: e.toString()));
    } on KeystoreUnreadable catch (e) {
      throw VaultNotReady(_statusFor(VaultState.damaged, d: e.message));
    }
    if (doc == null || doc.check != _doc?.check) {
      throw VaultNotReady(_statusFor(VaultState.damaged,
          d: "keystore.json changed while the app was running"));
    }
    _doc = doc;
    return KeyHierarchy.databaseKey(
        _requireMaster(), doc.saltFor(role, account)!, role);
  }

  /// keystore.json disappeared under a ready vault: forget what was loaded
  /// and unlock again, which writes a new one. Only while it is still
  /// missing (another engine may have written it meanwhile).
  Future<VaultStatus> _restartAfterWipe() async {
    if (await keystoreFile.read() == null) {
      // Not zeroed: a key derivation may still be using it.
      _master = null;
      _doc = null;
      _setStatus(const VaultStatus(VaultState.starting));
    }
    return unlock();
  }

  /// Records a database file's state (for the UI, telemetry and the
  /// migration). Headless engines don't write.
  Future<void> recordState(
      DatabaseRole role, String? account, DatabaseEncryptionState state) async {
    if (!allowCreate || _doc == null) return;
    if (_doc!.state(role, account) == state) return;
    final doc =
        await keystoreFile.update((doc) => doc.setState(role, account, state));
    if (doc != null) _doc = doc;
  }

  /// The recorded state of a database file.
  DatabaseEncryptionState? recordedState(DatabaseRole role, String? account) =>
      _doc?.state(role, account);

  /// How many migrations of a file failed in a row.
  int migrationFailures(DatabaseRole role, String? account) =>
      _doc?.migrationFailures(role, account) ?? 0;

  /// Records the failure count of a file's migration (UI engine only).
  Future<void> setMigrationFailures(
      DatabaseRole role, String? account, int count) async {
    if (!allowCreate || _doc == null) return;
    if (_doc!.migrationFailures(role, account) == count) return;
    final doc = await keystoreFile
        .update((doc) => doc.setMigrationFailures(role, account, count));
    if (doc != null) _doc = doc;
  }

  /// Re-reads keystore.json (another engine may have changed the salts or
  /// states). Keeps what was loaded when it can't be read or belongs to
  /// another key.
  Future<void> refresh() async {
    try {
      final fresh = await keystoreFile.read();
      if (fresh != null && fresh.check == _doc?.check) _doc = fresh;
    } catch (_) {}
  }

  /// The media cache's key, from the current media salt. Throws
  /// [VaultNotReady] when the master key isn't loaded.
  Future<Uint8List> mediaKey() async =>
      KeyHierarchy.mediaKey(_requireMaster(), _doc!.mediaSalt);

  /// Identifies the current media key without revealing it (the cache
  /// notices a rotation by another engine through it).
  String? get mediaKeyStamp {
    final doc = _doc;
    if (doc == null) return null;
    return KeyHierarchy.hex(doc.mediaSalt);
  }

  /// A new media salt: every sealed media cache entry becomes unreadable
  /// (sign-out). Any ready engine may do it: keeping the old key around
  /// would be worse than one engine writing keystore.json.
  Future<void> rotateMediaKey() async {
    _requireMaster();
    final doc = await keystoreFile.update((doc) {
      doc.rotateMediaSalt();
      return true;
    });
    if (doc != null && doc.check == _doc?.check) _doc = doc;
  }

  /// Forgets [account]'s salt (sign-out): the files of it this app still
  /// finds can't be decrypted with the current keystore.json any more. Best
  /// effort, not a cryptographic erase: the master key stays the same, so a
  /// copy of the old keystore.json (a backup of the home folder, a
  /// snapshot, a kept copy) together with a copy of the files still opens
  /// them (LOCAL-DATA-ENCRYPTION.md, sign-out).
  ///
  /// Only the UI engine writes keystore.json: a headless engine queues the
  /// account under keys/forget-queue/, and the UI engine forgets it when
  /// it is next ready.
  Future<void> forgetAccount(String account) async {
    if (!allowCreate) {
      await _queueForget(account);
      return;
    }
    final doc = await keystoreFile.update((doc) {
      if (!doc.accounts.contains(account)) return false;
      doc.removeAccount(account);
      return true;
    });
    if (doc != null && doc.check == _doc?.check) _doc = doc;
    // A crash mid-write may have left a copy of the old document.
    await keystoreFile.sweepTemporaryFiles();
  }

  String get _forgetQueue => p.join(keystoreFile.directory, "forget-queue");

  /// Accounts headless engines signed out, for the UI engine to forget.
  Future<List<String>> queuedForgets() async {
    final dir = Directory(_forgetQueue);
    final found = <String>[];
    try {
      if (!await dir.exists()) return found;
      await for (final entity in dir.list()) {
        try {
          found.add(utf8.decode(base64Url.decode(p.basename(entity.path))));
        } catch (_) {}
      }
    } catch (_) {}
    return found;
  }

  Future<void> _queueForget(String account) async {
    await keystoreFile.ensureDirectory();
    final dir = Directory(_forgetQueue);
    if (!await dir.exists()) await dir.create();
    await OwnerOnly.directory(dir.path);
    final file = File(p.join(dir.path, base64Url.encode(utf8.encode(account))));
    await file.writeAsString("", flush: true);
    DiskSpace.syncDirectory(dir.path);
  }

  /// Forgets what headless engines queued (UI engine only).
  Future<void> _forgetQueued() async {
    for (final account in await queuedForgets()) {
      await forgetAccount(account);
      try {
        await File(p.join(_forgetQueue, base64Url.encode(utf8.encode(account))))
            .delete();
      } catch (_) {}
    }
  }

  /// Whether keystore.json still holds a key of a database that was
  /// encrypted (an account's salt, or an encrypted app_data.db), other
  /// than those of the accounts in [except].
  bool hasDatabaseKeysExcept(Set<String> except) {
    final doc = _doc;
    if (doc == null) return false;
    return doc.accounts
            .any((a) => !except.contains(a) && doc.accountSalt(a) != null) ||
        doc.state(DatabaseRole.appData, null) ==
            DatabaseEncryptionState.encrypted;
  }

  bool get hasDatabaseKeys => hasDatabaseKeysExcept(const {});

  /// Forgets the database keys but keeps the media key (local data
  /// encryption turned off, after the files were decrypted): this
  /// keystore.json no longer opens a database encrypted before. The salts
  /// of the accounts in [keep] stay (their files are still encrypted: they
  /// were skipped or failed, and are decrypted at a later start). UI engine
  /// only.
  Future<void> forgetDatabaseKeys({Set<String> keep = const {}}) async {
    if (!allowCreate) return;
    final doc =
        await keystoreFile.update((doc) => doc.forgetDatabaseKeys(keep: keep));
    if (doc != null && doc.check == _doc?.check) _doc = doc;
    await keystoreFile.sweepTemporaryFiles();
  }

  /// The user chose the key file (no automatic move to a keyring).
  bool get pinnedToFile => _doc?.pinnedToFile ?? false;

  /// Whether a preferred store (a keyring) is there at all, locked or not.
  Future<bool> keyringAvailable() async {
    for (final store in preferredStores) {
      try {
        if (await store.availability() != StoreAvailability.unavailable) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// Forgets everything; for tests.
  Future<void> dispose() async {
    _master?.fillRange(0, _master!.length, 0);
    _master = null;
    await _changes.close();
  }

  @override
  String toString() => "KeyVault($_status)";
}
