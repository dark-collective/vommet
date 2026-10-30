import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:commet/debug/log.dart';
import 'package:commet/utils/private_files/owner_only.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Vommet: short-lived plaintext copies of private media, for the things
/// that can only take a file path: the video, GIF, audio and voice message
/// players (media_kit's own in-memory source writes a temporary file too),
/// the system share sheet and the voice recorder.
///
/// They live in "media_open" in the app's own cache directory (never /tmp),
/// made 0700 with files 0600, under random names. Whoever asked for a copy
/// deletes it with [release] when done; anything left behind by a crash is
/// removed by [sweep] at the next start.
///
/// No copy is ever left readable by others: if the folder or a file can't
/// be made owner-only (checked on disk, on every platform but Windows,
/// where the per-user profile's ACLs do that), nothing is written and
/// [PrivateFilesUnavailable] is thrown, so playback or sharing fails with a
/// logged error instead.
class PrivateMediaFiles {
  /// Tests point this at a directory of their own (path_provider has no
  /// platform in unit tests). Not for app code.
  static String? directoryOverride;

  static const String folderName = "media_open";

  static Future<String>? _directory;

  /// The private directory, created 0700 if missing.
  static Future<String> directory() {
    final override = directoryOverride;
    if (override != null) return _ensure(override);
    return _directory ??= () async {
      final base = await getApplicationCacheDirectory();
      return _ensure(p.join(base.path, folderName));
    }()
        .catchError((Object error) {
      _directory = null;
      throw error;
    });
  }

  static Future<String> _ensure(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    await _ownerOnlyDirectory(path);
    return path;
  }

  static Future<void> _ownerOnlyDirectory(String path) async {
    await OwnerOnly.directory(path);
    if (!await OwnerOnly.isOwnerOnly(path)) {
      throw PrivateFilesUnavailable("Couldn't make $path owner-only");
    }
  }

  static Future<void> _ownerOnlyFile(File file) async {
    await OwnerOnly.file(file.path);
    if (!await OwnerOnly.isOwnerOnly(file.path)) {
      await _delete(file);
      throw PrivateFilesUnavailable("Couldn't make ${file.path} owner-only");
    }
  }

  static final Random _random = Random.secure();

  static String _randomName() {
    const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
    return String.fromCharCodes(Iterable.generate(
        24, (_) => chars.codeUnitAt(_random.nextInt(chars.length))));
  }

  /// A file extension safe to put in a name ("mp4"), or null.
  static String? safeExtension(String? extension) {
    if (extension == null) return null;
    final ext = extension.startsWith(".") ? extension.substring(1) : extension;
    if (!RegExp(r"^[A-Za-z0-9]{1,8}$").hasMatch(ext)) return null;
    return ext.toLowerCase();
  }

  /// A random path in the private directory, not created yet: for a
  /// recorder that makes the file itself (ffmpeg won't write over one).
  static Future<String> newPath({String? extension}) async {
    final dir = await directory();
    final ext = safeExtension(extension);
    return p.join(dir, ext == null ? _randomName() : "${_randomName()}.$ext");
  }

  /// A new, empty 0600 file at a random name. Throws
  /// [PrivateFilesUnavailable] when it can't be made owner-only.
  static Future<File> create({String? extension}) async {
    final dir = await directory();
    // The folder is checked again: something may have changed it since.
    await _ownerOnlyDirectory(dir);
    final file = File(await newPath(extension: extension));
    await file.create(exclusive: true);
    await _ownerOnlyFile(file);
    return file;
  }

  /// [bytes] written to a new private file. Release it when done.
  static Future<Uri> write(Uint8List bytes, {String? extension}) async {
    final file = await create(extension: extension);
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      await _delete(file);
      rethrow;
    }
    return file.uri;
  }

  /// [bytes] written as [name] (already a safe file name) in a new private
  /// folder of its own, for the share sheet, which shows the name. Release
  /// it when done; the folder goes with it.
  static Future<File> writeNamed(Uint8List bytes, String name) async {
    final dir = await directory();
    await _ownerOnlyDirectory(dir);
    final folder = Directory(p.join(dir, "share-${_randomName()}"));
    await folder.create();
    final file = File(p.join(folder.path, name));
    try {
      await _ownerOnlyDirectory(folder.path);
      await file.create(exclusive: true);
      await _ownerOnlyFile(file);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      await _deleteFolder(folder);
      rethrow;
    }
    return file;
  }

  /// Whether [path] is a private copy (inside [directory]).
  static Future<bool> isPrivate(String path) async {
    if (kIsWeb) return false;
    try {
      final dir = await Directory(await directory()).resolveSymbolicLinks();
      final parent = await Directory(p.dirname(path)).resolveSymbolicLinks();
      final real = p.join(parent, p.basename(path));
      return p.isWithin(dir, real);
    } catch (_) {
      return false;
    }
  }

  /// Deletes the private copy at [uri] (and the folder [writeNamed] made for
  /// it). Anything outside the private directory (a cached plain file, the
  /// user's own file) is left alone, so callers can release whatever a file
  /// provider resolved to. Never throws.
  static Future<void> release(Uri? uri) async {
    if (kIsWeb || uri == null || !uri.isScheme("file")) return;
    try {
      final path = uri.toFilePath();
      if (!await isPrivate(path)) return;
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.file ||
          type == FileSystemEntityType.link) {
        await File(path).delete();
      }
      final parent = p.dirname(path);
      final dir = await Directory(await directory()).resolveSymbolicLinks();
      final realParent = await Directory(parent).resolveSymbolicLinks();
      if (p.isWithin(dir, realParent)) {
        await _deleteFolder(Directory(realParent));
      }
    } catch (error) {
      Log.w("Couldn't delete a private media copy: $error");
    }
  }

  /// [release] once [done] (a player's dispose) has finished, so the player
  /// never loses the file under it.
  static void releaseAfter(Future<void>? done, Uri? uri) {
    if (uri == null) return;
    (done ?? Future<void>.value())
        .then((_) => release(uri), onError: (_) => release(uri));
  }

  /// Deletes what is left in the private directory from before [olderThan]
  /// ago: copies a crash or a kill left behind. Run at start-up; with [all]
  /// (sign-out) everything goes, copies in use included (players keep an
  /// open file on Linux, macOS and Android; Windows refuses and the next
  /// start-up gets it). Returns how many entries went.
  static Future<int> sweep(
      {Duration olderThan = const Duration(minutes: 1),
      bool all = false}) async {
    if (kIsWeb) return 0;
    var count = 0;
    try {
      final dir = Directory(await directory());
      final cutoff = DateTime.now().subtract(olderThan);
      await for (final entity in dir.list(followLinks: false)) {
        try {
          final stat = await entity.stat();
          if (!all && !stat.modified.isBefore(cutoff)) continue;
          if (entity is Directory) {
            // Dart's recursive delete doesn't follow links inside.
            await entity.delete(recursive: true);
          } else {
            await entity.delete();
          }
          count++;
        } catch (_) {
          // In use (Windows) or already gone.
        }
      }
    } catch (error) {
      Log.w("Couldn't sweep private media copies: $error");
    }
    if (count > 0) Log.i("Removed $count leftover private media copies");
    return count;
  }

  /// Vommet: Android copies of private media made outside [directory]:
  /// share_plus copies whatever is shared into the app cache's "share_plus"
  /// folder (for its FileProvider), and "Copy image" writes the PNG into
  /// "clipboard" (VommetClipboard.kt). At start-up the share copies go (no
  /// share sheet outlives the app) and a copied image older than
  /// [clipboardFor] (pasting apps read the file only when they paste, so it
  /// can't go right away); at sign-out ([all]) everything goes.
  /// [cacheDirectory] is for tests; elsewhere it is the app's cache
  /// directory, on Android only.
  static Future<int> sweepAndroidCopies({
    bool all = false,
    Duration clipboardFor = const Duration(minutes: 10),
    String? cacheDirectory,
  }) async {
    if (kIsWeb) return 0;
    var count = 0;
    try {
      final String base;
      if (cacheDirectory != null) {
        base = cacheDirectory;
      } else {
        if (!Platform.isAndroid) return 0;
        base = (await getApplicationCacheDirectory()).path;
      }
      final cutoff = all ? null : DateTime.now().subtract(clipboardFor);
      for (final name in androidCopyFolders) {
        final dir = Directory(p.join(base, name));
        if (await FileSystemEntity.type(dir.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        await for (final entity in dir.list(followLinks: false)) {
          try {
            if (name == "clipboard" && cutoff != null) {
              final stat = await entity.stat();
              if (!all && !stat.modified.isBefore(cutoff)) continue;
            }
            await entity.delete(recursive: true);
            count++;
          } catch (_) {}
        }
      }
    } catch (error) {
      Log.w("Couldn't sweep shared media copies: $error");
    }
    if (count > 0) Log.i("Removed $count shared media copies");
    return count;
  }

  /// The app cache folders [sweepAndroidCopies] empties.
  static const List<String> androidCopyFolders = ["share_plus", "clipboard"];

  static Future<void> _delete(File file) async {
    try {
      await file.delete();
    } catch (_) {}
  }

  static Future<void> _deleteFolder(Directory folder) async {
    try {
      await folder.delete(recursive: true);
    } catch (_) {}
  }
}

/// Vommet: a private copy couldn't be made owner-only, so it wasn't made.
class PrivateFilesUnavailable implements Exception {
  PrivateFilesUnavailable(this.message);

  final String message;

  @override
  String toString() => "PrivateFilesUnavailable: $message";
}
