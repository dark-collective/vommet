// Vommet: local data encryption, "Export decrypted copy" (debug builds,
// LOCAL-DATA-ENCRYPTION.md §5): writes a plaintext copy of an encrypted
// database, for looking into it with stock tools. sqlite3mc has no
// sqlcipher_export; VACUUM INTO a URI with an empty `key=` writes the copy
// unencrypted (a plain path would inherit the source's cipher).
//
// The copy holds everything the database holds, unencrypted: callers must
// warn first and put it where the user chose.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class DecryptedExportError implements Exception {
  const DecryptedExportError(this.message);
  final String message;

  @override
  String toString() => "DecryptedExportError: $message";
}

class DecryptedExport {
  /// Writes a plaintext copy of [source] (encrypted with [key], or already
  /// plaintext when [key] is null) to [target], which must not exist.
  /// Errors never include the key.
  static void exportSync(String source, Uint8List? key, String target) {
    if (File(target).existsSync()) {
      throw const DecryptedExportError("the target already exists");
    }
    if (key != null) {
      if (key.length != EncryptedOpen.keyLength) {
        throw const DecryptedExportError("the key has the wrong length");
      }
      EncryptedOpen.requireCipher();
    }
    final Database db;
    try {
      db = sqlite3.open(source, uri: true, mode: OpenMode.readOnly);
    } on SqliteException catch (e) {
      throw DecryptedExportError(
          "can't open the database (code ${e.extendedResultCode})");
    }
    try {
      if (key != null) EncryptedOpen.applyKey(db, key, path: source);
      db.execute("VACUUM INTO ?", ["${Uri.file(target)}?key="]);
    } on SqliteException catch (e) {
      throw DecryptedExportError(
          "can't write the copy (code ${e.extendedResultCode})");
    } on DatabaseKeyError catch (e) {
      throw DecryptedExportError("can't decrypt the database (${e.kind.name})");
    } finally {
      db.close();
    }
  }

  /// [exportSync] in a background isolate.
  static Future<void> export(String source, Uint8List? key, String target) =>
      Isolate.run(() => exportSync(source, key, target));

  /// Plaintext copies of the app's databases (app_data.db and each
  /// account's data.db and search_index.db) under [folder]:
  /// "app/app_data.db", "<account>/data.db", … Files that don't exist are
  /// skipped; an encrypted file without a key in [vault] is reported, not
  /// copied. Returns one line per database.
  static Future<List<String>> exportAll({
    required KeyVault vault,
    required String databaseDirectory,
    required List<String> accounts,
    required String folder,
  }) async {
    final drift = p.join(databaseDirectory, "account", "drift");
    final sources = <(String, DatabaseRole, String?, String)>[
      (
        p.join(databaseDirectory, "app", DatabaseRole.appData.fileName),
        DatabaseRole.appData,
        null,
        p.join("app", DatabaseRole.appData.fileName),
      ),
      for (final account in accounts)
        if (p.basename(account) == account)
          for (final role in const [
            DatabaseRole.data,
            DatabaseRole.searchIndex
          ])
            (
              p.join(drift, account, role.fileName),
              role,
              account,
              p.join(account, role.fileName),
            ),
    ];
    final report = <String>[];
    for (final (source, role, account, relative) in sources) {
      final state = EncryptedOpen.fileState(source);
      if (state == DatabaseFileState.missing) continue;
      Uint8List? key;
      try {
        if (state == DatabaseFileState.encrypted) {
          key = await vault.existingDatabaseKey(role, account);
          if (key == null) {
            report.add("$relative: no key");
            continue;
          }
        }
        final target = p.join(folder, relative);
        await Directory(p.dirname(target)).create(recursive: true);
        await export(source, key, target);
        report.add("$relative: exported");
      } on DecryptedExportError catch (e) {
        report.add("$relative: ${e.message}");
      } on VaultNotReady catch (e) {
        report.add("$relative: the key vault isn't ready "
            "(${e.status.state.name})");
      } finally {
        key?.fillRange(0, key.length, 0);
      }
    }
    return report;
  }
}
