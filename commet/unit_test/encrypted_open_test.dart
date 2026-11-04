// Vommet: local data encryption, opening databases (phase 3): this build's
// SQLite is SQLite3 Multiple Ciphers; a raw key makes an SQLCipher 4 file
// with no plaintext header that reopens with the same key and not with
// another (a sanitized error without the key); a plaintext file is told
// apart by its header (also when its first page is only in the WAL); WAL,
// user_version and FTS5 trigram search work on an encrypted file; the raw
// key skips the passphrase KDF.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/utils/database/encrypted_open.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

Uint8List keyOf(int seed) =>
    Uint8List.fromList(List.generate(32, (i) => (i * 7 + seed) & 0xff));

List<int> repeat(List<int> b, int times) =>
    [for (var i = 0; i < times; i++) ...b];

String hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, "0")).join();

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory(p.join(Directory.current.path, ".dart_tool"))
        .createTemp("encrypted_open_test_");
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  String path(String name) => p.join(dir.path, name);

  test("this build's SQLite has encryption", () {
    expect(EncryptedOpen.requireCipher(), isNotEmpty);
  });

  test("a keyed database is encrypted and reopens only with its key", () {
    final key = keyOf(1);
    final file = path("a.db");
    expect(EncryptedOpen.fileState(file), DatabaseFileState.missing);

    var db = EncryptedOpen.open(file, key: key);
    db.execute("PRAGMA journal_mode = wal");
    db.execute("CREATE TABLE t (x TEXT)");
    db.execute("INSERT INTO t VALUES ('secret words')");
    db.execute("PRAGMA user_version = 7");
    db.close();

    final bytes = File(file).readAsBytesSync();
    expect(EncryptedOpen.fileState(file), DatabaseFileState.encrypted);
    expect(latin1.decode(bytes, allowInvalid: true),
        isNot(contains("secret words")));
    expect(bytes.length % 4096, 0);

    db = EncryptedOpen.open(file, key: key, readOnly: true);
    expect(db.select("SELECT x FROM t").single["x"], "secret words");
    expect(db.select("PRAGMA user_version").single.values.first, 7);
    expect(db.select("PRAGMA journal_mode").single.values.first, "wal");
    db.close();

    final wrong = keyOf(2);
    expect(
        () => EncryptedOpen.open(file, key: wrong),
        throwsA(
          isA<DatabaseKeyError>()
              .having((e) => e.kind, "kind", DatabaseKeyErrorKind.wrongKey)
              .having(
                  (e) => e.toString(),
                  "text",
                  allOf(
                      isNot(contains(hexOf(wrong))),
                      isNot(contains(hexOf(key))),
                      isNot(contains(base64.encode(wrong))))),
        ));
    // Opened without a key it isn't a database at all.
    final plain = sqlite3.open(file);
    expect(() => plain.select("SELECT count(*) FROM sqlite_master"),
        throwsA(isA<SqliteException>()));
    plain.close();
  });

  test("the file is SQLCipher 4 compatible (sqlcipher scheme, raw key)", () {
    final key = keyOf(3);
    final file = path("c.db");
    EncryptedOpen.open(file, key: key)
      ..execute("CREATE TABLE t (x)")
      ..close();
    // Opening with the same raw key spelled by hand, as sqlcipher's CLI
    // would, works; the default sqlite3mc scheme (ChaCha20) doesn't.
    final db = sqlite3.open(file);
    db.execute("PRAGMA cipher = 'sqlcipher'");
    db.execute("PRAGMA legacy = 4");
    db.execute("PRAGMA key = \"x'${hexOf(key)}'\"");
    expect(db.select("SELECT count(*) AS n FROM sqlite_master").single["n"], 1);
    db.close();
    final other = sqlite3.open(file);
    other.execute("PRAGMA key = \"x'${hexOf(key)}'\"");
    expect(() => other.select("SELECT count(*) FROM sqlite_master"),
        throwsA(isA<SqliteException>()));
    other.close();
  });

  test("a plaintext file is detected and refuses a key", () {
    final file = path("p.db");
    sqlite3.open(file)
      ..execute("CREATE TABLE t (x)")
      ..close();
    expect(EncryptedOpen.fileState(file), DatabaseFileState.plaintext);
    expect(
        () => EncryptedOpen.open(file, key: keyOf(4)),
        throwsA(isA<DatabaseKeyError>()
            .having((e) => e.kind, "kind", DatabaseKeyErrorKind.wrongKey)));
    // Untouched: still a plain database.
    expect(EncryptedOpen.fileState(file), DatabaseFileState.plaintext);
    final db = EncryptedOpen.open(file);
    expect(db.select("SELECT count(*) AS n FROM sqlite_master").single["n"], 1);
    db.close();
  });

  test("an empty main file is judged by page 1 in its WAL", () {
    final source = path("src.db");
    sqlite3.open(source)
      ..execute("PRAGMA page_size = 4096")
      ..execute("CREATE TABLE t (x)")
      ..close();
    final page1 = File(source).readAsBytesSync().sublist(0, 4096);

    Uint8List wal(List<int> page, {int pageNumber = 1}) {
      final out = BytesBuilder();
      final header = ByteData(32)
        ..setUint32(0, 0x377f0682)
        ..setUint32(4, 3007000)
        ..setUint32(8, 4096);
      out.add(header.buffer.asUint8List());
      final frame = ByteData(24)
        ..setUint32(0, pageNumber)
        ..setUint32(4, 1);
      out.add(frame.buffer.asUint8List());
      out.add(page);
      return out.toBytes();
    }

    final file = path("w.db");
    File(file).writeAsBytesSync([]);
    expect(EncryptedOpen.fileState(file), DatabaseFileState.missing);

    File("$file-wal").writeAsBytesSync(wal(page1));
    expect(EncryptedOpen.fileState(file), DatabaseFileState.plaintext);

    File("$file-wal").writeAsBytesSync(wal(repeat(keyOf(9), 128)));
    expect(EncryptedOpen.fileState(file), DatabaseFileState.encrypted);

    File("$file-wal").writeAsBytesSync(wal(page1, pageNumber: 2));
    expect(EncryptedOpen.fileState(file), DatabaseFileState.missing);

    File("$file-wal").writeAsBytesSync(repeat(keyOf(5), 40));
    expect(EncryptedOpen.fileState(file), DatabaseFileState.encrypted);
  });

  test("FTS5 trigram search works on an encrypted file", () {
    final db = EncryptedOpen.open(path("s.db"), key: keyOf(6));
    db.execute("CREATE VIRTUAL TABLE f USING fts5(body, tokenize = 'trigram')");
    db.execute("INSERT INTO f VALUES ('東京で会いましょう'), ('hello there')");
    expect(db.select("SELECT body FROM f WHERE f MATCH '東京で'").single["body"],
        "東京で会いましょう");
    expect(db.select("SELECT body FROM f WHERE f MATCH 'ello'").length, 1);
    db.close();
  });

  test("a raw key skips the passphrase KDF", () {
    final file = path("k.db");
    EncryptedOpen.open(file, key: keyOf(7))
      ..execute("CREATE TABLE t (x)")
      ..close();
    final passFile = path("pass.db");
    final setup = sqlite3.open(passFile)
      ..execute("PRAGMA cipher = 'sqlcipher'")
      ..execute("PRAGMA legacy = 4")
      ..execute("PRAGMA key = 'a passphrase'")
      ..execute("CREATE TABLE t (x)");
    setup.close();

    int timeRaw() {
      final w = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        EncryptedOpen.open(file, key: keyOf(7)).close();
      }
      return w.elapsedMicroseconds;
    }

    int timePass() {
      final w = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        final db = sqlite3.open(passFile)
          ..execute("PRAGMA cipher = 'sqlcipher'")
          ..execute("PRAGMA legacy = 4")
          ..execute("PRAGMA key = 'a passphrase'");
        db.select("SELECT count(*) FROM sqlite_master");
        db.close();
      }
      return w.elapsedMicroseconds;
    }

    final raw = timeRaw();
    final pass = timePass();
    // 256000 PBKDF2-HMAC-SHA512 rounds take tens of milliseconds per open;
    // a raw key takes well under one.
    expect(raw * 5, lessThan(pass),
        reason: "raw ${raw ~/ 5} us/open vs passphrase ${pass ~/ 5} us/open");
  });

  test("a key of the wrong length is refused before opening", () {
    expect(() => EncryptedOpen.open(path("x.db"), key: Uint8List(16)),
        throwsA(isA<DatabaseKeyError>()));
    expect(File(path("x.db")).existsSync(), isFalse);
  });

  test(
      "an error names only the file, not the folders (they hold the user's name)",
      () {
    final e = DatabaseKeyError(DatabaseKeyErrorKind.wrongKey, "doesn't open",
        path: "/home/someone/.local/share/vommet/db/acc/data.db");
    expect(e.toString(), contains("data.db"));
    expect(e.toString(), isNot(contains("someone")));
    final w = DatabaseKeyError(DatabaseKeyErrorKind.wrongKey, "doesn't open",
        path: r"C:\Users\someone\AppData\db\data.db");
    expect(w.toString(), contains("data.db"));
    expect(w.toString(), isNot(contains("someone")));
  });

  test("damaged is told apart from failures that may pass", () {
    expect(EncryptedOpen.isCorruptCode(11), isTrue);
    expect(EncryptedOpen.isCorruptCode(26), isTrue);
    expect(EncryptedOpen.isCorruptCode(11 | (1 << 8)), isTrue);
    expect(EncryptedOpen.isCorruptCode(5), isFalse); // busy
    expect(EncryptedOpen.isCorruptCode(10), isFalse); // I/O
    expect(EncryptedOpen.isCorruptCode(13), isFalse); // full
    expect(
        EncryptedOpen.isCorrupt(
            DatabaseKeyError(DatabaseKeyErrorKind.wrongKey, "x")),
        isTrue);
    expect(
        EncryptedOpen.isCorrupt(
            DatabaseKeyError(DatabaseKeyErrorKind.keyUnavailable, "x")),
        isFalse);
    expect(
        EncryptedOpen.isCorrupt(DatabaseKeyError(
            DatabaseKeyErrorKind.keyUnavailable, "x",
            sqliteCode: 26)),
        isTrue);
    expect(EncryptedOpen.isCorrupt(const FileSystemException("x")), isFalse);
  });

  test("a wrong key is reported as damaged", () {
    final file = path("w.db");
    EncryptedOpen.open(file, key: keyOf(1))
      ..execute("CREATE TABLE t (x)")
      ..close();
    Object? error;
    try {
      EncryptedOpen.open(file, key: keyOf(2))
          .select("SELECT count(*) FROM sqlite_master");
    } catch (e) {
      error = e;
    }
    expect(error, isNotNull);
    expect(EncryptedOpen.isCorrupt(error!), isTrue);
  });
}
