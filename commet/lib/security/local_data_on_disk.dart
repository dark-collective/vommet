// Vommet: local data encryption, what the disk says about it. Whether new
// databases are encrypted is decided from the disk alone (the setting file,
// else whether anything there is encrypted), never from what a vault in
// memory still holds: keys/ may have been wiped under it, and a setting
// file may be missing or unreadable (LocalDataSetting.resolve).
// Native platforms only.
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/security/key_vault/dpapi_key_store.dart';
import 'package:commet/security/key_vault/file_key_store.dart';
import 'package:commet/security/key_vault/keystore_file.dart';
import 'package:commet/security/key_vault/portal_key_store.dart';
import 'package:commet/security/local_data_setting.dart';
import 'package:commet/security/migration/database_migration.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:commet/utils/disk_space.dart';
import 'package:commet/utils/private_files/owner_only.dart';
import 'package:path/path.dart' as p;

/// What opening an encrypted database with its key showed.
enum DatabaseOpenCheck {
  ok,

  /// Damaged, or the key is wrong (SQLite CORRUPT / NOTADB): seen twice.
  corrupt,

  /// Failed for another reason every time (busy, locked, I/O, can't open):
  /// it may pass, so the file is kept.
  transient,
}

class LocalDataOnDisk {
  /// Waits between tries of [checkOpens] after a failure that may pass
  /// (tests shorten them).
  static List<Duration> openBackoff = const [
    Duration(milliseconds: 300),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  /// Opens [path] with [key] and reads its schema: tried again after each of
  /// [backoff] while it fails, until it is seen corrupt twice in a row.
  static Future<DatabaseOpenCheck> checkOpens(String path, Uint8List key,
      {List<Duration>? backoff}) async {
    final waits = backoff ?? openBackoff;
    var corruptInARow = 0;
    for (var i = 0;; i++) {
      try {
        final db = EncryptedOpen.open(path, key: key);
        try {
          db.select("SELECT count(*) FROM sqlite_master");
          return DatabaseOpenCheck.ok;
        } finally {
          db.close();
        }
      } catch (e) {
        corruptInARow = EncryptedOpen.isCorrupt(e) ? corruptInARow + 1 : 0;
        if (corruptInARow >= 2) return DatabaseOpenCheck.corrupt;
        if (i >= waits.length) {
          return corruptInARow > 0
              ? DatabaseOpenCheck.corrupt
              : DatabaseOpenCheck.transient;
        }
        await Future<void>.delayed(corruptInARow > 0 ? waits.first : waits[i]);
      }
    }
  }

  /// Where kept copies (Start over / Reset with Keep a copy) go: next to
  /// the database folder, except on Android, where everything next to it is
  /// in Auto Backup: there in vommet-kept/, which the backup rules exclude
  /// (vommet_backup_rules.xml, vommet_data_extraction_rules.xml).
  static String keptCopyParent(String databaseDirectory, {bool? android}) =>
      (android ?? Platform.isAndroid)
          ? p.join(p.dirname(databaseDirectory), "vommet-kept")
          : p.dirname(databaseDirectory);

  /// Whether [name] (in keys/) is a master key file of a store, an archive
  /// of one, or a temporary file of one.
  static bool isKeyFile(String name) => const [
        FileKeyStore.fileName,
        DpapiKeyStore.fileName,
        PortalKeyStore.fileName,
      ].any((base) => name == base || name.startsWith("$base."));

  /// Start over with a kept copy: the key files that went with the moved
  /// folder ([keptKeys], its keys/) come back to [keys], so the copy holds
  /// no key (master.key is the plain key) and the next start finds the key
  /// where it was: the copy still opens with it and the copy's
  /// keystore.json. A file that can't be moved back is left in the copy
  /// (never lost); returns how many those are.
  static Future<int> moveKeyFilesBack(String keptKeys, String keys) async {
    final dir = Directory(keptKeys);
    if (!await dir.exists()) return 0;
    var left = 0;
    final files = [
      await for (final entity in dir.list())
        if (entity is File && isKeyFile(p.basename(entity.path))) entity,
    ];
    if (files.isEmpty) return 0;
    try {
      await Directory(keys).create(recursive: true);
      await OwnerOnly.directory(keys);
    } catch (_) {}
    for (final file in files) {
      final target = p.join(keys, p.basename(file.path));
      try {
        if (await FileSystemEntity.type(target) !=
            FileSystemEntityType.notFound) {
          left++;
          continue;
        }
        await file.rename(target);
      } on FileSystemException {
        left++;
      }
    }
    DiskSpace.syncDirectory(keys);
    return left;
  }

  /// The app's database files under [databaseDirectory]: app_data.db and
  /// every account folder's message store and search index (registered or
  /// not: the disk decides).
  static List<String> databaseFiles(String databaseDirectory) {
    final files = [p.join(databaseDirectory, "app", "app_data.db")];
    try {
      final drift = Directory(p.join(databaseDirectory, "account", "drift"));
      if (drift.existsSync()) {
        for (final entity in drift.listSync()) {
          if (entity is! Directory) continue;
          files.add(p.join(entity.path, "data.db"));
          files.add(p.join(entity.path, "search_index.db"));
        }
      }
    } on FileSystemException {
      // Not listable: what is known so far.
    }
    return files;
  }

  /// An encrypted database, or one being converted, is on disk.
  static bool anyEncryptedFile(String databaseDirectory) =>
      databaseFiles(databaseDirectory).any((path) =>
          EncryptedOpen.fileState(path) == DatabaseFileState.encrypted ||
          DatabaseMigrator.hasLeftovers(path));

  /// Whether keystore.json in [keysDirectory] records a database key: null
  /// when it can't be read (unknown). An unreadable keystore.json is no
  /// evidence of encryption: a plaintext user whose keystore.json got
  /// damaged (or root-owned after one `sudo` run) must not be switched to
  /// encryption, or sent to the "key missing" screen, because of it.
  static Future<bool?> keystoreHasDatabaseKeys(String keysDirectory) async {
    try {
      final doc = await KeystoreFile(keysDirectory).read();
      return doc != null && doc.hasDatabaseKeys;
    } on KeystoreUnreadable {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Positive evidence of encryption under [databaseDirectory]: an
  /// encrypted file (or one being converted), or database keys in a
  /// keystore.json that was read. An unreadable keystore.json counts as
  /// no (it is unknown, [keystoreHasDatabaseKeys]); an encrypted file
  /// still fails closed, whatever keystore.json says.
  static Future<bool> hasEncryptedData(String databaseDirectory) async =>
      anyEncryptedFile(databaseDirectory) ||
      await keystoreHasDatabaseKeys(p.join(databaseDirectory, "keys")) == true;

  /// The setting in force for [databaseDirectory], read from the disk.
  static Future<(LocalDataSetting, LocalDataSettingFileState)> setting(
      String databaseDirectory) async {
    final file = LocalDataSetting.load(p.join(databaseDirectory, "keys"));
    if (file.state == LocalDataSettingFileState.ok) {
      return (file.setting!, file.state);
    }
    final setting = LocalDataSetting.resolve(file,
        encryptedOnDisk: await hasEncryptedData(databaseDirectory));
    return (setting, file.state);
  }
}
