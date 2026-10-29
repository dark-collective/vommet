// Vommet: local data encryption, "Export decrypted copy" (debug builds):
// an encrypted database is copied to a plaintext file stock SQLite opens;
// a wrong key, or a target that exists, fails without the key in the error.
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/migration/decrypted_export.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'support/test_key_vault.dart';

void main() {
  late Directory root;
  final key = Uint8List.fromList(List.generate(32, (i) => 0xa0 + i));
  String hex(Uint8List k) =>
      k.map((b) => b.toRadixString(16).padLeft(2, "0")).join();

  setUp(() async {
    root = await Directory(p.join(Directory.current.path, ".dart_tool"))
        .createTemp("decrypted_export_test_");
  });
  tearDown(() => root.delete(recursive: true));

  String makeEncrypted() {
    final path = p.join(root.path, "data.db");
    final db = EncryptedOpen.open(path, key: key);
    db.execute("PRAGMA journal_mode = wal");
    db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, body TEXT)");
    db.execute("CREATE VIRTUAL TABLE f USING fts5(body, tokenize='trigram')");
    for (var i = 0; i < 40; i++) {
      db.execute("INSERT INTO t (body) VALUES (?)", ["row $i"]);
      db.execute("INSERT INTO f (body) VALUES (?)", ["message $i"]);
    }
    db.close();
    return path;
  }

  test("an encrypted database is copied to a plaintext file", () async {
    final source = makeEncrypted();
    final target = p.join(root.path, "copy with space.db");
    await DecryptedExport.export(source, key, target);
    expect(EncryptedOpen.fileState(target), DatabaseFileState.plaintext);
    final db = sqlite3.open(target);
    expect(db.select("SELECT count(*) AS n FROM t").first["n"], 40);
    expect(
        db.select("SELECT count(*) AS n FROM f WHERE f MATCH ?",
            ['"sage 3"']).first["n"],
        11);
    db.close();
    // The source is untouched and still encrypted.
    expect(EncryptedOpen.fileState(source), DatabaseFileState.encrypted);
  });

  test("a wrong key or an existing target fails without the key", () {
    final source = makeEncrypted();
    final wrong = Uint8List.fromList(List.generate(32, (i) => i));
    final target = p.join(root.path, "copy.db");
    expect(
        () => DecryptedExport.exportSync(source, wrong, target),
        throwsA(isA<DecryptedExportError>().having(
            (e) => e.toString(), "message", isNot(contains(hex(wrong))))));
    expect(File(target).existsSync(), isFalse);

    File(target).writeAsStringSync("x");
    expect(() => DecryptedExport.exportSync(source, key, target),
        throwsA(isA<DecryptedExportError>()));
    expect(File(target).readAsStringSync(), "x");
  });

  test("every database of the app is exported, keys from the vault", () async {
    final dbDir = p.join(root.path, "db");
    final vault = await testKeyVault(p.join(dbDir, "keys"));
    void make(String path, Uint8List? k, String text) {
      Directory(p.dirname(path)).createSync(recursive: true);
      final db = EncryptedOpen.open(path, key: k);
      db.execute("CREATE TABLE t (body TEXT)");
      db.execute("INSERT INTO t VALUES (?)", [text]);
      db.close();
    }

    final drift = p.join(dbDir, "account", "drift");
    make(p.join(drift, "alice", "data.db"),
        await vault.newDatabaseKey(DatabaseRole.data, "alice"), "alice");
    make(p.join(drift, "bob", "data.db"), null, "bob plaintext");
    // Encrypted with a key the vault never recorded.
    make(p.join(drift, "bob", "search_index.db"), key, "orphan");

    final out = p.join(root.path, "out");
    final report = await DecryptedExport.exportAll(
        vault: vault,
        databaseDirectory: dbDir,
        accounts: ["alice", "bob", "../escape"],
        folder: out);
    expect(report, [
      p.join("alice", "data.db") + ": exported",
      p.join("bob", "data.db") + ": exported",
      p.join("bob", "search_index.db") + ": no key",
    ]);
    for (final (who, text) in [("alice", "alice"), ("bob", "bob plaintext")]) {
      final path = p.join(out, who, "data.db");
      expect(EncryptedOpen.fileState(path), DatabaseFileState.plaintext);
      final db = sqlite3.open(path);
      expect(db.select("SELECT body FROM t").first["body"], text);
      db.close();
    }
    expect(File(p.join(out, "bob", "search_index.db")).existsSync(), isFalse);
  });
}
