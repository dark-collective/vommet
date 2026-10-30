import 'file_cache_stub.dart'
    if (dart.library.io) "package:commet/cache/drift_file_cache.dart";

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Vommet: what a cached file is, for the storage usage breakdown. The cache
/// stores no MIME type, so it is read from the file's first bytes.
enum CachedMediaType { images, videos, gifs, files, other }

abstract class FileCache {
  Future<void> init();

  Future<void> close();

  /// Whether [identifier] is cached. [sensitive] looks in the encrypted
  /// part of the cache (see [writeFile]).
  Future<bool> hasFile(String identifier, {bool sensitive = false});

  /// The plain cached file of [identifier]. Sensitive entries have no
  /// readable file: use [readFile].
  Future<Uri?> getFile(String identifier);

  /// Caches [bytes] as a plain file. Only for media that isn't private (from
  /// unencrypted rooms, avatars, emoji); use [writeFile] with `sensitive`
  /// for anything from an encrypted room.
  Future<Uri> putFile(String identifier, Uint8List bytes);

  /// Vommet: the cached bytes of [identifier], or null on a miss. A
  /// [sensitive] entry is opened (decrypted and checked) off the UI isolate;
  /// one that fails to open counts as a miss and is deleted.
  Future<Uint8List?> readFile(String identifier, {bool sensitive = false});

  /// Vommet: caches [bytes] for [identifier]. With [sensitive] (media from
  /// an encrypted room, including thumbnails) the bytes never reach the disk
  /// in plaintext: they are sealed with the cache key first, under a file
  /// name that doesn't show the identifier.
  Future<void> writeFile(String identifier, Uint8List bytes,
      {bool sensitive = false});

  /// Vommet: writes the cached [identifier] into the existing file at
  /// [path] (its permissions kept), streaming: a [sensitive] entry is opened
  /// a segment at a time off the UI isolate, so a big video is never held
  /// in memory. False on a miss (or an entry that fails to open); [path] is
  /// then left empty or partly written, for the caller to delete.
  Future<bool> openToFile(String identifier, String path,
      {bool sensitive = false});

  /// Vommet: [bytes] (small app data kept outside the cache, such as voice
  /// message transcripts) sealed under the cache key for [identifier], or
  /// null when no key is available (the data then isn't kept). Signing out
  /// deletes the key, after which nothing sealed with it opens again.
  Future<Uint8List?> sealData(String identifier, Uint8List bytes);

  /// Vommet: the bytes [sealData] sealed for [identifier], or null when
  /// [sealed] isn't that (another key, another identifier, changed).
  Future<Uint8List?> openData(String identifier, Uint8List sealed);

  /// Vommet: a file name for [identifier]'s sealed data that doesn't show
  /// the identifier (a keyed hash), or null when no key is available.
  Future<String?> dataNameOf(String identifier);

  /// Vommet: deletes the old cache in the temporary directory (where it was
  /// before it moved to the app's own cache directory). Never throws.
  Future<void> migrateLegacyCache();

  /// Vommet: deletes every sensitive entry and the key they were sealed
  /// with. Run at sign-out; a later sensitive write makes a new key.
  Future<void> forgetSensitive();

  Future<Uri> fetchFile(String identifier, Future<Uint8List> Function() getter);

  /// Removes media not opened within the "Keep media for" setting, then the
  /// least recently opened media while the cache is over its size limit.
  Future<void> clean();

  /// Vommet: how many files of each type the media cache directory holds and
  /// their size in bytes.
  Future<Map<CachedMediaType, ({int files, int bytes})>> usage();

  /// Vommet: deletes the cached media of [types] (all of it when null). Only
  /// files inside the media cache directory are ever deleted (see
  /// [isCachePath]); account databases, encryption keys and saved downloads
  /// live elsewhere and are never touched.
  Future<void> clearAll({Set<CachedMediaType>? types});

  /// Vommet: total size of the app's databases (messages, keys), shown next
  /// to the cache but never cleared by it. Null if unknown.
  Future<int?> databaseSize();

  /// Vommet: how long unused media is kept, from the "Keep media for" setting
  /// (days; 0 = forever). Null means keep forever.
  static Duration? retention(double days) {
    if (days <= 0) return null;
    return Duration(hours: (days * 24).round());
  }

  /// Vommet: the cache size limit in bytes from the "Media cache limit"
  /// setting (MB; 0 = unlimited). Null means unlimited.
  static int? sizeLimit(double megabytes) {
    if (megabytes <= 0) return null;
    return (megabytes * 1024 * 1024).round();
  }

  /// Vommet: whether [path] lies strictly inside [cacheDir]. The cache only
  /// deletes such paths, so a bad or stale database row can never point it at
  /// another file. Pass paths with symlinks already resolved.
  static bool isCachePath(String cacheDir, String path) {
    final dir = p.normalize(p.absolute(cacheDir));
    final file = p.normalize(p.absolute(path));
    return p.isWithin(dir, file);
  }

  /// Vommet: the type of a file from its first bytes (16 are enough).
  static CachedMediaType sniffType(List<int> head) {
    bool at(int offset, String ascii) {
      if (head.length < offset + ascii.length) return false;
      for (var i = 0; i < ascii.length; i++) {
        if (head[offset + i] != ascii.codeUnitAt(i)) return false;
      }
      return true;
    }

    bool bytes(List<int> magic) {
      if (head.length < magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (head[i] != magic[i]) return false;
      }
      return true;
    }

    if (head.isEmpty) return CachedMediaType.other;
    // Vommet: a sealed entry keeps its type in its header.
    if (at(0, "VME2") && head.length > 4) {
      final index = head[4];
      return index < CachedMediaType.values.length
          ? CachedMediaType.values[index]
          : CachedMediaType.other;
    }
    if (at(0, "GIF8")) return CachedMediaType.gifs;
    if (bytes([0x89, 0x50, 0x4E, 0x47]) ||
        bytes([0xFF, 0xD8, 0xFF]) ||
        (at(0, "RIFF") && at(8, "WEBP")) ||
        at(0, "BM")) {
      return CachedMediaType.images;
    }
    if (at(4, "ftyp")) {
      const imageBrands = ["avif", "avis", "heic", "heix", "hevc", "mif1"];
      const audioBrands = ["M4A ", "M4B "];
      if (imageBrands.any((b) => at(8, b))) return CachedMediaType.images;
      if (audioBrands.any((b) => at(8, b))) return CachedMediaType.other;
      return CachedMediaType.videos;
    }
    if (bytes([0x1A, 0x45, 0xDF, 0xA3])) return CachedMediaType.videos;
    if (at(0, "OggS") ||
        at(0, "ID3") ||
        at(0, "fLaC") ||
        (at(0, "RIFF") && at(8, "WAVE")) ||
        bytes([0xFF, 0xFB]) ||
        bytes([0xFF, 0xF3]) ||
        bytes([0xFF, 0xF2]) ||
        bytes([0xFF, 0xF1]) ||
        bytes([0xFF, 0xF9])) {
      return CachedMediaType.other;
    }
    return CachedMediaType.files;
  }

  /// Vommet: "1.4 MB" style size for the storage settings.
  static String formatSize(int bytes) {
    const units = ["B", "KB", "MB", "GB", "TB"];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = unit == 0 || value >= 100 ? 0 : 1;
    return "${value.toStringAsFixed(digits)} ${units[unit]}";
  }

  static FileCache? getFileCacheInstance() {
    return getFileCacheImplementation();
  }
}
