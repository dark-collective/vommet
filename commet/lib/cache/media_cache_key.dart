import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:commet/debug/log.dart';
import 'package:commet/utils/private_files/owner_only.dart';
import 'package:path/path.dart' as p;

/// Vommet: the master key of the encrypted part of the media cache: 32
/// random bytes in a 0600 file next to the app's databases
/// ("<database dir>/app/media_cache.key").
///
/// The app has no OS keyring today; its account databases (messages and the
/// keys of every attachment) are protected only by the user's profile. This
/// key gets that same protection on every platform, so the media cache is
/// never weaker than the data it is a copy of. What it adds: the cache can
/// sit in a cache directory (which backups, sync tools and cleaners treat as
/// disposable) without its contents being readable there, and signing out
/// deletes the key, which makes anything a failed delete left behind
/// unreadable.
///
/// The file is "VMK1" followed by the key. A missing, short or otherwise
/// damaged file means a new key (and the old sealed entries are wiped); one
/// that can't be read at all, or a key or folder that can't be made
/// owner-only, means no sealed caching for that run.
class MediaCacheKeyFile {
  MediaCacheKeyFile(this.path);

  final String path;

  static const List<int> _magic = [0x56, 0x4D, 0x4B, 0x31]; // "VMK1"
  static const int keyLength = 32;

  /// The stored key, or null when there is none or it is damaged (both mean
  /// a new key). Throws [MediaCacheKeyUnreadable] when the file is there but
  /// can't be read (a permission or I/O error): a new key must not then be
  /// written over one that may still be fine.
  Future<Uint8List?> read() async {
    final folder = p.dirname(path);
    if (await FileSystemEntity.type(folder) == FileSystemEntityType.directory) {
      await _ownerOnly(folder, directory: true);
    }
    final file = File(path);
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (error) {
      // ENOENT: there is no key yet.
      if (error.osError?.errorCode == 2 ||
          await FileSystemEntity.type(path) == FileSystemEntityType.notFound) {
        return null;
      }
      throw MediaCacheKeyUnreadable(error.toString());
    }
    await _ownerOnly(path, directory: false);
    if (bytes.length != _magic.length + keyLength) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return null;
    }
    return Uint8List.sublistView(bytes, _magic.length);
  }

  /// A new random key, written atomically (a 0600 temporary file renamed
  /// over the old one). Returns the key now on disk: if another engine of the
  /// app (the background notification service) wrote one at the same
  /// moment, both end up using the same.
  Future<Uint8List> create() async {
    final random = Random.secure();
    final key = Uint8List(keyLength);
    for (var i = 0; i < keyLength; i++) {
      key[i] = random.nextInt(256);
    }

    final dir = Directory(p.dirname(path));
    if (!await dir.exists()) await dir.create(recursive: true);
    await _ownerOnly(dir.path, directory: true);

    final temp = File("$path.${random.nextInt(1 << 32).toRadixString(16)}.tmp");
    try {
      await temp.create(exclusive: true);
      await _ownerOnly(temp.path, directory: false);
      await temp.writeAsBytes([..._magic, ...key], flush: true);
      await temp.rename(path);
    } catch (error) {
      try {
        await temp.delete();
      } catch (_) {}
      rethrow;
    }
    return await read() ?? key;
  }

  /// Vommet: [path] made owner-only (a 0700 folder, a 0600 file) and read
  /// back to be sure. One that can't be (no chmod, or it didn't take) throws
  /// [MediaCacheKeyUnreadable], which turns sealed caching off for the run:
  /// a key others can read, or a folder others can swap it in, would be no
  /// key at all. Windows has no modes (the profile's ACLs apply).
  static Future<void> _ownerOnly(String path, {required bool directory}) async {
    if (Platform.isWindows || await OwnerOnly.isOwnerOnly(path)) return;
    if (directory) {
      await OwnerOnly.directory(path);
    } else {
      await OwnerOnly.file(path);
    }
    if (!await OwnerOnly.isOwnerOnly(path)) {
      throw MediaCacheKeyUnreadable("$path can't be made owner-only");
    }
  }

  /// Deletes the key. Never throws.
  Future<void> delete() async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (error) {
      Log.w("Couldn't delete the media cache key: $error");
    }
  }
}

/// Vommet: the media cache key file exists but couldn't be read.
class MediaCacheKeyUnreadable implements Exception {
  MediaCacheKeyUnreadable(this.message);

  final String message;

  @override
  String toString() => "Media cache key unreadable: $message";
}
