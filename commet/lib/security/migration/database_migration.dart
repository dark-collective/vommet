// Vommet: local data encryption, the one-time migration of a plaintext
// database to an encrypted one (LOCAL-DATA-ENCRYPTION.md §6). Native
// platforms only.
//
// Per file:
//  1. resume an interrupted run (the rules of §6 step 10);
//  2. check the free space (db + wal) × 1.1 + 50 MiB;
//  3. checkpoint the plaintext (TRUNCATE) and copy it encrypted into
//     `<db>.enc-tmp` (0600) with VACUUM INTO: SQLite3 Multiple Ciphers has
//     no sqlcipher_export, and VACUUM INTO a URI with the cipher parameters
//     writes the same SQLCipher 4 file (user_version, FTS5, triggers kept);
//  4. verify the copy (opens with the key, quick_check or integrity_check,
//     same tables, same row counts, same user_version);
//  5. fsync it; 6. delete the plaintext -wal/-shm (checked empty and the
//     file unchanged since the copy); 7. rename `<db>` → `<db>.plain-old`;
//  8. rename `<db>.enc-tmp` → `<db>`, fsync the directory;
//  9. overwrite `<db>.plain-old` with zeros and delete it.
// A crash or kill at any point leaves at least one whole copy, and the next
// run finishes or undoes what was started.
//
// The reverse (decrypt, when the user turns local data encryption off) is
// the same engine and the same safety: the encrypted file is copied
// plaintext into `<db>.dec-tmp` (VACUUM INTO a URI with an empty key: the
// copy has no cipher), verified (opens without a key, same checks), the
// encrypted -wal/-shm deleted, `<db>` renamed to `<db>.enc-old`, the copy put
// in place, `<db>.enc-old` deleted (it is encrypted: no need to overwrite
// it). [MigrationStep.deletePlainWal] and [MigrationStep.renamePlain] then
// stand for the source file's WAL and rename, whichever it is.
//
// Key material never leaves this file in an error: SqliteException carries
// the statement and its parameters (the URI with the key), so every error is
// replaced by a [MigrationError] that holds a result code only.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:commet/utils/database/encrypted_open.dart';
import 'package:commet/utils/disk_space.dart';
import 'package:commet/utils/private_files/owner_only.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// The steps of one file's migration, in order (for fault injection, logs
/// and telemetry).
enum MigrationStep {
  resume,
  spaceCheck,
  export,
  verify,
  sync,
  deletePlainWal,
  renamePlain,
  renameTemp,
  wipe,
}

enum MigrationResult {
  /// The file is encrypted now (this run, or by finishing an interrupted
  /// one).
  encrypted,

  /// Decrypting: the file is plaintext now.
  decrypted,

  /// Decrypting: it was plaintext already; nothing to do.
  alreadyPlain,

  /// It was encrypted already; nothing to do.
  alreadyEncrypted,

  /// There is no such file.
  missing,

  /// Not enough free space: the file is kept as it was.
  noSpace,

  /// Copying or verifying failed: the file is kept as it was.
  failed,
}

class MigrationOutcome {
  const MigrationOutcome(this.result,
      {this.step,
      this.detail,
      this.bytesNeeded,
      this.bytesFree,
      this.corrupt = false});

  final MigrationResult result;

  /// [MigrationResult.failed] because the file itself is damaged or its
  /// key is wrong (SQLite CORRUPT / NOTADB): only then is a derived file
  /// deleted to be made again.
  final bool corrupt;

  /// The step that failed.
  final MigrationStep? step;

  /// What went wrong, without key material or statements.
  final String? detail;

  /// For [MigrationResult.noSpace]: what is needed and what is free.
  final int? bytesNeeded;
  final int? bytesFree;

  bool get isEncrypted =>
      result == MigrationResult.encrypted ||
      result == MigrationResult.alreadyEncrypted;

  bool get isPlain =>
      result == MigrationResult.decrypted ||
      result == MigrationResult.alreadyPlain;

  @override
  String toString() => "MigrationOutcome(${result.name}"
      "${step != null ? ", at ${step!.name}" : ""}"
      "${detail != null ? ": $detail" : ""}"
      "${corrupt ? ", corrupt" : ""})";
}

/// A sanitized failure: a message and a SQLite result code, never a
/// statement, a parameter or a path with a key in it.
class MigrationError implements Exception {
  const MigrationError(this.message,
      {this.code, this.noSpace = false, this.corrupt = false});
  final String message;
  final int? code;
  final bool noSpace;

  /// The file being converted is damaged or its key is wrong.
  final bool corrupt;
  @override
  String toString() =>
      "MigrationError: $message${code != null ? " (code $code)" : ""}";
}

/// Both copies of a file are in a state the app must not start on (the
/// encrypted copy couldn't be put in place, and the plaintext couldn't be
/// put back). The next start finishes the swap; this one must stop before
/// anything opens the database (it would create an empty one).
class MigrationInterrupted implements Exception {
  MigrationInterrupted(this.path);
  final String path;
  @override
  String toString() =>
      "MigrationInterrupted: the encrypted copy of $path couldn't be put in "
      "place; restart the app to finish";
}

/// For tests: a kill at a step. Thrown by [DatabaseMigrator.beforeStep], it
/// leaves everything as a killed process would (no clean-up).
class SimulatedCrash extends Error {
  SimulatedCrash(this.step);
  final MigrationStep step;
  @override
  String toString() => "SimulatedCrash(${step.name})";
}

typedef FreeSpaceProbe = int? Function(String directory);

class DatabaseMigrator {
  DatabaseMigrator({
    FreeSpaceProbe? freeSpace,
    this.beforeStep,
    this.useIsolate = true,
    this.fullCheckBelow = 200 * 1024 * 1024,
  }) : freeSpace = freeSpace ?? DiskSpace.freeBytes;

  final FreeSpaceProbe freeSpace;

  /// Called before each step; for fault injection. Throwing
  /// [SimulatedCrash] stops as a kill would, anything else is a failure of
  /// that step.
  final void Function(MigrationStep step, String path)? beforeStep;

  /// Runs the SQLite work on another isolate (the splash keeps drawing).
  final bool useIsolate;

  /// Files smaller than this get a full integrity_check, others a
  /// quick_check.
  final int fullCheckBelow;

  static const int _sqliteFull = 13;
  static const int _enospc = 28; // POSIX
  static const int _winDiskFull = 112; // ERROR_DISK_FULL
  static const int _winHandleDiskFull = 39; // ERROR_HANDLE_DISK_FULL

  static String tempPath(String path) => "$path.enc-tmp";
  static String oldPath(String path) => "$path.plain-old";

  /// Decrypting: the plaintext copy, and the encrypted file moved aside.
  static String decryptTempPath(String path) => "$path.dec-tmp";
  static String decryptOldPath(String path) => "$path.enc-old";

  /// What the copy needs free: (db + wal) × 1.1 + 50 MiB.
  static int requiredBytes(int databaseBytes) =>
      (databaseBytes * 1.1).ceil() + 50 * 1024 * 1024;

  /// Every leftover a run at [path] may have left (for the start-up check:
  /// is there anything to do at all?).
  static bool hasLeftovers(String path) =>
      _exists(tempPath(path)) ||
      _exists(oldPath(path)) ||
      _exists(decryptTempPath(path)) ||
      _exists(decryptOldPath(path));

  /// Encrypts the database at [path] with [key] (the caller keeps and
  /// zeroes it). [onProgress] gets 0..1 while the copy is written.
  Future<MigrationOutcome> migrate(String path, Uint8List key,
          {void Function(double fraction)? onProgress}) =>
      _convert(path, key, encrypt: true, onProgress: onProgress);

  /// Decrypts the encrypted database at [path] with [key] (local data
  /// encryption turned off); the same steps and safety as [migrate].
  Future<MigrationOutcome> decrypt(String path, Uint8List key,
          {void Function(double fraction)? onProgress}) =>
      _convert(path, key, encrypt: false, onProgress: onProgress);

  Future<MigrationOutcome> _convert(String path, Uint8List key,
      {required bool encrypt,
      void Function(double fraction)? onProgress}) async {
    _hook(MigrationStep.resume, path);
    await resume(path);

    switch (EncryptedOpen.fileState(path)) {
      case DatabaseFileState.missing:
        return const MigrationOutcome(MigrationResult.missing);
      case DatabaseFileState.encrypted:
        // resume() may just have finished an interrupted swap.
        if (encrypt) {
          return const MigrationOutcome(MigrationResult.alreadyEncrypted);
        }
      case DatabaseFileState.plaintext:
        if (!encrypt) {
          return const MigrationOutcome(MigrationResult.alreadyPlain);
        }
    }

    final temp = encrypt ? tempPath(path) : decryptTempPath(path);
    final old = encrypt ? oldPath(path) : decryptOldPath(path);
    var step = MigrationStep.spaceCheck;
    try {
      _hook(step, path);
      final size = _length(path) + _length("$path-wal");
      final needed = requiredBytes(size);
      final free = freeSpace(p.dirname(path));
      if (free != null && free < needed) {
        return MigrationOutcome(MigrationResult.noSpace,
            step: step, bytesNeeded: needed, bytesFree: free);
      }

      step = MigrationStep.export;
      _hook(step, path);
      await _deleteTemp(temp);
      await File(temp).create(exclusive: true);
      await OwnerOnly.file(temp);
      final total = size == 0 ? 1 : size;
      final progress = onProgress == null
          ? null
          : Timer.periodic(const Duration(milliseconds: 250), (_) {
              final done = _length(temp) / total;
              onProgress(done > 0.95 ? 0.95 : done);
            });
      final _Stamp stamp;
      try {
        stamp = await (useIsolate
            ? _exportIsolate(path, temp, key, encrypt)
            : Future.sync(() => _exportSync(path, temp, key, encrypt)));
      } finally {
        progress?.cancel();
      }

      step = MigrationStep.verify;
      _hook(step, path);
      final fullCheck = size < fullCheckBelow;
      await (useIsolate
          ? _verifyIsolate(path, temp, key, fullCheck, encrypt)
          : Future.sync(
              () => _verifySync(path, temp, key, fullCheck, encrypt)));
      onProgress?.call(0.97);

      step = MigrationStep.sync;
      _hook(step, path);
      final raf = await File(temp).open(mode: FileMode.append);
      try {
        await raf.flush();
      } finally {
        await raf.close();
      }

      step = MigrationStep.deletePlainWal;
      _hook(step, path);
      // Something wrote to the source after it was copied (another
      // engine): the copy is stale. Try again on the next start.
      if (!stamp.matches(path)) {
        throw const MigrationError("the database changed while it was copied");
      }
      await _deleteIfThere("$path-wal");
      await _deleteIfThere("$path-shm");

      step = MigrationStep.renamePlain;
      _hook(step, path);
      await _rename(path, old);
    } on SimulatedCrash {
      rethrow;
    } catch (e) {
      await _deleteTemp(temp);
      return _failure(step, e);
    }

    // From here the source is only in its .old name: a failure puts it
    // back.
    _hook(MigrationStep.renameTemp, path);
    try {
      await _rename(temp, path);
    } on SimulatedCrash {
      rethrow;
    } catch (e) {
      try {
        await _rename(old, path);
      } catch (_) {
        throw MigrationInterrupted(path);
      }
      await _deleteTemp(temp);
      return _failure(MigrationStep.renameTemp, e);
    }
    DiskSpace.syncDirectory(p.dirname(path));
    onProgress?.call(1);

    _hook(MigrationStep.wipe, path);
    if (encrypt) {
      await secureDelete(old);
      return const MigrationOutcome(MigrationResult.encrypted);
    }
    // The old copy is encrypted: deleting it is enough.
    await deleteDatabaseFiles(old);
    return const MigrationOutcome(MigrationResult.decrypted);
  }

  /// Finishes or undoes an interrupted run at [path] (§6 step 10). Never
  /// leaves the file missing when a copy of it exists.
  Future<void> resume(String path) async {
    if (_exists(decryptTempPath(path)) || _exists(decryptOldPath(path))) {
      await _resume(path, decryptTempPath(path), decryptOldPath(path),
          oldIsPlain: false);
    }
    await _resume(path, tempPath(path), oldPath(path), oldIsPlain: true);
  }

  Future<void> _resume(String path, String temp, String old,
      {required bool oldIsPlain}) async {
    Future<void> deleteOld() =>
        oldIsPlain ? secureDelete(old) : deleteDatabaseFiles(old);
    final state = EncryptedOpen.fileState(path);
    final hasTemp = _exists(temp);
    final hasOld = _exists(old);

    // An empty file at [path] with the old copy next to it was made by
    // something that opened the path after the source was moved away: it
    // holds nothing, so it is the missing case (never trusted over the
    // copies).
    if (state == DatabaseFileState.missing && _exists(path) && hasOld) {
      try {
        await deleteDatabaseFiles(path);
      } on FileSystemException {
        throw MigrationInterrupted(path);
      }
    }

    if (state == DatabaseFileState.missing && !_exists(path)) {
      // The app must not start with the file missing (it would make an
      // empty one, and the next run would take that for the encrypted
      // copy): a rename that fails here stops the start.
      if (hasOld && hasTemp) {
        // Killed between the two renames: the copy was verified and synced
        // before the source was moved away.
        try {
          await _rename(temp, path);
        } on FileSystemException {
          throw MigrationInterrupted(path);
        }
        DiskSpace.syncDirectory(p.dirname(path));
        await deleteOld();
      } else if (hasOld) {
        // No copy to put in place: the source goes back.
        try {
          await _rename(old, path);
        } on FileSystemException {
          throw MigrationInterrupted(path);
        }
      } else if (hasTemp) {
        await _deleteTemp(temp);
      }
      return;
    }

    if (hasTemp) await _deleteTemp(temp);
    // The file with the old copy next to it: killed before the wipe
    // finished, or the leftover is an older copy.
    if (hasOld) await deleteOld();
  }

  void _hook(MigrationStep step, String path) => beforeStep?.call(step, path);

  MigrationOutcome _failure(MigrationStep step, Object error) {
    if (error is MigrationError && error.noSpace) {
      return MigrationOutcome(MigrationResult.noSpace,
          step: step, detail: error.toString());
    }
    if (error is FileSystemException && _isDiskFull(error.osError)) {
      return MigrationOutcome(MigrationResult.noSpace,
          step: step, detail: "disk full");
    }
    final String detail;
    if (error is MigrationError) {
      detail = error.toString();
    } else if (error is SqliteException) {
      // Only the code: the statement may hold the key.
      if (error.resultCode == _sqliteFull) {
        return MigrationOutcome(MigrationResult.noSpace,
            step: step, detail: "disk full");
      }
      detail = "SQLite error ${error.extendedResultCode}";
    } else if (error is FileSystemException) {
      detail = "${error.message} (${error.osError?.errorCode})";
    } else if (error is DatabaseKeyError) {
      detail = error.toString();
    } else {
      detail = error.runtimeType.toString();
    }
    // Only reading the file being converted tells that it is damaged (a
    // failing copy or check is not the file's fault).
    final corrupt = error is MigrationError
        ? error.corrupt
        : step == MigrationStep.export && EncryptedOpen.isCorrupt(error);
    return MigrationOutcome(MigrationResult.failed,
        step: step, detail: detail, corrupt: corrupt);
  }

  static bool _isDiskFull(OSError? error) {
    final code = error?.errorCode;
    if (code == null) return false;
    return Platform.isWindows
        ? code == _winDiskFull || code == _winHandleDiskFull
        : code == _enospc;
  }

  // Static, so the closures sent to the isolate capture their arguments
  // only (not the hooks and callbacks of the migrator).
  static Future<_Stamp> _exportIsolate(
          String path, String temp, Uint8List key, bool encrypt) =>
      Isolate.run(() => _exportSync(path, temp, key, encrypt));

  static Future<void> _verifyIsolate(String path, String temp, Uint8List key,
          bool fullCheck, bool encrypt) =>
      Isolate.run(() => _verifySync(path, temp, key, fullCheck, encrypt));

  /// Checkpoints [path] and copies it encrypted (or, decrypting, plaintext)
  /// into [temp]. Runs on the migration isolate; throws [MigrationError]
  /// only.
  static _Stamp _exportSync(
      String path, String temp, Uint8List key, bool encrypt) {
    final hex = StringBuffer();
    for (final b in key) {
      hex.write(b.toRadixString(16).padLeft(2, "0"));
    }
    Database? source;
    try {
      EncryptedOpen.requireCipher();
      // uri: true on the source lets VACUUM INTO read its target as a URI.
      source = sqlite3.open(path, uri: true);
      if (!encrypt) EncryptedOpen.applyKey(source, key, path: path);
      final checkpoint = source.select("PRAGMA wal_checkpoint(TRUNCATE)");
      if (checkpoint.isNotEmpty && checkpoint.first.values.first == 1) {
        throw const MigrationError("the database is in use");
      }
      final stamp = _Stamp.of(path);
      // key=x'…' is the raw key (hexkey= would go through the KDF). An
      // empty key writes a copy without a cipher (without one, the target
      // would get the source's key).
      final target = Uri.file(temp).replace(
          queryParameters: encrypt
              ? {
                  "cipher": "sqlcipher",
                  "legacy": "4",
                  "key": "x'$hex'",
                }
              : {"key": ""});
      source.execute("VACUUM INTO ?", [target.toString()]);
      return stamp;
    } on MigrationError {
      rethrow;
    } on DatabaseKeyError catch (e) {
      throw MigrationError(e.message, code: e.sqliteCode, corrupt: e.corrupt);
    } on SqliteException catch (e) {
      throw MigrationError("copying failed",
          code: e.extendedResultCode,
          noSpace: e.resultCode == _sqliteFull,
          corrupt: EncryptedOpen.isCorruptCode(e.extendedResultCode));
    } catch (e) {
      throw MigrationError("copying failed: ${e.runtimeType}");
    } finally {
      hex.clear();
      try {
        source?.close();
      } catch (_) {}
    }
  }

  /// Checks [temp] opens with [key] (decrypting: without a key, and has no
  /// cipher) and holds what [path] holds.
  static void _verifySync(
      String path, String temp, Uint8List key, bool fullCheck, bool encrypt) {
    Database? source;
    Database? copy;
    try {
      if (encrypt) {
        copy = EncryptedOpen.open(temp, key: key);
        source = sqlite3.open(path);
      } else {
        if (EncryptedOpen.fileState(temp) != DatabaseFileState.plaintext) {
          throw const MigrationError("the decrypted copy isn't plaintext");
        }
        copy = sqlite3.open(temp);
        source = EncryptedOpen.open(path, key: key);
      }
      final check = copy
          .select(fullCheck ? "PRAGMA integrity_check" : "PRAGMA quick_check");
      if (check.length != 1 || check.first.values.first != "ok") {
        throw const MigrationError("the copy failed its check");
      }
      int version(Database db) =>
          db.select("PRAGMA user_version").first.values.first as int;
      if (version(source) != version(copy)) {
        throw const MigrationError("the copy has another version");
      }
      List<String> tables(Database db) => [
            for (final row in db
                .select("SELECT name FROM sqlite_master WHERE type = 'table' "
                    "ORDER BY name"))
              row["name"] as String
          ];
      final names = tables(source);
      final copied = tables(copy);
      if (names.length != copied.length ||
          !Iterable.generate(names.length)
              .every((i) => names[i] == copied[i])) {
        throw const MigrationError("the copy has other tables");
      }
      for (final name in names) {
        final quoted = '"${name.replaceAll('"', '""')}"';
        int count(Database db) =>
            db.select("SELECT count(*) FROM $quoted").first.values.first as int;
        if (count(source) != count(copy)) {
          throw const MigrationError("the copy has a different number of rows");
        }
      }
    } on MigrationError {
      rethrow;
    } on DatabaseKeyError catch (e) {
      throw MigrationError("the copy doesn't open: ${e.kind.name}");
    } on SqliteException catch (e) {
      throw MigrationError("verifying failed", code: e.extendedResultCode);
    } catch (e) {
      throw MigrationError("verifying failed: ${e.runtimeType}");
    } finally {
      try {
        copy?.close();
      } catch (_) {}
      try {
        source?.close();
      } catch (_) {}
    }
  }

  /// Overwrites [path] with zeros (1 MiB at a time), syncs and deletes it.
  /// Best effort: on SSDs and copy-on-write file systems the old blocks may
  /// survive (LOCAL-DATA-ENCRYPTION.md §6). Never throws for a missing
  /// file; deleting is attempted even when overwriting fails.
  static Future<void> secureDelete(String path) async {
    final file = File(path);
    if (!_exists(path)) return;
    try {
      final length = await file.length();
      // append: read/write without truncating; the position is set below.
      final raf = await file.open(mode: FileMode.append);
      try {
        final zeros = Uint8List(1024 * 1024);
        await raf.setPosition(0);
        var left = length;
        while (left > 0) {
          final n = left < zeros.length ? left : zeros.length;
          await raf.writeFrom(zeros, 0, n);
          left -= n;
        }
        await raf.flush();
      } finally {
        await raf.close();
      }
    } catch (_) {}
    await _deleteIfThere(path);
    for (final suffix in const ["-wal", "-shm", "-journal"]) {
      await _deleteIfThere("$path$suffix");
    }
  }

  /// Deletes a database file and its -wal/-shm/-journal without
  /// overwriting them (for encrypted files). Never throws for a missing
  /// file.
  static Future<void> deleteDatabaseFiles(String path) async {
    for (final suffix in const ["", "-wal", "-shm", "-journal"]) {
      await _deleteIfThere("$path$suffix");
    }
  }

  static Future<void> _deleteTemp(String temp) async {
    for (final suffix in const ["", "-journal", "-wal", "-shm"]) {
      await _deleteIfThere("$temp$suffix");
    }
  }

  static Future<void> _deleteIfThere(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      if (_exists(path)) rethrow;
    }
  }

  /// Renames, retrying for up to 5 s on Windows (scanners and indexers hold
  /// files open for a moment).
  static Future<void> _rename(String from, String to) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      try {
        await File(from).rename(to);
        return;
      } on FileSystemException {
        if (!Platform.isWindows || DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  static bool _exists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  static int _length(String path) {
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return 0;
    }
  }
}

/// The plaintext file as it was right after the checkpoint: a write after
/// that (by another engine) changes it or its WAL.
class _Stamp {
  const _Stamp(this.length, this.modified, this.walLength);

  final int length;
  final int modified;
  final int walLength;

  static _Stamp of(String path) {
    final stat = File(path).statSync();
    return _Stamp(stat.size, stat.modified.microsecondsSinceEpoch,
        DatabaseMigrator._length("$path-wal"));
  }

  bool matches(String path) {
    final now = of(path);
    return now.length == length &&
        now.modified == modified &&
        now.walLength == walLength &&
        walLength == 0;
  }
}
