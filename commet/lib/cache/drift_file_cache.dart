import 'dart:io';
import 'package:commet/cache/file_cache.dart';
import 'package:commet/config/app_config.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/database/multiple_database_server.dart';
import 'package:commet/utils/rng.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'drift_file_cache.g.dart';

FileCache? getFileCacheImplementation() {
  return DriftFileCache();
}

class FileCacheEntry extends Table {
  TextColumn get id => text()();
  TextColumn get path => text()();

  IntColumn get lastAccessedTimestamp => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [FileCacheEntry])
class DriftFileCacheDatabase extends _$DriftFileCacheDatabase {
  DriftFileCacheDatabase(super.e);

  @override
  int get schemaVersion => 1;
}

class DriftFileCache implements FileCache {
  DriftFileCacheDatabase? database;

  static const String isolateName = "chat.commet.commetapp.isolate.file_cache";

  @override
  Future<void> clean() async {
    Log.i("Cleaning files");
    final db = await get();

    // Vommet: "Keep media for" setting (default 5 days, the old fixed value).
    final keep = FileCache.retention(preferences.mediaCacheKeepDays.value);
    if (keep == null) {
      Log.i("Keeping cached media forever");
    } else {
      var now = DateTime.now();
      var cutoffTime = now.subtract(keep);
      var timeMs = cutoffTime.millisecondsSinceEpoch;

      var removeFiles = await (db.select(db.fileCacheEntry)
            ..where(
                (tbl) => tbl.lastAccessedTimestamp.isSmallerThanValue(timeMs)))
          .get();

      var allFiles = await (db.select(db.fileCacheEntry).get());

      Log.i(
          "Found: ${removeFiles.length}/${allFiles.length} files for cleaning");

      await _forget(db, await _deleteEntries(removeFiles));
    }

    // Vommet: "Media cache limit": least recently opened media goes first.
    final limit = FileCache.sizeLimit(preferences.mediaCacheLimitMb.value);
    if (limit != null) await _evictOverLimit(db, limit);
  }

  Future<void> _evictOverLimit(DriftFileCacheDatabase db, int limit) async {
    final entries = await (db.select(db.fileCacheEntry)
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.lastAccessedTimestamp)]))
        .get();

    final sizes = <String, int>{};
    var total = 0;
    for (final entry in entries) {
      try {
        final size = await File(entry.path).length();
        sizes[entry.id] = size;
        total += size;
      } catch (_) {
        // Missing; hasFile forgets the row on next use.
      }
    }
    if (total <= limit) return;

    final dir = await cacheDirectory();
    final removed = <String>[];
    for (final entry in entries) {
      if (total <= limit) break;
      final size = sizes[entry.id];
      if (size == null) continue;
      if (await deleteCachedFile(dir, entry.path)) {
        removed.add(entry.id);
        total -= size;
      }
    }
    await _forget(db, removed);
    Log.i("Over the cache limit: removed ${removed.length} files");
  }

  /// Vommet: the media cache directory itself, so files a past clean-up
  /// failed to delete are counted too.
  @override
  Future<Map<CachedMediaType, ({int files, int bytes})>> usage() async {
    final result = {
      for (final type in CachedMediaType.values) type: (files: 0, bytes: 0)
    };
    final dir = Directory(await cacheDirectory());
    if (!await dir.exists()) return result;

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final size = await entity.length();
        final type = await readType(entity.path);
        final current = result[type]!;
        result[type] = (files: current.files + 1, bytes: current.bytes + size);
      } catch (_) {
        // Deleted while listing.
      }
    }
    return result;
  }

  /// Vommet: deletes the cached files of [types] (all when null) that the
  /// database knows about, then any leftover file of those types in the cache
  /// directory that no row tracks (older than a minute, so a download being
  /// written right now is left alone).
  @override
  Future<void> clearAll({Set<CachedMediaType>? types}) async {
    final db = await get();
    final startedAt = DateTime.now();
    var entries = await db.select(db.fileCacheEntry).get();
    if (types != null) {
      final matching = <FileCacheEntryData>[];
      for (final entry in entries) {
        if (types.contains(await readType(entry.path))) matching.add(entry);
      }
      entries = matching;
    }

    // Only the rows read above, and only those whose file is really gone (a
    // locked file on Windows stays tracked so a later clean can retry).
    final removed = await _deleteEntries(entries);
    await _forget(db, removed);

    final tracked =
        (await db.select(db.fileCacheEntry).get()).map((e) => e.path).toSet();
    final swept = await sweepUntracked(await cacheDirectory(), tracked,
        startedAt.subtract(const Duration(minutes: 1)),
        types: types);

    Log.i(
        "Cleared ${removed.length}/${entries.length} cached files, $swept untracked");
  }

  /// Deletes the entries' files; returns the ids whose rows can be forgotten.
  Future<List<String>> _deleteEntries(List<FileCacheEntryData> entries) async {
    final dir = await cacheDirectory();
    final removed = <String>[];
    for (final entry in entries) {
      if (await deleteCachedFile(dir, entry.path)) removed.add(entry.id);
    }
    return removed;
  }

  Future<void> _forget(DriftFileCacheDatabase db, List<String> ids) async {
    if (ids.isEmpty) return;
    await (db.delete(db.fileCacheEntry)..where((tbl) => tbl.id.isIn(ids))).go();
  }

  /// Vommet: the type of the file at [path] from its first bytes; "other"
  /// when it can't be read.
  static Future<CachedMediaType> readType(String path) async {
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      return FileCache.sniffType(await file.read(16));
    } catch (_) {
      return CachedMediaType.other;
    } finally {
      await file?.close();
    }
  }

  /// Vommet: deletes [path] only if it is a regular file strictly inside
  /// [cacheDir] (symlinks resolved, never followed). Anything else (a path
  /// outside the cache, a link, a directory) is left on disk. Returns whether
  /// the database row can be forgotten: true once the file is gone or the row
  /// points outside the cache, false if deleting failed.
  static Future<bool> deleteCachedFile(String cacheDir, String path) async {
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return true;
      if (type != FileSystemEntityType.file) {
        Log.w("Not deleting non-file cache entry: $path");
        return true;
      }

      final realDir = await Directory(cacheDir).resolveSymbolicLinks();
      final realPath = await File(path).resolveSymbolicLinks();
      if (!FileCache.isCachePath(realDir, realPath)) {
        Log.w("Not deleting cache entry outside the cache directory: $path");
        return true;
      }

      await File(realPath).delete();
      return true;
    } catch (e) {
      Log.w("Couldn't delete cached file $path: $e");
      return false;
    }
  }

  /// Vommet: deletes regular files directly in [cacheDir] that aren't in
  /// [tracked], were last modified before [olderThan] and are of [types] (any
  /// type when null). Returns how many.
  static Future<int> sweepUntracked(
      String cacheDir, Set<String> tracked, DateTime olderThan,
      {Set<CachedMediaType>? types}) async {
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return 0;

    final trackedPaths = tracked.map(p.normalize).toSet();
    var count = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (trackedPaths.contains(p.normalize(entity.path))) continue;
      try {
        if (!(await entity.lastModified()).isBefore(olderThan)) continue;
      } catch (_) {
        continue;
      }
      if (types != null && !types.contains(await readType(entity.path))) {
        continue;
      }
      if (await deleteCachedFile(cacheDir, entity.path)) count++;
    }
    return count;
  }

  /// Vommet: total size of the app's databases (messages, keys, this cache's
  /// index), for the storage usage page. Read only; null if unknown.
  @override
  Future<int?> databaseSize() async {
    try {
      final dir = Directory(await AppConfig.getDatabasePath());
      if (!await dir.exists()) return null;
      var total = 0;
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    return await database?.close();
  }

  @override
  Future<Uri> fetchFile(
      String identifier, Future<Uint8List> Function() getter) async {
    var existing = await getFile(identifier);
    if (existing != null) return existing;

    var bytes = await getter();
    var path = await generateTempFilePath();
    if (BuildConfig.DEBUG) path += "_${Uri.encodeComponent(identifier)}";

    var file = File(path);
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);

    var entry = FileCacheEntryCompanion.insert(
        id: identifier,
        path: path,
        lastAccessedTimestamp: DateTime.now().millisecondsSinceEpoch);
    final db = await get();
    await db.into(db.fileCacheEntry).insertOnConflictUpdate(entry);

    return file.uri;
  }

  @override
  Future<Uri?> getFile(String identifier) async {
    if (!await hasFile(identifier)) return null;

    var entry = await _getByFileId(identifier);
    if (entry == null) return null;
    //var lastAccess = DateTime.fromMillisecondsSinceEpoch(entry!.lastAccessedTimestamp).toLocal().toString();
    final db = await get();
    db.into(db.fileCacheEntry).insertOnConflictUpdate(entry.copyWith(
        lastAccessedTimestamp: DateTime.now().millisecondsSinceEpoch));

    var file = File(entry.path);

    return file.uri;
  }

  @override
  Future<bool> hasFile(String identifier) async {
    var file = await _getByFileId(identifier);
    if (file == null) return false;
    final db = await get();
    // if the file exists in the database but not on disk, we should remove it from db
    var exists = await File(file.path).exists();
    if (!exists)
      (db.delete(db.fileCacheEntry)..where((tbl) => tbl.id.equals(file.id)))
          .go();

    return exists;
  }

  @override
  Future<void> init() async {
    Log.i("Cache: ${await cacheDirectory()}");

    final dir = p.join(await AppConfig.getDatabasePath(), "app");
    var directory = Directory(dir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File(p.join(dir, "app_data.db"));

    var connection = await DatabaseIsolate.connect(file.absolute.path);
    database = DriftFileCacheDatabase(connection);
  }

  @override
  Future<Uri> putFile(String identifier, Uint8List bytes) async {
    var path = await generateTempFilePath();
    if (BuildConfig.DEBUG) path += "_${Uri.encodeComponent(identifier)}";
    final db = await get();
    var file = File(path);
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);

    var entry = FileCacheEntryCompanion.insert(
        id: identifier,
        path: path,
        lastAccessedTimestamp: DateTime.now().millisecondsSinceEpoch);

    await db.into(db.fileCacheEntry).insertOnConflictUpdate(entry);

    return file.uri;
  }

  Future<DriftFileCacheDatabase> get() async {
    if (database != null) {
      return database!;
    }

    await init();
    return database!;
  }

  /// The media cache directory: every cached file is created directly in it,
  /// and clean-up and clearing never delete anything outside it.
  static Future<String> cacheDirectory() async {
    final dir = await getTemporaryDirectory();
    return p.join(dir.path, "chat.commet.app", "file_cache");
  }

  Future<String> newPath() async {
    String fileName = RandomUtils.getRandomString(30);
    return p.join(await cacheDirectory(), fileName);
  }

  Future<String> generateTempFilePath() async {
    var path = "";
    for (path = await newPath();
        await File(path).exists();
        path = await newPath()) {}

    return path;
  }

  Future<FileCacheEntryData?> _getByFileId(String fileId) async {
    final db = await get();
    return (db.select(db.fileCacheEntry)
          ..where((tbl) => tbl.id.equals(fileId))
          ..limit(1))
        .getSingleOrNull();
  }
}
