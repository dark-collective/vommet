// Vommet: local data encryption, which key a database file is opened with.
// Native platforms only (it reads the file's header).
//
// - A plaintext file (it starts with "SQLite format 3") keeps opening
//   unencrypted and untouched; the one-time migration encrypts it later.
// - A missing file is created encrypted, with a new key from the vault,
//   when local data encryption is on (LocalDataSetting, opt-in, read from
//   the disk each time); plaintext only when the disk says it is off.
// - An encrypted file opens with its key from the vault.
// - While the UI engine migrates a file (its state in keystore.json is
//   "migrating"), a headless engine doesn't open it: [DatabaseKeyError]
//   (migrating). The file is marked in use first (DatabaseInUse), so the
//   migration skips it when it was opened before.
// Fail closed: when the key can't be had, [DatabaseKeyError] (keyUnavailable)
// is thrown. Nothing here ever creates a plaintext database in place of an
// encrypted one while encryption is on, or deletes a file.
import 'dart:typed_data';

import 'package:commet/debug/log.dart';
import 'package:commet/security/database_in_use.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/keystore_file.dart';
import 'package:commet/security/key_vault/platform_key_stores.dart';
import 'package:commet/security/local_data_on_disk.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:path/path.dart' as p;

class DatabaseKeys {
  /// For tests: the vault to use instead of [KeyVault.instance].
  static KeyVault? debugVault;

  /// The key [path] is to be opened with; null opens it as plain SQLite.
  /// [account] is the client name for per-account databases.
  static Future<Uint8List?> forFile(
      String path, DatabaseRole role, String? account,
      {bool readOnly = false}) async {
    DatabaseInUse.mark(path);
    final state = EncryptedOpen.fileState(path);
    switch (state) {
      case DatabaseFileState.plaintext:
        await _refuseWhileMigrating(path, role, account);
        await _record(role, account, DatabaseEncryptionState.plain);
        return null;
      case DatabaseFileState.missing:
        // Nothing to read; opening it read-only fails as it always did.
        if (readOnly) return null;
        // Between the migration's two renames the file is briefly missing:
        // creating it then would hide the real one.
        await _refuseWhileMigrating(path, role, account);
        if (!await encryptsNewFiles()) {
          await _record(role, account, DatabaseEncryptionState.plain);
          return null;
        }
        final vault = await _readyVault(path);
        try {
          final key = await vault.newDatabaseKey(role, account);
          await _record(role, account, DatabaseEncryptionState.encrypted);
          return key;
        } on VaultNotReady catch (e) {
          throw _unavailable(path, e.status);
        }
      case DatabaseFileState.encrypted:
        final vault = await _readyVault(path);
        final Uint8List? key;
        try {
          key = await vault.existingDatabaseKey(role, account);
        } on VaultNotReady catch (e) {
          throw _unavailable(path, e.status);
        }
        if (key == null) {
          throw DatabaseKeyError(DatabaseKeyErrorKind.keyUnavailable,
              "the key store has no key for this ${role.fileName}",
              path: path);
        }
        return key;
    }
  }

  /// For tests: the keys folder to use when there is no vault.
  static String? debugKeysDirectory;

  static Future<String> _keysDirectory(KeyVault? vault) async =>
      vault?.keystoreFile.directory ??
      debugKeysDirectory ??
      await PlatformKeyStores.keysDirectory();

  /// Whether a new database is created encrypted, from the disk alone: the
  /// user's setting; without a setting that can be read, whether anything
  /// there is encrypted (LocalDataOnDisk). Never from what a vault in
  /// memory holds (keys/ may have been wiped under it). When the disk
  /// can't be looked at: encrypted (fail closed: never plaintext while
  /// the setting may be on).
  static Future<bool> encryptsNewFiles() async {
    final vault = debugVault ?? KeyVault.instance;
    try {
      final keys = await _keysDirectory(vault);
      final (setting, _) = await LocalDataOnDisk.setting(p.dirname(keys));
      return setting.encrypt;
    } catch (e) {
      Log.w("Couldn't read the local data setting: ${e.runtimeType}");
      return true;
    }
  }

  /// A headless engine doesn't touch a file the UI engine is migrating.
  /// The state is read from keystore.json each time (the UI engine writes
  /// it), also before this engine has a vault. The UI engine itself runs
  /// the migration before it opens anything.
  static Future<void> _refuseWhileMigrating(
      String path, DatabaseRole role, String? account) async {
    final vault = debugVault ?? KeyVault.instance;
    if (vault != null && vault.allowCreate) return;
    KeystoreDocument? doc;
    try {
      doc = await (vault?.keystoreFile ??
              KeystoreFile(await _keysDirectory(null)))
          .read();
    } catch (_) {
      return;
    }
    if (doc?.state(role, account) == DatabaseEncryptionState.migrating) {
      throw DatabaseKeyError(DatabaseKeyErrorKind.migrating,
          "the app is encrypting this ${role.fileName}; try again later",
          path: path);
    }
  }

  static Future<KeyVault> _readyVault(String path) async {
    var vault = debugVault ?? KeyVault.instance;
    if (vault == null) {
      // An entry point that didn't run the app's start-up is a headless
      // engine (push, background task): set the vault up now, read-only.
      vault = await PlatformKeyStores.init(headless: true);
    }
    if (!vault.status.isReady) {
      // Another engine may have created the keystore meanwhile, or a
      // keyring was unlocked: try once more without prompting.
      await vault.unlock();
    }
    if (!vault.status.isReady) throw _unavailable(path, vault.status);
    return vault;
  }

  static Future<void> _record(
      DatabaseRole role, String? account, DatabaseEncryptionState state) async {
    final vault = debugVault ?? KeyVault.instance;
    if (vault == null || !vault.status.isReady) return;
    try {
      await vault.recordState(role, account, state);
    } catch (e) {
      // Only bookkeeping; the file itself decides how it is opened.
      Log.w("Couldn't record the database state: ${e.runtimeType}");
    }
  }

  static DatabaseKeyError _unavailable(String path, VaultStatus status) =>
      DatabaseKeyError(DatabaseKeyErrorKind.keyUnavailable,
          "the local data key isn't available ($status)",
          path: path);
}
