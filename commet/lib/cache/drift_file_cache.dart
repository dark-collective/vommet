import 'dart:async';
import 'dart:io';
import 'package:commet/cache/file_cache.dart';
import 'package:commet/cache/media_cache_crypto.dart';
import 'package:commet/cache/media_cache_key.dart';
import 'package:commet/config/app_config.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/database/multiple_database_server.dart';
import 'package:commet/utils/private_files/owner_only.dart';
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
  /// Vommet: tests pass directories of their own (path_provider has no
  /// platform in unit tests): [cacheDir] for the cache, [keyPath] for the
  /// key file and [tempDir] for the temporary directory the old cache was
  /// in.
  DriftFileCache({String? cacheDir, String? keyPath, String? tempDir})
      : _cacheDirOverride = cacheDir,
        _keyPathOverride = keyPath,
        _tempDirOverride = tempDir;

  final String? _cacheDirOverride;
  final String? _keyPathOverride;
  final String? _tempDirOverride;

  DriftFileCacheDatabase? database;

  /// Vommet: seals and opens sensitive entries off the UI isolate.
  final MediaCacheWorker _worker = MediaCacheWorker();

  /// Vommet: the key of the sensitive entries, loaded (or made) on first use.
  Future<MediaCacheCrypto>? _crypto;

  /// Vommet: bumped when the sensitive entries are forgotten, so a write that
  /// was sealing under the old key at that moment deletes what it wrote, and
  /// a key load that overlapped a forget is never used.
  int _keyGeneration = 0;

  /// Vommet: the forget in progress, if any; key loads wait for it.
  Future<void>? _forgetting;

  /// Vommet: the key file couldn't be read (an I/O or permission error, not
  /// a missing file). Sensitive media then isn't cached at all for the rest
  /// of the run, rather than replacing a key that may still be fine.
  bool _sealingDisabled = false;

  /// Vommet: how many forgets this engine started; a sealed write asked for
  /// before one is dropped (see [_writeSealed]).
  int _forgets = 0;

  /// Vommet: the key file as it was when [_crypto] was loaded, to notice
  /// another engine of the app (the Android background service, or the
  /// app while this is that service) forgetting or replacing it.
  ({DateTime modified, int size})? _keyStamp;

  static const String isolateName = "chat.commet.commetapp.isolate.file_cache";

  /// Vommet: set by [close]; the delayed clean-up then does nothing.
  bool _closed = false;

  @override
  Future<void> clean() async {
    if (_closed) return;
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
      if (p.basename(entity.path) == keyCheckFileName) continue;
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

    final dir = await cacheDirectory();
    final tracked = {
      ...(await db.select(db.fileCacheEntry).get()).map((e) => e.path),
      p.join(dir, keyCheckFileName),
    };
    final swept = await sweepUntracked(
        dir, tracked, startedAt.subtract(const Duration(minutes: 1)),
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
    _closed = true;
    _worker.close();
    return await database?.close();
  }

  @override
  Future<Uri> fetchFile(
      String identifier, Future<Uint8List> Function() getter) async {
    var existing = await getFile(identifier);
    if (existing != null) return existing;

    var bytes = await getter();
    return putFile(identifier, bytes);
  }

  @override
  Future<Uri?> getFile(String identifier) async {
    if (!await hasFile(identifier)) return null;

    FileCacheEntryData? entry;
    try {
      entry = await _getByFileId(identifier);
    } catch (error) {
      Log.w("File cache lookup failed: $error");
      return null;
    }
    if (entry == null) return null;
    _touch(entry);

    var file = File(entry.path);

    return file.uri;
  }

  @override
  Future<bool> hasFile(String identifier, {bool sensitive = false}) async {
    // Vommet: a lookup that fails (the database was closed under an image
    // still loading, e.g. at sign-out or test teardown) counts as a cache
    // miss instead of an uncaught ConnectionClosedException.
    try {
      final String rowId;
      if (sensitive) {
        final crypto = await _cryptoKey();
        if (crypto == null) return false;
        rowId = crypto.rowIdOf(identifier);
      } else {
        if (_isSealedRowId(identifier)) return false;
        rowId = identifier;
      }
      var file = await _getByFileId(rowId);
      if (file == null) return false;
      final db = await get();
      // if the file exists in the database but not on disk, we should remove it from db
      var exists = await File(file.path).exists();
      if (!exists)
        _ignoreFailure((db.delete(db.fileCacheEntry)
              ..where((tbl) => tbl.id.equals(file.id)))
            .go());

      return exists;
    } catch (error) {
      Log.w("File cache lookup failed: $error");
      return false;
    }
  }

  @override
  Future<Uint8List?> readFile(String identifier,
      {bool sensitive = false}) async {
    if (!sensitive) {
      try {
        final uri = await getFile(identifier);
        if (uri == null) return null;
        return await File.fromUri(uri).readAsBytes();
      } catch (error) {
        Log.w("File cache read failed: $error");
        return null;
      }
    }

    try {
      final crypto = await _cryptoKey();
      if (crypto == null) return null;
      final entry = await _getByFileId(crypto.rowIdOf(identifier));
      if (entry == null) return null;

      Uint8List? plain;
      try {
        final length = await File(entry.path).length();
        if (length >= MediaCacheCrypto.ownIsolateBytes) {
          plain = await MediaCacheWorker.openFileToBytes(
              crypto.encryptionKey, identifier, entry.path);
        } else {
          final sealed = await File(entry.path).readAsBytes();
          plain = await _worker.open(crypto.encryptionKey, identifier, sealed);
        }
      } on FileSystemException catch (_) {
        // Gone from disk: forget the row.
        await _forget(await get(), [entry.id]);
        return null;
      }

      if (plain == null) {
        // Changed, cut short, another entry's file or another key's: a
        // miss, and the file goes so it is fetched afresh.
        Log.w("Dropping a cached media entry that failed to open");
        await _forget(await get(), await _deleteEntries([entry]));
        return null;
      }
      _touch(entry);
      return plain;
    } catch (error) {
      Log.w("File cache read failed: $error");
      return null;
    }
  }

  @override
  Future<bool> openToFile(String identifier, String path,
      {bool sensitive = false}) async {
    try {
      if (!sensitive) {
        final uri = await getFile(identifier);
        if (uri == null) return false;
        final out = File(path).openWrite();
        await File.fromUri(uri).openRead().pipe(out);
        return true;
      }

      final crypto = await _cryptoKey();
      if (crypto == null) return false;
      final entry = await _getByFileId(crypto.rowIdOf(identifier));
      if (entry == null) return false;
      final bool opened;
      try {
        final length = await File(entry.path).length();
        if (length < MediaCacheCrypto.ownIsolateBytes) {
          final plain = await readFile(identifier, sensitive: true);
          if (plain == null) return false;
          await File(path).writeAsBytes(plain, flush: true);
          return true;
        }
        opened = await MediaCacheWorker.openToFile(
            crypto.encryptionKey, identifier, entry.path, path);
      } on FileSystemException catch (_) {
        if (!await File(entry.path).exists()) {
          await _forget(await get(), [entry.id]);
        }
        rethrow;
      }
      if (!opened) {
        Log.w("Dropping a cached media entry that failed to open");
        await _forget(await get(), await _deleteEntries([entry]));
        return false;
      }
      _touch(entry);
      return true;
    } catch (error) {
      Log.w("File cache read failed: $error");
      return false;
    }
  }

  /// Keeps sealed app data apart from media sealed for the same string.
  static const String _dataPrefix = "vommet-data:";

  @override
  Future<Uint8List?> sealData(String identifier, Uint8List bytes) async {
    try {
      final crypto = await _cryptoKey();
      if (crypto == null) return null;
      return await _worker.seal(crypto.encryptionKey, "$_dataPrefix$identifier",
          CachedMediaType.other.index, bytes);
    } catch (error) {
      Log.w("Couldn't seal app data: $error");
      return null;
    }
  }

  @override
  Future<Uint8List?> openData(String identifier, Uint8List sealed) async {
    try {
      final crypto = await _cryptoKey();
      if (crypto == null) return null;
      return await _worker.open(
          crypto.encryptionKey, "$_dataPrefix$identifier", sealed);
    } catch (error) {
      Log.w("Couldn't open app data: $error");
      return null;
    }
  }

  @override
  Future<String?> dataNameOf(String identifier) async {
    try {
      return (await _cryptoKey())?.hashOf("$_dataPrefix$identifier");
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeFile(String identifier, Uint8List bytes,
      {bool sensitive = false}) async {
    try {
      if (sensitive) {
        // A write asked for during a forget (sign-out) belongs to what is
        // being forgotten: it is dropped, not sealed under the next key.
        if (_forgetting != null) return;
        await _writeSealed(identifier, bytes, _forgets);
      } else {
        await putFile(identifier, bytes);
      }
    } catch (error) {
      // A cache that can't be written is a cache miss next time, not an
      // error for the image or player that asked.
      Log.w("Couldn't cache media: $error");
    }
  }

  /// [startedAt] is [_forgets] when the write was asked for: a forget since
  /// then (it may have finished while this waited for the key) drops it.
  Future<void> _writeSealed(
      String identifier, Uint8List bytes, int startedAt) async {
    final keyed = await _cryptoKeyAt();
    // No usable key this run: sensitive media just isn't cached.
    if (keyed == null) return;
    final (:crypto, :generation) = keyed;
    if (_forgets != startedAt) return;
    final type = FileCache.sniffType(
        bytes.length > 16 ? Uint8List.sublistView(bytes, 0, 16) : bytes);

    final dir = await _ensureCacheDirectory();
    final path = p.join(dir, crypto.fileNameOf(identifier));
    final rowId = crypto.rowIdOf(identifier);
    // Written beside and renamed into place, so a reader never sees half a
    // file and two writers of one entry can't interleave.
    final temp = File("$path.${RandomUtils.getRandomString(8)}.tmp");
    try {
      if (bytes.length >= MediaCacheCrypto.ownIsolateBytes) {
        // Sealed straight into the file a chunk at a time.
        await MediaCacheWorker.sealToFile(
            crypto.encryptionKey, identifier, type.index, bytes, temp.path);
      } else {
        final sealed = await _worker.seal(
            crypto.encryptionKey, identifier, type.index, bytes);
        await temp.writeAsBytes(sealed, flush: true);
      }
      if (generation != _keyGeneration) {
        throw StateError("The media cache key was forgotten while sealing");
      }
      await temp.rename(path);
    } catch (error) {
      try {
        await temp.delete();
      } catch (_) {}
      rethrow;
    }

    final db = await get();
    await db.into(db.fileCacheEntry).insertOnConflictUpdate(
        FileCacheEntryCompanion.insert(
            id: rowId,
            path: path,
            lastAccessedTimestamp: DateTime.now().millisecondsSinceEpoch));

    if (generation != _keyGeneration) {
      // Signed out while sealing: this entry belongs to the forgotten key.
      await _forget(
          db,
          await _deleteEntries([
            FileCacheEntryData(id: rowId, path: path, lastAccessedTimestamp: 0)
          ]));
    }
  }

  /// The cache directory, made again (0700) if something deleted it while
  /// the app runs (Android clears app caches when storage runs low).
  Future<String> _ensureCacheDirectory() async {
    final dir = await cacheDirectory();
    if (!await Directory(dir).exists()) {
      await Directory(dir).create(recursive: true);
      await _ownerOnlyCacheDirectory(dir);
    }
    return dir;
  }

  /// Vommet: crypto-shreds first (the key file and the key check go before
  /// anything else, so whatever a failed delete leaves can't be opened),
  /// then wipes the sealed entries. Key loads wait until it is done, and one
  /// that overlapped it is thrown away, so no load can bring the old key
  /// back or leave a new key without its key check. Safe to run twice at
  /// once (sign-out and a remote sign-out): the second runs after the first.
  @override
  Future<void> forgetSensitive() {
    final previous = _forgetting ?? Future<void>.value();
    late final Future<void> run;
    // After the previous one however it ended: a forget that threw must
    // not keep the next one from running.
    run = previous
        .then<void>((_) {}, onError: (Object _) {})
        .then((_) => _forgetSensitive())
        .whenComplete(() {
      if (identical(_forgetting, run)) _forgetting = null;
    });
    _forgetting = run;
    return run;
  }

  Future<void> _forgetSensitive() async {
    _forgets++;
    _keyGeneration++;
    final pending = _crypto;
    _crypto = null;
    _keyStamp = null;
    // A load already running finishes first (it may still write a key and
    // a key check), so the deletes below come after it.
    try {
      await pending;
    } catch (_) {}

    await MediaCacheKeyFile(await keyPath()).delete();
    try {
      final check = File(p.join(await cacheDirectory(), keyCheckFileName));
      if (await check.exists()) await check.delete();
    } catch (error) {
      Log.w("Couldn't delete the media cache key check: $error");
    }

    try {
      await _wipeSealed();
    } catch (error) {
      Log.w("Couldn't delete all encrypted cache entries: $error");
    }
    Log.i("Forgot the encrypted media cache and its key");
  }

  /// Vommet: the file next to the sealed entries saying which key sealed
  /// them ([MediaCacheCrypto.keyCheck]).
  static const String keyCheckFileName = "e1.keycheck";

  /// The key of the sensitive entries, or null when sealing is disabled for
  /// this run (see [_sealingDisabled]).
  Future<MediaCacheCrypto?> _cryptoKey() async =>
      (await _cryptoKeyAt())?.crypto;

  /// [_cryptoKey] with the key generation it belongs to: a write compares
  /// it with [_keyGeneration] before and after it lands, so a forget that
  /// starts any time after the key was handed out still drops the write.
  Future<({MediaCacheCrypto crypto, int generation})?> _cryptoKeyAt() async {
    while (true) {
      final forgetting = _forgetting;
      if (forgetting != null) {
        try {
          await forgetting;
        } catch (_) {}
        continue;
      }
      if (_sealingDisabled) return null;
      final generation = _keyGeneration;
      if (_crypto != null && !await _keyFileUnchanged()) {
        if (generation != _keyGeneration || _forgetting != null) continue;
        Log.i("The media cache key changed on disk: loading it again");
        // Writes sealing under the old key drop what they wrote.
        _keyGeneration++;
        _crypto = null;
        _keyStamp = null;
        continue;
      }
      // The stat above may have let a forget start: no load may begin
      // during one (nothing awaits between this check and the load).
      if (generation != _keyGeneration || _forgetting != null) continue;
      final loading = _crypto ??= _loadKey().catchError((Object error) {
        _crypto = null;
        throw error;
      });
      final MediaCacheCrypto crypto;
      try {
        crypto = await loading;
      } on MediaCacheKeyUnreadable catch (error) {
        _sealingDisabled = true;
        Log.w("Not caching encrypted media this run: $error");
        return null;
      }
      // A forget started while this loaded: its result is the old key.
      if (generation != _keyGeneration || _forgetting != null) continue;
      // The cache directory turned out not to be owner-only while loading.
      if (_sealingDisabled) return null;
      return (crypto: crypto, generation: generation);
    }
  }

  /// Whether the key file still is the one [_crypto] was loaded from (a
  /// stat; another engine of the app may have deleted or replaced it).
  Future<bool> _keyFileUnchanged() async {
    final stamp = _keyStamp;
    if (stamp == null) return true;
    try {
      final stat = await FileStat.stat(await keyPath());
      return stat.type != FileSystemEntityType.notFound &&
          stat.modified == stamp.modified &&
          stat.size == stamp.size;
    } catch (_) {
      return false;
    }
  }

  Future<MediaCacheCrypto> _loadKey() async {
    final path = await keyPath();
    final keyFile = MediaCacheKeyFile(path);
    var key = await keyFile.read();
    if (key == null) {
      Log.i("Making a new media cache key");
      key = await keyFile.create();
    }
    final crypto = await MediaCacheCrypto.fromMasterKey(key);
    final stat = await FileStat.stat(path);
    _keyStamp = (modified: stat.modified, size: stat.size);

    // A different key (lost, replaced, rotated) can't open the old entries.
    final dir = await cacheDirectory();
    final check = File(p.join(dir, keyCheckFileName));
    String? stored;
    try {
      if (await check.exists()) stored = (await check.readAsString()).trim();
    } catch (_) {}
    if (stored != crypto.keyCheck) {
      if (stored != null)
        Log.w("The media cache key changed: wiping its entries");
      await _wipeSealed();
      await check.writeAsString(crypto.keyCheck, flush: true);
    }
    return crypto;
  }

  /// Deletes every sealed entry: tracked rows and their files, then any
  /// sealed file no row tracks.
  Future<void> _wipeSealed() async {
    final db = await get();
    final rows = await (db.select(db.fileCacheEntry)
          ..where((tbl) => tbl.id.like("${MediaCacheCrypto.rowIdPrefix}%")))
        .get();
    await _forget(db, await _deleteEntries(rows));

    final dir = Directory(await cacheDirectory());
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!p
          .basename(entity.path)
          .startsWith(MediaCacheCrypto.fileNamePrefix)) {
        continue;
      }
      await deleteCachedFile(dir.path, entity.path);
    }
  }

  static bool _isSealedRowId(String id) =>
      id.startsWith(MediaCacheCrypto.rowIdPrefix);

  void _touch(FileCacheEntryData entry) {
    get().then((db) {
      _ignoreFailure(db.into(db.fileCacheEntry).insertOnConflictUpdate(
          entry.copyWith(
              lastAccessedTimestamp: DateTime.now().millisecondsSinceEpoch)));
    }, onError: (Object error) {
      Log.w("File cache write skipped: $error");
    });
  }

  /// Vommet: fire-and-forget cache writes must not surface as uncaught
  /// errors when the database closes before they run.
  void _ignoreFailure(Future<Object?> write) {
    write.then((_) {}, onError: (Object error) {
      Log.w("File cache write skipped: $error");
    });
  }

  @override
  Future<void> init() async {
    final cacheDir = await cacheDirectory();
    Log.i("Cache: $cacheDir");

    final dir = p.join(await AppConfig.getDatabasePath(), "app");
    var directory = Directory(dir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File(p.join(dir, "app_data.db"));

    var connection = await DatabaseIsolate.connect(file.absolute.path);
    database = DriftFileCacheDatabase(connection);

    // Vommet: drift opens the database on its first query. The startup
    // clean-up used to be that query; now that it runs later, open it here
    // so the first open never lands after the app's data was torn down.
    await database!.customSelect("SELECT 1").get();
  }

  /// Vommet: the cache used to live in the temporary directory (/tmp on
  /// Linux, shared by every user of the machine). Its files are deleted and
  /// the rows that pointed there forgotten; media is fetched again into the
  /// new cache. Safe to run more than once. Never throws.
  @override
  Future<void> migrateLegacyCache() async {
    try {
      final db = await get();
      final dir = await cacheDirectory();
      final rows = await db.select(db.fileCacheEntry).get();
      final stale = [
        for (final row in rows)
          if (!FileCache.isCachePath(dir, row.path)) row.id
      ];
      await _forget(db, stale);
      if (stale.isNotEmpty) {
        Log.i("Forgot ${stale.length} cache rows outside the cache directory");
      }
    } catch (error) {
      Log.w("Couldn't forget the old cache rows: $error");
    }

    try {
      // Sealed writes interrupted between writing and renaming.
      final dir = Directory(await cacheDirectory());
      final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith(".tmp")) continue;
        try {
          if ((await entity.lastModified()).isBefore(cutoff)) {
            await deleteCachedFile(dir.path, entity.path);
          }
        } catch (_) {}
      }
    } catch (error) {
      Log.w("Couldn't sweep unfinished cache writes: $error");
    }

    try {
      await _deleteLegacyCache();
    } catch (error) {
      Log.w("Couldn't delete the old media cache: $error");
    }
  }

  /// Vommet: deletes the old cache (temp/chat.commet.app/file_cache), but
  /// only when it is plainly ours. The temporary directory is shared (/tmp
  /// on Linux), so anyone could have made "chat.commet.app" a link to, or a
  /// directory leading into, somebody's files. Every part of the path under
  /// the temporary directory must be a real directory (not a link), the path
  /// must resolve to itself, and on Linux each part must be owned by us (no
  /// owner check there, no delete). Anything else is left alone (its rows
  /// were already forgotten above).
  Future<void> _deleteLegacyCache() async {
    final temp = p.normalize(p.absolute(await temporaryDirectory()));
    final old = p.normalize(p.absolute(legacyCacheDirectory(temp)));
    final current = p.normalize(p.absolute(await cacheDirectory()));
    if (old == current ||
        p.isWithin(old, current) ||
        p.isWithin(current, old)) {
      return;
    }

    if (await FileSystemEntity.type(old, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }

    final parts = p.split(p.relative(old, from: temp));
    // On Linux the temporary directory is /tmp, shared by every user: without
    // an owner check, someone else's directory (or one swapped in between
    // the checks below and the delete) can't be told from ours, so nothing
    // is deleted. Elsewhere the temporary directory is per user or per app.
    int? uid;
    if (Platform.isLinux) {
      uid = OwnerOnly.currentUid();
      if (uid == null) {
        Log.w("Leaving the old media cache: can't check who owns it");
        return;
      }
    }
    var path = temp;
    for (final part in parts) {
      path = p.join(path, part);
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type != FileSystemEntityType.directory) {
        Log.w("Leaving the old media cache: part of its path isn't a "
            "directory ($type)");
        return;
      }
      if (uid != null && OwnerOnly.ownerOf(path) != uid) {
        Log.w("Leaving the old media cache: part of its path isn't ours");
        return;
      }
    }
    final resolved =
        await Directory(old).resolveSymbolicLinks().catchError((_) => "");
    final resolvedTemp = await Directory(temp).resolveSymbolicLinks();
    if (resolved != p.joinAll([resolvedTemp, ...parts])) {
      Log.w("Leaving the old media cache: it doesn't resolve to itself");
      return;
    }

    // Dart's recursive delete removes links inside, never what they point
    // at.
    await Directory(old).delete(recursive: true);
    Log.i("Deleted the old media cache in the temporary directory");
    final parent = Directory(p.dirname(old));
    if (parent.path != temp &&
        await FileSystemEntity.type(parent.path, followLinks: false) ==
            FileSystemEntityType.directory &&
        await parent.list().isEmpty) {
      await parent.delete();
    }
  }

  @override
  Future<Uri> putFile(String identifier, Uint8List bytes) async {
    if (_isSealedRowId(identifier)) {
      throw ArgumentError("Reserved cache identifier");
    }
    await _ensureCacheDirectory();
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

  /// Vommet: least recently opened entries go until the cache is at most
  /// [limit] bytes (the "Media cache limit" part of [clean]).
  Future<void> evictOverLimit(int limit) async =>
      _evictOverLimit(await get(), limit);

  Future<String>? _cacheDirectory;

  /// The media cache directory: every cached file is created directly in it,
  /// and clean-up and clearing never delete anything outside it.
  ///
  /// Vommet: "media_cache" in the app's own cache directory (per user:
  /// ~/.cache/<app id> on Linux, Library/Caches on Apple platforms, the
  /// local app data on Windows, the app's cache on Android), made 0700. It
  /// used to be in the temporary directory, which is /tmp on Linux.
  Future<String> cacheDirectory() {
    return _cacheDirectory ??= () async {
      final path = _cacheDirOverride ??
          p.join((await getApplicationCacheDirectory()).path, "media_cache");
      final dir = Directory(path);
      if (!await dir.exists()) await dir.create(recursive: true);
      await _ownerOnlyCacheDirectory(path);
      return path;
    }()
        .catchError((Object error) {
      _cacheDirectory = null;
      throw error;
    });
  }

  /// Vommet: 0700 on the cache directory, read back. If it didn't take, the
  /// sealed part is off for this run (its names and key check would sit
  /// where others can list or swap them); plain media is cached as before.
  Future<void> _ownerOnlyCacheDirectory(String path) async {
    await OwnerOnly.directory(path);
    if (await OwnerOnly.isOwnerOnly(path)) return;
    if (!_sealingDisabled) {
      Log.w("The media cache directory can't be made owner-only: not "
          "caching encrypted media this run");
    }
    _sealingDisabled = true;
  }

  /// Vommet: the temporary directory the cache used to be in.
  Future<String> temporaryDirectory() async =>
      _tempDirOverride ?? (await getTemporaryDirectory()).path;

  /// Vommet: where the cache used to be, for [migrateLegacyCache].
  static String legacyCacheDirectory(String temporaryDirectory) =>
      p.join(temporaryDirectory, "chat.commet.app", "file_cache");

  /// Vommet: the media cache key's file, next to the cache's index database.
  Future<String> keyPath() async =>
      _keyPathOverride ??
      p.join(await AppConfig.getDatabasePath(), "app", "media_cache.key");

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
