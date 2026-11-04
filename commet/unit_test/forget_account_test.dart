// Vommet: local data encryption, signing an account out here forgets its
// database keys (its databases can't be decrypted any more, by this run or
// the next) and deletes its database files; the other accounts and the
// app's own database keep theirs. A remote sign-out (SignOutWipe.run)
// doesn't forget them.
import 'dart:io';

import 'package:commet/security/database_in_use.dart';
import 'package:commet/security/database_keys.dart';
import 'package:commet/security/forget_account.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/local_data_setting.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:commet/utils/private_files/sign_out_wipe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/test_key_vault.dart';

void main() {
  late Directory root;
  late String drift;
  late String keys;
  late KeyVault vault;

  String file(String account, String name) => p.join(drift, account, name);

  Future<void> makeEncrypted(String account) async {
    for (final (name, role) in [
      ("data.db", DatabaseRole.data),
      ("search_index.db", DatabaseRole.searchIndex),
    ]) {
      final path = file(account, name);
      await Directory(p.dirname(path)).create(recursive: true);
      final key = await DatabaseKeys.forFile(path, role, account);
      final db = EncryptedOpen.open(path, key: key);
      db.execute("PRAGMA journal_mode = wal");
      db.execute("CREATE TABLE t (x)");
      db.execute("INSERT INTO t VALUES (1)");
      db.close();
    }
  }

  setUp(() async {
    root = await Directory(p.join(Directory.current.path, ".dart_tool"))
        .createTemp("forget_account_test_");
    drift = p.join(root.path, "db", "account", "drift");
    keys = p.join(root.path, "db", "keys");
    vault = await testKeyVault(keys);
    DatabaseKeys.debugVault = vault;
    // Database encryption is opt-in; these accounts turned it on.
    LocalDataSetting.debugOverride =
        const LocalDataSetting(encrypt: true, chosen: true);
  });

  tearDown(() async {
    DatabaseKeys.debugVault = null;
    LocalDataSetting.debugOverride = null;
    DatabaseInUse.debugClear();
    await vault.dispose();
    await root.delete(recursive: true);
  });

  test("the account's keys are forgotten and its databases deleted", () async {
    await makeEncrypted("gone");
    await makeEncrypted("kept");
    final appKey = await vault.existingDatabaseKey(DatabaseRole.appData, null);

    await ForgetAccount.run(
        vault: vault, driftDirectory: drift, account: "gone");

    expect(await vault.existingDatabaseKey(DatabaseRole.data, "gone"), isNull);
    expect(await vault.existingDatabaseKey(DatabaseRole.searchIndex, "gone"),
        isNull);
    expect(await Directory(p.join(drift, "gone")).exists(), isFalse);
    // The next start doesn't have them either.
    final next = await testKeyVault(keys);
    expect(await next.existingDatabaseKey(DatabaseRole.data, "gone"), isNull);
    await next.dispose();

    // The other account and the app's database are untouched.
    final kept = await DatabaseKeys.forFile(
        file("kept", "data.db"), DatabaseRole.data, "kept");
    final db = EncryptedOpen.open(file("kept", "data.db"), key: kept);
    expect(db.select("SELECT x FROM t").single["x"], 1);
    db.close();
    expect(await vault.existingDatabaseKey(DatabaseRole.appData, null), appKey);
  });

  test("a copy kept elsewhere (a backup) can't be decrypted any more",
      () async {
    await makeEncrypted("gone");
    final copy = p.join(root.path, "backup", "data.db");
    await Directory(p.dirname(copy)).create();
    await File(file("gone", "data.db")).copy(copy);

    await ForgetAccount.run(
        vault: vault, driftDirectory: drift, account: "gone");
    expect(EncryptedOpen.fileState(copy), DatabaseFileState.encrypted);
    await expectLater(
        DatabaseKeys.forFile(copy, DatabaseRole.data, "gone"),
        throwsA(isA<DatabaseKeyError>().having(
            (e) => e.kind, "kind", DatabaseKeyErrorKind.keyUnavailable)));
  });

  test("an account name that isn't a plain name deletes nothing", () async {
    await makeEncrypted("kept");
    await ForgetAccount.run(
        vault: vault, driftDirectory: p.join(drift, "x"), account: "../kept");
    expect(await File(file("kept", "data.db")).exists(), isTrue);
    expect(
        await vault.existingDatabaseKey(DatabaseRole.data, "kept"), isNotNull);
  });

  test("only a sign-out here forgets the keys, and a failure is kept in",
      () async {
    var forgot = 0;
    final wipe = SignOutWipe(
      sweepCopies: () async {},
      forgetKeys: () async {
        forgot++;
        throw const FileSystemException("busy");
      },
    );
    await wipe.run();
    expect(forgot, 0, reason: "a remote sign-out keeps the keys");
    await wipe.forgetAccount();
    expect(forgot, 1);
  });
}
