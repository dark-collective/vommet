// Vommet: local data encryption, reading and writing keys/keystore.json.
//
// Writes are atomic (a 0600 temporary file renamed over the old one) and
// made under keys/.lock, a lock file created with O_EXCL. dart:io's
// RandomAccessFile.lock is a POSIX record lock, which doesn't exclude the
// other engines of the same process (Android runs the UI, a bubble and
// headless push engines in one process), so it isn't used.
import 'dart:async';
import 'dart:io';

import 'package:commet/debug/log.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/utils/disk_space.dart';
import 'package:commet/utils/private_files/owner_only.dart';
import 'package:path/path.dart' as p;

/// keystore.json exists but can't be read or used. Never written over.
class KeystoreUnreadable implements Exception {
  KeystoreUnreadable(this.message);
  final String message;
  @override
  String toString() => "KeystoreUnreadable: $message";
}

/// Another engine held keys/.lock for longer than [KeystoreFile.waitFor].
class KeystoreBusy implements Exception {
  @override
  String toString() => "KeystoreBusy: keys/.lock is held by another engine";
}

class KeystoreFile {
  KeystoreFile(this.directory,
      {this.staleAfter = staleLock, this.waitFor = lockWait});

  /// `<database dir>/keys`.
  final String directory;

  String get path => p.join(directory, "keystore.json");
  String get _lockPath => p.join(directory, ".lock");

  /// A lock not refreshed for this long was left by an engine that died
  /// holding it. A live holder refreshes it every quarter of that, for as
  /// long as it holds it (an unlock prompt may take minutes).
  static const Duration staleLock = Duration(seconds: 30);
  static const Duration lockWait = Duration(seconds: 20);

  final Duration staleAfter;
  final Duration waitFor;

  /// Makes the keys directory (0700) if needed.
  Future<void> ensureDirectory() async {
    final dir = Directory(directory);
    if (!await dir.exists()) await dir.create(recursive: true);
    await OwnerOnly.directory(directory);
  }

  /// The document, or null when there is none. Throws [KeystoreUnreadable]
  /// when the file is there but can't be read or parsed: whoever wrote it
  /// may know where a key is that this run doesn't, so it must not be
  /// replaced.
  Future<KeystoreDocument?> read() async {
    final String text;
    try {
      text = await File(path).readAsString();
    } on FileSystemException catch (error) {
      if (await FileSystemEntity.type(path) == FileSystemEntityType.notFound) {
        return null;
      }
      throw KeystoreUnreadable("can't read keystore.json: ${error.message}");
    }
    try {
      return KeystoreDocument.parse(text);
    } on KeystoreFormatException catch (error) {
      throw KeystoreUnreadable(error.message);
    }
  }

  /// Writes [doc] atomically, and syncs the folder so the rename survives
  /// a power loss (a keystore.json rolled back to before a new salt would
  /// leave that account's file without a key). Call under [locked].
  Future<void> write(KeystoreDocument doc) async {
    await ensureDirectory();
    final temp =
        File("$path.${KeyHierarchy.hex(KeyHierarchy.randomBytes(4))}.tmp");
    try {
      await temp.create(exclusive: true);
      await OwnerOnly.file(temp.path);
      // keystore.json holds no key, only salts (useless without the master
      // key): a folder that can't be made private is reported, not
      // refused (the master key file itself is refused, KeyFileIo).
      if (!await OwnerOnly.isOwnerOnly(temp.path)) {
        Log.w("keystore.json can't be made readable by this user only");
      }
      await temp.writeAsString(doc.encode(), flush: true);
      await temp.rename(path);
      DiskSpace.syncDirectory(directory);
    } catch (_) {
      try {
        await temp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Runs [action] holding keys/.lock. Waits up to [waitFor] for another
  /// holder. The lock holds a token of its holder and is refreshed while
  /// [action] runs; one not refreshed for [staleAfter] is taken over by
  /// renaming it away (atomic: of two engines that find it stale, one
  /// wins), never by deleting it.
  Future<T> locked<T>(Future<T> Function() action) async {
    await ensureDirectory();
    final lock = File(_lockPath);
    final token = KeyHierarchy.hex(KeyHierarchy.randomBytes(8));
    final deadline = DateTime.now().add(waitFor);
    while (true) {
      try {
        await lock.create(exclusive: true);
        try {
          await lock.writeAsString(token, flush: true);
        } catch (_) {}
        break;
      } on FileSystemException {
        if (await _takeOverStale(lock)) continue;
        if (DateTime.now().isAfter(deadline)) {
          throw KeystoreBusy();
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    // A quarter of the stale time: file times are set to the second.
    final heartbeat = Timer.periodic(staleAfter ~/ 4, (_) {
      try {
        if (lock.readAsStringSync() == token) {
          lock.setLastModifiedSync(DateTime.now());
        }
      } catch (_) {}
    });
    try {
      return await action();
    } finally {
      heartbeat.cancel();
      try {
        // Only this holder's lock (a takeover may have replaced it).
        if (await lock.readAsString() == token) await lock.delete();
      } catch (_) {}
    }
  }

  /// Takes a stale lock out of the way. True when the lock is gone (try
  /// again to create it).
  Future<bool> _takeOverStale(File lock) async {
    if (!await _isStale(lock)) return false;
    final aside = File(
        "${lock.path}.stale-${KeyHierarchy.hex(KeyHierarchy.randomBytes(4))}");
    try {
      await lock.rename(aside.path);
    } on FileSystemException {
      // Gone already, or another engine won: look again.
      return true;
    }
    // Refreshed between the look and the rename: its holder is alive, so
    // it goes back (unless a new lock was made meanwhile).
    if (!await _isStale(aside)) {
      try {
        if (await FileSystemEntity.type(lock.path) ==
            FileSystemEntityType.notFound) {
          await aside.rename(lock.path);
          return false;
        }
      } catch (_) {}
    }
    try {
      await aside.delete();
    } catch (_) {}
    return true;
  }

  Future<bool> _isStale(File lock) async {
    try {
      final stat = await lock.stat();
      if (stat.type == FileSystemEntityType.notFound) return true;
      return DateTime.now().difference(stat.modified) > staleAfter;
    } catch (_) {
      return false;
    }
  }

  /// Read, change and write under the lock. [change] returns false when
  /// nothing changed (no write). Returns the document as stored.
  Future<KeystoreDocument?> update(
      bool Function(KeystoreDocument doc) change) async {
    return locked(() async {
      final doc = await read();
      if (doc == null) return null;
      if (change(doc)) await write(doc);
      return doc;
    });
  }

  /// Temporary files a crash left between write and rename.
  Future<void> sweepTemporaryFiles() async {
    try {
      await for (final entity in Directory(directory).list()) {
        final name = p.basename(entity.path);
        if ((name.startsWith("keystore.json.") && name.endsWith(".tmp")) ||
            name.startsWith(".lock.stale-")) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }
}
