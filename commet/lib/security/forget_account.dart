// Vommet: local data encryption, what signing an account out here does to
// its encrypted databases (LOCAL-DATA-ENCRYPTION.md §7): the account's salt
// leaves the current keystore.json, so its data.db and search index can no
// longer be decrypted from what is on this device now. The files are then
// deleted, best effort: an open connection (the database isolate keeps them
// cached) or Windows' locking may keep one.
//
// Best effort, not a cryptographic erase: the master key isn't rotated, so
// a copy that kept the salt too (a backup or snapshot of the home folder, a
// Start over / Reset copy, the freed blocks of an earlier keystore.json)
// decrypts with it. Rotating it would mean re-keying every other account's
// databases, which the database isolate keeps open (ENC-STATE.md, threat
// model).
//
// Plain deletes, not overwrites. A message store still plaintext (its
// migration never finished) is only deleted like before.
import 'dart:io';

import 'package:commet/debug/log.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:path/path.dart' as p;

class ForgetAccount {
  /// Forgets [account]'s keys, then deletes its databases under
  /// [driftDirectory] (<database dir>/account/drift). Never throws.
  static Future<void> run(
      {required KeyVault? vault,
      required String driftDirectory,
      required String account}) async {
    if (account.isEmpty || p.basename(account) != account) return;
    if (vault != null && vault.status.isReady) {
      try {
        await vault.forgetAccount(account);
        Log.i("Forgot the database keys of a signed-out account");
      } catch (e) {
        Log.w("Couldn't forget the account's database keys: ${e.runtimeType}");
      }
    }
    final dir = Directory(p.join(driftDirectory, account));
    for (final name in const ["data.db", "search_index.db"]) {
      for (final suffix in const ["", "-wal", "-shm", "-journal"]) {
        final file = File(p.join(dir.path, "$name$suffix"));
        try {
          if (await file.exists()) await file.delete();
        } catch (e) {
          Log.w("Couldn't delete $name$suffix of a signed-out account: "
              "${e.runtimeType}");
        }
      }
    }
    try {
      if (await dir.exists() && await dir.list().isEmpty) await dir.delete();
    } catch (_) {}
  }
}
