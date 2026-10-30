import 'dart:io';

import 'package:commet/debug/log.dart';
import 'package:path/path.dart' as p;

/// Vommet issue 836: on Linux, the files you pick to customize the app
/// (custom themes, fonts, sounds, app icons) live in
/// `$XDG_CONFIG_HOME/<app>` (normally `~/.config/im.nether.chat`, inside
/// `~/.var/app/<id>/config` on Flatpak) instead of the data folder with the
/// account databases, so they can be copied to another device or shared
/// without the private data. Databases, crypto stores, keys and downloaded
/// models stay in `$XDG_DATA_HOME`; caches already use `$XDG_CACHE_HOME`.
///
/// Existing installs are moved once, crash-safe: a folder is copied next to
/// its new place, checked byte for byte, then renamed into place (atomic),
/// and stored settings that point into the old folder are rewritten. The old
/// folder is only deleted once no stored setting points at it (on a later
/// start if one had to be rewritten) and every file in it has an identical
/// copy in the new one. A crash at any
/// step leaves either the old folder alone or a complete new one.
class XdgConfigDirs {
  /// Sub folders of the data folder that are user configuration.
  static const List<String> movedFolders = [
    "theme",
    "fonts",
    "sounds",
    "app_icon"
  ];

  XdgConfigDirs({required this.dataDir, required this.configDir});

  /// The old place: the app support folder (`$XDG_DATA_HOME/<app>`).
  final String dataDir;

  /// The new place: `$XDG_CONFIG_HOME/<app>`.
  final String configDir;

  /// `$XDG_CONFIG_HOME/<name of the data folder>`, or null when there is
  /// no usable config home (no `$HOME`). An `$XDG_CONFIG_HOME` that isn't
  /// absolute is ignored, as the XDG spec says.
  static String? configDirFor(String dataDir, Map<String, String> env) {
    var home = env["XDG_CONFIG_HOME"];
    if (home == null || home.isEmpty || !p.isAbsolute(home)) {
      final userHome = env["HOME"];
      if (userHome == null || userHome.isEmpty) return null;
      home = p.join(userHome, ".config");
    }
    final config = p.join(home, p.basename(dataDir));
    // Never the data folder itself (XDG_CONFIG_HOME == XDG_DATA_HOME).
    if (p.equals(config, dataDir)) return null;
    return config;
  }

  /// Where [folder] lives now: the new place, unless only the old one
  /// exists (the move hasn't run, or failed), so nothing is ever hidden.
  String folderPath(String folder) {
    final moved = p.join(configDir, folder);
    final old = p.join(dataDir, folder);
    if (!Directory(moved).existsSync() && Directory(old).existsSync()) {
      return old;
    }
    return moved;
  }

  /// Moves each folder in [movedFolders]. [readStrings] lists every stored
  /// string setting (key → value or list of values); [writeString] /
  /// [writeStringList] store a rewritten one. Never throws.
  Future<void> migrate({
    required Map<String, Object> Function() readStrings,
    required Future<void> Function(String key, String value) writeString,
    required Future<void> Function(String key, List<String> value)
        writeStringList,
  }) async {
    for (final folder in movedFolders) {
      try {
        await _migrateFolder(folder, readStrings, writeString, writeStringList);
      } catch (e, s) {
        Log.onError(e, s,
            content: "Could not move the $folder folder to $configDir");
      }
    }
  }

  Future<void> _migrateFolder(
    String folder,
    Map<String, Object> Function() readStrings,
    Future<void> Function(String key, String value) writeString,
    Future<void> Function(String key, List<String> value) writeStringList,
  ) async {
    final old = Directory(p.join(dataDir, folder));
    final moved = Directory(p.join(configDir, folder));
    if (!await old.exists()) return;

    if (!await moved.exists()) {
      await Directory(configDir).create(recursive: true);
      // Copy next to the final place (same file system, so the rename is
      // atomic); a leftover from a crashed attempt is thrown away first.
      final staging = Directory(p.join(configDir, ".$folder.moving"));
      if (await staging.exists()) await staging.delete(recursive: true);
      await _copyTree(old, staging);
      if (!await _sameTree(old, staging)) {
        await staging.delete(recursive: true);
        throw StateError("The copy of $folder doesn't match the original");
      }
      try {
        await staging.rename(moved.path);
      } on FileSystemException {
        // Something made the new folder meanwhile; keep it, drop ours.
        if (!await moved.exists()) rethrow;
        await staging.delete(recursive: true);
      }
      Log.i("Moved ${old.path} to ${moved.path} (Vommet issue 836)");
    }

    // Settings that hold a file path point at the new folder (again, if a
    // crash came between the rename and this).
    final rewritten = await _rewritePaths(
        old.path, moved.path, readStrings, writeString, writeStringList);

    // The old folder goes only when nothing refers to it (paths rewritten
    // just now wait for a later start: the splash may still show a file
    // from it) and the new folder has every file in it unchanged; otherwise
    // it stays (e.g. an older version wrote into it after a downgrade).
    if (rewritten) return;
    if (_referencesOld(old.path, readStrings())) return;
    if (!await _contains(moved, old)) {
      Log.w("Keeping ${old.path}: it has files that ${moved.path} doesn't");
      return;
    }
    await old.delete(recursive: true);
  }

  static bool _pointsInto(String value, String dir) =>
      value == dir || value.contains("$dir${p.separator}");

  static bool _referencesOld(String oldDir, Map<String, Object> strings) {
    for (final value in strings.values) {
      if (value is String && _pointsInto(value, oldDir)) return true;
      if (value is List<String> && value.any((v) => _pointsInto(v, oldDir))) {
        return true;
      }
    }
    return false;
  }

  /// Rewrites stored values that contain a path into [oldDir]. Returns
  /// whether any was changed.
  static Future<bool> _rewritePaths(
    String oldDir,
    String newDir,
    Map<String, Object> Function() readStrings,
    Future<void> Function(String key, String value) writeString,
    Future<void> Function(String key, List<String> value) writeStringList,
  ) async {
    String fix(String v) => v == oldDir
        ? newDir
        : v.replaceAll("$oldDir${p.separator}", "$newDir${p.separator}");
    var changed = false;
    for (final entry in readStrings().entries) {
      final value = entry.value;
      if (value is String && _pointsInto(value, oldDir)) {
        await writeString(entry.key, fix(value));
        changed = true;
      } else if (value is List<String> &&
          value.any((v) => _pointsInto(v, oldDir))) {
        await writeStringList(entry.key, value.map(fix).toList());
        changed = true;
      }
    }
    return changed;
  }

  static Future<void> _copyTree(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(followLinks: false)) {
      final target = p.join(to.path, p.basename(entity.path));
      if (entity is Link) {
        await Link(target).create(await entity.target());
      } else if (entity is Directory) {
        await _copyTree(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      }
    }
  }

  /// Whether [a] and [b] hold the same entries with the same contents.
  static Future<bool> _sameTree(Directory a, Directory b) async =>
      await _contains(b, a) && await _contains(a, b);

  /// Whether every entry under [inner] has an identical one in [outer].
  static Future<bool> _contains(Directory outer, Directory inner) async {
    await for (final entity
        in inner.list(recursive: true, followLinks: false)) {
      final rel = p.relative(entity.path, from: inner.path);
      final other = p.join(outer.path, rel);
      if (entity is Link) {
        if (!await Link(other).exists() ||
            await Link(other).target() != await entity.target()) {
          return false;
        }
      } else if (entity is Directory) {
        if (!await Directory(other).exists()) return false;
      } else if (entity is File) {
        final otherFile = File(other);
        if (!await otherFile.exists()) return false;
        if (await otherFile.length() != await entity.length()) return false;
        if (!_sameBytes(
            await otherFile.readAsBytes(), await entity.readAsBytes())) {
          return false;
        }
      }
    }
    return true;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
