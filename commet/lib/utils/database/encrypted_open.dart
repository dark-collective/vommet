// Vommet: local data encryption, opening a SQLite database that may be
// encrypted. Every native database of the app (data.db, search_index.db,
// app_data.db) is opened here.
//
// Encrypted files use SQLite3 Multiple Ciphers in SQLCipher 4 mode with a
// raw 256-bit key (no passphrase KDF: the key is already an HKDF output), so
// a stock `sqlcipher` can open them with the same raw key. Which way a file
// is opened is decided by its header, never by a setting: a plaintext file
// starts with "SQLite format 3\0", an encrypted one with random bytes.
//
// Key material must never reach a log, a crash report or telemetry:
// sqlite3's SqliteException carries the failing statement (which would be
// the PRAGMA key), so every error from the keying steps is replaced by a
// [DatabaseKeyError] that holds no statement.
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

/// What a database file on disk is, by its header.
enum DatabaseFileState {
  /// No file (or an empty one with nothing in its WAL): a new database.
  missing,

  /// A plain SQLite file.
  plaintext,

  /// Anything else: an encrypted file (or a damaged one, which opening with
  /// the key tells apart).
  encrypted,
}

enum DatabaseKeyErrorKind {
  /// The file is encrypted and the key doesn't open it (or it is damaged).
  wrongKey,

  /// The key needed for this file isn't available (the vault is locked,
  /// missing or unreachable). The file is left untouched.
  keyUnavailable,

  /// This build's SQLite has no encryption (it would ignore the key and
  /// write plaintext).
  noCipher,

  /// Setting up the cipher failed for another reason.
  cipherSetup,

  /// The UI engine is encrypting this file right now (a headless engine
  /// leaves it alone until it is done).
  migrating,
}

/// A database couldn't be opened because of its key. Never holds the key
/// or the statement that set it.
class DatabaseKeyError implements Exception {
  DatabaseKeyError(this.kind, this.message, {this.path, this.sqliteCode});

  final DatabaseKeyErrorKind kind;
  final String message;
  final String? path;

  /// SQLite's extended result code, when SQLite failed.
  final int? sqliteCode;

  /// The file is damaged or the key is wrong (not a failure that may pass).
  bool get corrupt =>
      kind == DatabaseKeyErrorKind.wrongKey ||
      (sqliteCode != null && EncryptedOpen.isCorruptCode(sqliteCode!));

  /// Only the file's name: a full path holds the user's name (logs and
  /// crash reports).
  @override
  String toString() =>
      "DatabaseKeyError(${kind.name}): $message${path != null ? " (${_fileName(path!)})" : ""}";

  static String _fileName(String path) => path
      .split(RegExp(r"[/\\]"))
      .lastWhere((part) => part.isNotEmpty, orElse: () => path);
}

class EncryptedOpen {
  static const List<int> plaintextHeader = [
    // "SQLite format 3\0"
    0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, //
    0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00,
  ];

  static const int keyLength = 32;
  static const int _sqliteNotADb = 26;
  static const int _sqliteCorrupt = 11;

  /// SQLITE_CORRUPT or SQLITE_NOTADB (by primary code).
  static bool isCorruptCode(int code) =>
      (code & 0xff) == _sqliteCorrupt || (code & 0xff) == _sqliteNotADb;

  /// Whether [error] (from opening or reading a database) means the file is
  /// damaged or its key is wrong. Anything else (busy, locked, I/O, out of
  /// memory, can't open) may pass and is only tried again.
  static bool isCorrupt(Object error) => switch (error) {
        DatabaseKeyError e => e.corrupt,
        SqliteException e => isCorruptCode(e.extendedResultCode),
        _ => false,
      };

  static String? _cipherVersion;

  /// The SQLite3 Multiple Ciphers version of this build; throws
  /// [DatabaseKeyError] (noCipher) when the SQLite in use has no
  /// encryption. Checked once per isolate.
  static String requireCipher() {
    final cached = _cipherVersion;
    if (cached != null) return cached;
    final Database db;
    try {
      db = sqlite3.openInMemory();
    } on SqliteException catch (e) {
      throw DatabaseKeyError(DatabaseKeyErrorKind.noCipher,
          "can't open SQLite (code ${e.extendedResultCode})");
    }
    try {
      final rows = db.select("SELECT sqlite3mc_version() AS v");
      final version = rows.isEmpty ? null : rows.first["v"];
      if (version is! String || version.isEmpty) {
        throw DatabaseKeyError(DatabaseKeyErrorKind.noCipher,
            "this SQLite build has no encryption");
      }
      return _cipherVersion = version;
    } on SqliteException {
      throw DatabaseKeyError(DatabaseKeyErrorKind.noCipher,
          "this SQLite build has no encryption (sqlite3mc_version is missing)");
    } finally {
      db.close();
    }
  }

  /// The state of the database at [path], by the first 16 bytes of the file
  /// (or of page 1 in its WAL when the main file is still empty).
  static DatabaseFileState fileState(String path) {
    final file = File(path);
    final int length;
    try {
      length = file.lengthSync();
    } on FileSystemException {
      return FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound
          ? DatabaseFileState.missing
          : DatabaseFileState.encrypted;
    }
    if (length > 0) {
      final head = _readHead(file, 16);
      return _isPlainHeader(head)
          ? DatabaseFileState.plaintext
          : DatabaseFileState.encrypted;
    }
    return _walState("$path-wal");
  }

  /// A main file with no pages yet may have its first page only in the WAL
  /// (a crash before the first checkpoint). A plain WAL frame stores the
  /// page as is; an encrypted one doesn't.
  static DatabaseFileState _walState(String walPath) {
    final wal = File(walPath);
    final RandomAccessFile raf;
    try {
      if (wal.lengthSync() < 32) return DatabaseFileState.missing;
      raf = wal.openSync();
    } on FileSystemException {
      return DatabaseFileState.missing;
    }
    try {
      final header = raf.readSync(32);
      final magic = _u32(header, 0);
      if (header.length < 32 || (magic != 0x377f0682 && magic != 0x377f0683)) {
        // Not a plain WAL header: an encrypted WAL.
        return DatabaseFileState.encrypted;
      }
      final pageSize = _u32(header, 8);
      if (pageSize < 512 || pageSize > 65536) {
        return DatabaseFileState.encrypted;
      }
      var offset = 32;
      final total = raf.lengthSync();
      while (offset + 24 + pageSize <= total) {
        raf.setPositionSync(offset);
        final frame = raf.readSync(24 + 16);
        if (_u32(frame, 0) == 1) {
          return _isPlainHeader(Uint8List.sublistView(frame, 24))
              ? DatabaseFileState.plaintext
              : DatabaseFileState.encrypted;
        }
        offset += 24 + pageSize;
      }
      return DatabaseFileState.missing;
    } on FileSystemException {
      return DatabaseFileState.encrypted;
    } finally {
      raf.closeSync();
    }
  }

  static Uint8List _readHead(File file, int count) {
    final raf = file.openSync();
    try {
      return raf.readSync(count);
    } finally {
      raf.closeSync();
    }
  }

  static int _u32(List<int> b, int at) => b.length < at + 4
      ? -1
      : (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

  static bool _isPlainHeader(List<int> head) {
    if (head.length < plaintextHeader.length) return false;
    for (var i = 0; i < plaintextHeader.length; i++) {
      if (head[i] != plaintextHeader[i]) return false;
    }
    return true;
  }

  /// Opens [path]. With a [key], the connection is set up for SQLCipher 4
  /// with that raw key and checked by reading the schema: a wrong key (or a
  /// plaintext file) throws [DatabaseKeyError] (wrongKey) and the file is
  /// left as it was. Without one the file is opened as plain SQLite.
  static Database open(String path, {Uint8List? key, bool readOnly = false}) {
    if (key != null) {
      if (key.length != keyLength) {
        throw DatabaseKeyError(
            DatabaseKeyErrorKind.cipherSetup, "the key has the wrong length",
            path: path);
      }
      requireCipher();
    }
    final db = sqlite3.open(path,
        mode: readOnly ? OpenMode.readOnly : OpenMode.readWriteCreate);
    if (key == null) return db;
    try {
      applyKey(db, key, path: path);
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// Keys an open connection (before anything else reads it).
  static void applyKey(Database db, Uint8List key, {String? path}) {
    final hex = StringBuffer();
    for (final b in key) {
      hex.write(b.toRadixString(16).padLeft(2, "0"));
    }
    try {
      // The cipher scheme must be chosen before the key; "legacy = 4" is
      // SQLCipher 4's defaults (4 KiB pages, HMAC-SHA512, 64-byte reserve).
      db.execute("PRAGMA cipher = 'sqlcipher'");
      db.execute("PRAGMA legacy = 4");
      // x'…' with 64 hex digits is a raw key: no passphrase derivation.
      final rows = db.select("PRAGMA key = \"x'$hex'\"");
      if (rows.isNotEmpty && rows.first.values.first == "error") {
        throw DatabaseKeyError(
            DatabaseKeyErrorKind.cipherSetup, "the cipher rejected the key",
            path: path);
      }
    } on SqliteException catch (e) {
      throw DatabaseKeyError(DatabaseKeyErrorKind.cipherSetup,
          "can't set up the cipher (code ${e.extendedResultCode})",
          path: path, sqliteCode: e.extendedResultCode);
    } finally {
      hex.clear();
    }
    try {
      db.select("SELECT count(*) FROM sqlite_master");
    } on SqliteException catch (e) {
      if (e.resultCode == _sqliteNotADb) {
        throw DatabaseKeyError(
            DatabaseKeyErrorKind.wrongKey, "the key doesn't open this database",
            path: path);
      }
      throw DatabaseKeyError(DatabaseKeyErrorKind.cipherSetup,
          "can't read the database (code ${e.extendedResultCode})",
          path: path, sqliteCode: e.extendedResultCode);
    }
  }
}
