// Vommet: local data encryption, small owner-only files under keys/ that
// start with a 4-byte magic ("VDK1" for the plain key file, "VDP1" for a
// DPAPI blob, "VPW1" for a portal-wrapped key).
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/utils/disk_space.dart';
import 'package:commet/utils/private_files/owner_only.dart';
import 'package:path/path.dart' as p;

/// A key file that couldn't be made owner-only (a file system without
/// permissions, or a chmod that failed): it isn't kept.
class KeyFileNotPrivate implements Exception {
  const KeyFileNotPrivate();
  @override
  String toString() =>
      "KeyFileNotPrivate: the keys folder can't be made readable by this user "
      "only";
}

class KeyFileIo {
  KeyFileIo(this.path, this.magic) : assert(magic.length == 4);

  /// For tests: replaces the owner-only check of a written key file.
  static Future<bool> Function(String path)? debugIsOwnerOnly;

  static Future<bool> _isOwnerOnly(String path) =>
      (debugIsOwnerOnly ?? OwnerOnly.isOwnerOnly)(path);

  final String path;
  final List<int> magic;

  /// The payload after the magic; null when there is no file. Throws
  /// [FileSystemException] when it can't be read and [FormatException] when
  /// it isn't one of these files.
  Future<Uint8List?> read() async {
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException {
      if (await FileSystemEntity.type(path) == FileSystemEntityType.notFound) {
        return null;
      }
      rethrow;
    }
    if (bytes.length < magic.length) {
      throw const FormatException("key file is too short");
    }
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        throw const FormatException("not a key file");
      }
    }
    return Uint8List.fromList(Uint8List.sublistView(bytes, magic.length));
  }

  /// Writes magic + [payload] atomically with mode 0600 in a 0700 folder.
  /// Throws [KeyFileNotPrivate] (and keeps nothing) when the file isn't
  /// owner-only afterwards: key material is never left readable by others.
  Future<void> write(List<int> payload) async {
    final dir = Directory(p.dirname(path));
    if (!await dir.exists()) await dir.create(recursive: true);
    await OwnerOnly.directory(dir.path);
    final temp =
        File("$path.${KeyHierarchy.hex(KeyHierarchy.randomBytes(4))}.tmp");
    try {
      await temp.create(exclusive: true);
      await OwnerOnly.file(temp.path);
      // Checked on the file system, before anything is written to it, so a
      // chmod that failed or does nothing here (FAT, some network shares)
      // shows.
      if (!await _isOwnerOnly(temp.path) || !await _isOwnerOnly(dir.path)) {
        throw const KeyFileNotPrivate();
      }
      final data = Uint8List(magic.length + payload.length)
        ..setRange(0, magic.length, magic)
        ..setRange(magic.length, magic.length + payload.length, payload);
      await temp.writeAsBytes(data, flush: true);
      data.fillRange(0, data.length, 0);
      await temp.rename(path);
      DiskSpace.syncDirectory(dir.path);
    } catch (_) {
      try {
        await temp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Overwrites the file with zeros, then deletes it. A missing file is
  /// fine.
  Future<void> delete() async {
    final file = File(path);
    try {
      final length = await file.length();
      final raf = await file.open(mode: FileMode.writeOnlyAppend);
      try {
        await raf.setPosition(0);
        await raf.writeFrom(Uint8List(length));
        await raf.flush();
      } finally {
        await raf.close();
      }
    } on FileSystemException {
      // Missing, or not writable: the delete below says which.
    }
    try {
      await file.delete();
    } on FileSystemException {
      if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
        rethrow;
      }
    }
  }

  Future<bool> exists() => File(path).exists();

  /// Renames the file out of the way (`<name>.archived-<time>`), keeping
  /// the key it holds. Nothing to do when there is no file. Returns the new
  /// path, or null.
  Future<String?> archive() async {
    if (await FileSystemEntity.type(path) == FileSystemEntityType.notFound) {
      return null;
    }
    var target = "$path.archived-${DateTime.now().millisecondsSinceEpoch}";
    while (
        await FileSystemEntity.type(target) != FileSystemEntityType.notFound) {
      target = "$target-${KeyHierarchy.hex(KeyHierarchy.randomBytes(2))}";
    }
    await File(path).rename(target);
    DiskSpace.syncDirectory(p.dirname(path));
    return target;
  }
}
