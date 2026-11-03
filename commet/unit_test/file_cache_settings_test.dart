import 'dart:io';

import 'package:commet/cache/drift_file_cache.dart';
import 'package:commet/cache/file_cache.dart';
import 'package:commet/ui/pages/settings/categories/app/data_storage_settings_page.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Vommet issue 75: "Keep media for", the cache size shown in settings, and
  // clearing that can never delete anything outside the media cache.
  test('retention', () {
    expect(FileCache.retention(5), const Duration(days: 5));
    expect(FileCache.retention(0.5), const Duration(hours: 12));
    expect(FileCache.retention(0), isNull);
    expect(FileCache.retention(-1), isNull);
  });

  test('sizes', () {
    expect(FileCache.formatSize(0), "0 B");
    expect(FileCache.formatSize(1023), "1023 B");
    expect(FileCache.formatSize(1536), "1.5 KB");
    expect(FileCache.formatSize(5 * 1024 * 1024), "5.0 MB");
    expect(FileCache.formatSize(250 * 1024 * 1024), "250 MB");
    expect(FileCache.formatSize(3 * 1024 * 1024 * 1024), "3.0 GB");
  });

  test('size limit', () {
    expect(FileCache.sizeLimit(0), isNull);
    expect(FileCache.sizeLimit(1024), 1024 * 1024 * 1024);
  });

  test('slider steps snap to the nearest choice', () {
    const keep = StorageUsagePage.keepDaysSteps;
    expect(keep[StorageUsagePage.nearestStep(keep, 5)], 5);
    expect(keep[StorageUsagePage.nearestStep(keep, 0)], 0);
    expect(keep[StorageUsagePage.nearestStep(keep, 0.5)], 1);
    expect(keep[StorageUsagePage.nearestStep(keep, 400)], 30);
    const limit = StorageUsagePage.limitMbSteps;
    expect(limit[StorageUsagePage.nearestStep(limit, 0)], 0);
    expect(limit[StorageUsagePage.nearestStep(limit, 1000)], 1024);
  });

  test('types from the first bytes', () {
    List<int> ascii(String s) => s.codeUnits;
    List<int> ftyp(String brand) => [0, 0, 0, 0x18, ...ascii("ftyp$brand")];
    expect(FileCache.sniffType(ascii("GIF89a")), CachedMediaType.gifs);
    expect(FileCache.sniffType([0x89, 0x50, 0x4E, 0x47, 0x0D]),
        CachedMediaType.images);
    expect(
        FileCache.sniffType([0xFF, 0xD8, 0xFF, 0xE0]), CachedMediaType.images);
    expect(FileCache.sniffType(ascii("RIFF\x00\x00\x00\x00WEBPVP8 ")),
        CachedMediaType.images);
    expect(FileCache.sniffType(ftyp("avif")), CachedMediaType.images);
    expect(FileCache.sniffType(ftyp("isom")), CachedMediaType.videos);
    expect(FileCache.sniffType(ftyp("qt  ")), CachedMediaType.videos);
    expect(FileCache.sniffType(ftyp("M4A ")), CachedMediaType.other);
    expect(
        FileCache.sniffType([0x1A, 0x45, 0xDF, 0xA3]), CachedMediaType.videos);
    expect(FileCache.sniffType(ascii("OggS")), CachedMediaType.other);
    expect(FileCache.sniffType(ascii("%PDF-1.7")), CachedMediaType.files);
    expect(FileCache.sniffType([]), CachedMediaType.other);
  });

  test('isCachePath only accepts paths strictly inside the cache', () {
    const dir = "/tmp/app/file_cache";
    expect(FileCache.isCachePath(dir, "/tmp/app/file_cache/abc"), isTrue);
    expect(FileCache.isCachePath(dir, "/tmp/app/file_cache/"), isFalse);
    expect(FileCache.isCachePath(dir, "/tmp/app/file_cache"), isFalse);
    expect(FileCache.isCachePath(dir, "/tmp/app/file_cache_x/abc"), isFalse);
    expect(FileCache.isCachePath(dir, "/tmp/app/file_cache/../app_data.db"),
        isFalse);
    expect(FileCache.isCachePath(dir, "/home/user/Downloads/a.png"), isFalse);
  });

  group('deleting cached files', () {
    late Directory root;
    late String cacheDir;
    late File outside;

    setUp(() async {
      root = await Directory.systemTemp.createTemp("vommet_cache_test");
      cacheDir = p.join(root.path, "file_cache");
      await Directory(cacheDir).create();
      outside = File(p.join(root.path, "app_data.db"));
      await outside.writeAsString("keep me");
    });

    tearDown(() => root.delete(recursive: true));

    test('deletes a file inside the cache', () async {
      final f = File(p.join(cacheDir, "abc"));
      await f.writeAsString("x");
      expect(await DriftFileCache.deleteCachedFile(cacheDir, f.path), isTrue);
      expect(await f.exists(), isFalse);
    });

    test('a missing file can be forgotten', () async {
      expect(
          await DriftFileCache.deleteCachedFile(
              cacheDir, p.join(cacheDir, "gone")),
          isTrue);
    });

    test('never deletes outside the cache', () async {
      expect(await DriftFileCache.deleteCachedFile(cacheDir, outside.path),
          isTrue);
      expect(
          await DriftFileCache.deleteCachedFile(
              cacheDir, p.join(cacheDir, "..", "app_data.db")),
          isTrue);
      final sibling = Directory("${cacheDir}_x");
      await sibling.create();
      final s = File(p.join(sibling.path, "abc"));
      await s.writeAsString("x");
      await DriftFileCache.deleteCachedFile(cacheDir, s.path);

      expect(await outside.exists(), isTrue);
      expect(await s.exists(), isTrue);
    });

    test('never follows a link out of the cache', () async {
      final link = Link(p.join(cacheDir, "link"));
      await link.create(outside.path);
      await DriftFileCache.deleteCachedFile(cacheDir, link.path);
      expect(await outside.exists(), isTrue);

      final dirLink = Link(p.join(cacheDir, "up"));
      await dirLink.create(root.path);
      await DriftFileCache.deleteCachedFile(
          cacheDir, p.join(dirLink.path, "app_data.db"));
      expect(await outside.exists(), isTrue);
    }, testOn: "!windows");

    test('sweep only removes the chosen types', () async {
      final gif = File(p.join(cacheDir, "a"));
      final png = File(p.join(cacheDir, "b"));
      await gif.writeAsString("GIF89a....");
      await png.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
      final past = DateTime.now().subtract(const Duration(hours: 1));
      await gif.setLastModified(past);
      await png.setLastModified(past);

      final swept = await DriftFileCache.sweepUntracked(
          cacheDir, {}, DateTime.now(),
          types: {CachedMediaType.gifs});

      expect(swept, 1);
      expect(await gif.exists(), isFalse);
      expect(await png.exists(), isTrue);
    });

    test('sweep removes old untracked files only', () async {
      final tracked = File(p.join(cacheDir, "tracked"));
      final old = File(p.join(cacheDir, "old"));
      final fresh = File(p.join(cacheDir, "fresh"));
      for (final f in [tracked, old, fresh]) {
        await f.writeAsString("x");
      }
      final past = DateTime.now().subtract(const Duration(hours: 1));
      await tracked.setLastModified(past);
      await old.setLastModified(past);
      await Link(p.join(cacheDir, "link")).create(outside.path);

      final swept = await DriftFileCache.sweepUntracked(cacheDir,
          {tracked.path}, DateTime.now().subtract(const Duration(minutes: 1)));

      expect(swept, 1);
      expect(await old.exists(), isFalse);
      expect(await tracked.exists(), isTrue);
      expect(await fresh.exists(), isTrue);
      expect(await outside.exists(), isTrue);
    });
  });
}
