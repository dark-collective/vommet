import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:commet/cache/drift_file_cache.dart';
import 'package:commet/cache/file_cache.dart';
import 'package:commet/cache/media_cache_crypto.dart';
import 'package:commet/cache/media_cache_key.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:commet/utils/private_files/owner_only.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/test_key_vault.dart';

// Vommet: media from encrypted rooms is sealed in the file cache (never on
// disk in plaintext), the cache lives in the app's own cache directory
// instead of /tmp, and the copies players and the share sheet need are
// short-lived and private.

const String _id = "mxc://example.org/SecretMediaId123";

/// Bytes that look like a PNG (so the type byte says "images") with a
/// pattern a scan of the disk can look for.
Uint8List _media(int size, {int seed = 1}) {
  final random = Random(seed);
  final out = Uint8List(size);
  for (var i = 0; i < size; i++) {
    out[i] = random.nextInt(256);
  }
  out.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  return out;
}

bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// Every file under [root] (none when nothing made it).
Future<List<File>> _files(Directory root) async => [
      if (await root.exists())
        await for (final e in root.list(recursive: true, followLinks: false))
          if (e is File) e
    ];

void main() {
  late Directory root;
  late String cacheDir;
  late String keysDir;
  late String legacyKeyPath;
  late KeyVault vault;
  late String tempDir;
  late String legacyDir;
  late DriftFileCacheDatabase db;
  final caches = <DriftFileCache>[];

  DriftFileCache newCache({KeyVault? withVault}) {
    final cache = DriftFileCache(
        cacheDir: cacheDir,
        keySource: VaultMediaCacheKey(withVault ?? vault),
        legacyKeyPath: legacyKeyPath,
        tempDir: tempDir);
    cache.database = db;
    caches.add(cache);
    return cache;
  }

  setUp(() async {
    // Under the package's own .dart_tool, never the system temp directory.
    root = Directory(p.join(Directory.current.path, ".dart_tool",
        "vommet_media_cache_test", "${Random().nextInt(1 << 32)}"));
    await root.create(recursive: true);
    cacheDir = p.join(root.path, "cache", "media_cache");
    keysDir = p.join(root.path, "db", "keys");
    legacyKeyPath = p.join(root.path, "db", "app", "media_cache.key");
    vault = await testKeyVault(keysDir);
    tempDir = p.join(root.path, "tmp");
    await Directory(tempDir).create();
    legacyDir = DriftFileCache.legacyCacheDirectory(tempDir);
    db = DriftFileCacheDatabase(NativeDatabase.memory());
    PrivateMediaFiles.directoryOverride = p.join(root.path, "media_open");
  });

  tearDown(() async {
    for (final cache in caches) {
      cache.database = null;
      await cache.close();
    }
    caches.clear();
    await db.close();
    await vault.dispose();
    PrivateMediaFiles.directoryOverride = null;
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  test("sealed entries round-trip", () async {
    final cache = newCache();
    final small = _media(50 * 1024);
    final big = _media(2 * 1024 * 1024, seed: 2); // its own isolate
    await cache.writeFile(_id, small, sensitive: true);
    await cache.writeFile("$_id-big", big, sensitive: true);

    expect(await cache.hasFile(_id, sensitive: true), isTrue);
    expect(await cache.readFile(_id, sensitive: true), small);
    expect(await cache.readFile("$_id-big", sensitive: true), big);
    // A sealed entry is invisible to the plain lookups.
    expect(await cache.hasFile(_id), isFalse);
    expect(await cache.getFile(_id), isNull);
    expect(await cache.readFile(_id), isNull);
    expect(await cache.readFile("nope", sensitive: true), isNull);

    // Overwriting keeps one entry.
    final other = _media(1000, seed: 3);
    await cache.writeFile(_id, other, sensitive: true);
    expect(await cache.readFile(_id, sensitive: true), other);

    // The storage page still sees the type.
    final usage = await cache.usage();
    expect(usage[CachedMediaType.images]?.files, 2);
  });

  test("plain entries still round-trip, in the new directory", () async {
    final cache = newCache();
    final bytes = _media(4096);
    await cache.writeFile("mxc://example.org/plain", bytes);
    final uri = await cache.getFile("mxc://example.org/plain");
    expect(uri, isNotNull);
    expect(p.isWithin(cacheDir, uri!.toFilePath()), isTrue);
    expect(await File.fromUri(uri).readAsBytes(), bytes);
    expect(await cache.readFile("mxc://example.org/plain"), bytes);
    expect(() => cache.putFile("enc1:abc", bytes), throwsArgumentError);
  });

  test("media sealed for an encrypted room never reaches the disk in plaintext",
      () async {
    final cache = newCache();
    final small = _media(50 * 1024, seed: 7);
    final big = _media(3 * 1024 * 1024, seed: 8);
    await cache.writeFile(_id, small, sensitive: true);
    await cache.writeFile("$_id-big", big, sensitive: true);
    await cache.readFile(_id, sensitive: true);

    final files = await _files(root);
    expect(files, isNotEmpty);
    for (final file in files) {
      final bytes = await file.readAsBytes();
      for (final plain in [small, big]) {
        // Any 64 bytes from past the PNG header.
        for (final at in [100, plain.length ~/ 2, plain.length - 64]) {
          expect(_contains(bytes, plain.sublist(at, at + 64)), isFalse,
              reason: "${file.path} holds plaintext");
        }
      }
    }
  });

  test("file names and rows don't show the identifier", () async {
    final cache = newCache();
    await cache.writeFile(_id, _media(2000), sensitive: true);

    for (final file in await _files(Directory(cacheDir))) {
      final name = p.basename(file.path);
      expect(name.contains("SecretMediaId123"), isFalse);
      expect(name.contains("example.org"), isFalse);
    }
    final rows = await db.select(db.fileCacheEntry).get();
    expect(rows, hasLength(1));
    expect(rows.single.id.startsWith(MediaCacheCrypto.rowIdPrefix), isTrue);
    expect(rows.single.id.contains("SecretMediaId123"), isFalse);
    expect(rows.single.path.contains("SecretMediaId123"), isFalse);
    expect(p.basename(rows.single.path),
        startsWith(MediaCacheCrypto.fileNamePrefix));
  });

  test("a changed byte is a miss and the entry goes", () async {
    final cache = newCache();
    await cache.writeFile(_id, _media(5000), sensitive: true);
    final row = (await db.select(db.fileCacheEntry).get()).single;
    for (final at in [
      2,
      4,
      10,
      2000,
      MediaCacheCrypto.sealedLengthOf(5000) - 1
    ]) {
      await cache.writeFile(_id, _media(5000), sensitive: true);
      final bytes = await File(row.path).readAsBytes();
      bytes[at] ^= 0x01;
      await File(row.path).writeAsBytes(bytes);
      expect(await cache.readFile(_id, sensitive: true), isNull,
          reason: "byte $at");
      expect(await File(row.path).exists(), isFalse);
      expect(await cache.hasFile(_id, sensitive: true), isFalse);
    }

    // Cut short.
    await cache.writeFile(_id, _media(5000), sensitive: true);
    final bytes = await File(row.path).readAsBytes();
    await File(row.path).writeAsBytes(bytes.sublist(0, 20));
    expect(await cache.readFile(_id, sensitive: true), isNull);
  });

  test("swapped files are a miss, not the other entry's media", () async {
    final cache = newCache();
    await cache.writeFile("a", _media(3000, seed: 1), sensitive: true);
    await cache.writeFile("b", _media(3000, seed: 2), sensitive: true);
    final rows = await db.select(db.fileCacheEntry).get();
    final a = await File(rows[0].path).readAsBytes();
    final b = await File(rows[1].path).readAsBytes();
    await File(rows[0].path).writeAsBytes(b);
    await File(rows[1].path).writeAsBytes(a);

    expect(await cache.readFile("a", sensitive: true), isNull);
    expect(await cache.readFile("b", sensitive: true), isNull);
  });

  test("a new key (another engine signed out) wipes the old entries", () async {
    final first = newCache();
    await first.writeFile(_id, _media(3000), sensitive: true);
    await first.writeFile("plain", _media(3000));
    final sealedPath = (await db.select(db.fileCacheEntry).get())
        .firstWhere((r) => r.id.startsWith("enc1:"))
        .path;

    final other = await testKeyVault(keysDir);
    await other.rotateMediaKey();
    await other.dispose();
    final second = newCache();
    expect(await second.readFile(_id, sensitive: true), isNull);
    expect(await File(sealedPath).exists(), isFalse);
    expect(
        (await db.select(db.fileCacheEntry).get()).map((r) => r.id), ["plain"]);
    // The plain entry and the new key keep working.
    expect(await second.readFile("plain"), isNotNull);
    await second.writeFile(_id, _media(10), sensitive: true);
    expect(await second.readFile(_id, sensitive: true), _media(10));
  });

  test("the key file of older versions and what it sealed are deleted",
      () async {
    final first = newCache();
    await first.writeFile(_id, _media(3000), sensitive: true);
    // As an older version left it: its own key file, and entries sealed
    // with that key.
    await File(legacyKeyPath).create(recursive: true);
    await File(legacyKeyPath)
        .writeAsBytes([..."VMK1".codeUnits, ...List.filled(32, 7)]);
    await File(p.join(cacheDir, DriftFileCache.keyCheckFileName))
        .writeAsString("0123456789abcdef0123456789abcdef");

    final second = newCache();
    expect(await second.readFile(_id, sensitive: true), isNull);
    expect(await File(legacyKeyPath).exists(), isFalse);
    expect(
        (await _files(Directory(cacheDir)))
            .where((f) => p.basename(f.path).startsWith("e1_")),
        isEmpty);
    await second.writeFile(_id, _media(30), sensitive: true);
    expect(await second.readFile(_id, sensitive: true), _media(30));
  });

  test("the cache folder is owner-only", () async {
    if (Platform.isWindows) return;
    final cache = newCache();
    await cache.writeFile(_id, _media(10), sensitive: true);
    expect((await Directory(cacheDir).stat()).mode & 0x1FF, 0x1C0);
  });

  test("signing out makes a new key and deletes the sealed entries", () async {
    final cache = newCache();
    await cache.writeFile(_id, _media(3000), sensitive: true);
    await cache.writeFile("plain", _media(3000));
    final before = vault.mediaKeyStamp;

    await cache.forgetSensitive();
    expect(vault.mediaKeyStamp, isNot(before));
    expect(
        (await _files(Directory(cacheDir)))
            .map((f) => p.basename(f.path))
            .where((n) => n.startsWith("e1")),
        isEmpty);
    expect(
        (await db.select(db.fileCacheEntry).get()).map((r) => r.id), ["plain"]);
    expect(await cache.readFile(_id, sensitive: true), isNull);

    // The next sensitive write uses the new key.
    await cache.writeFile(_id, _media(20), sensitive: true);
    expect(await cache.readFile(_id, sensitive: true), _media(20));
  });

  test("the size limit evicts sealed entries too", () async {
    final cache = newCache();
    await cache.writeFile("old", _media(100 * 1024, seed: 1), sensitive: true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await cache.writeFile("new", _media(100 * 1024, seed: 2), sensitive: true);
    await cache.evictOverLimit(150 * 1024);
    expect(await cache.readFile("old", sensitive: true), isNull);
    expect(await cache.readFile("new", sensitive: true), isNotNull);

    await cache.clearAll(types: {CachedMediaType.images});
    expect(await cache.readFile("new", sensitive: true), isNull);
  });

  test("the old cache in /tmp is deleted and its rows forgotten", () async {
    await Directory(legacyDir).create(recursive: true);
    final oldFile = File(p.join(legacyDir, "abcdef"));
    await oldFile.writeAsBytes(_media(100));
    await db.into(db.fileCacheEntry).insert(FileCacheEntryCompanion.insert(
        id: "mxc://example.org/old",
        path: oldFile.path,
        lastAccessedTimestamp: 0));

    final cache = newCache();
    await cache.writeFile("plain", _media(100));
    // An unfinished sealed write from a crash, long ago.
    final stale = File(p.join(cacheDir, "e1_dead.abc.tmp"));
    await stale.writeAsBytes([1, 2, 3]);
    await stale
        .setLastModified(DateTime.now().subtract(const Duration(hours: 1)));

    await cache.migrateLegacyCache();
    expect(await Directory(legacyDir).exists(), isFalse);
    expect(await Directory(p.dirname(legacyDir)).exists(), isFalse);
    expect(await stale.exists(), isFalse);
    expect(
        (await db.select(db.fileCacheEntry).get()).map((r) => r.id), ["plain"]);
    expect(await cache.readFile("plain"), isNotNull);

    // Again (nothing left) is fine.
    await cache.migrateLegacyCache();
  });

  group("a legacy cache that isn't plainly ours is left alone", () {
    late Directory victim;
    late File keep;

    setUp(() async {
      victim = Directory(p.join(root.path, "victim"));
      await Directory(p.join(victim.path, "file_cache"))
          .create(recursive: true);
      keep = File(p.join(victim.path, "file_cache", "precious"));
      await keep.writeAsString("x");
    });

    test("the cache directory itself a link", () async {
      if (Platform.isWindows) return;
      await Directory(p.dirname(legacyDir)).create(recursive: true);
      await Link(legacyDir).create(p.join(victim.path, "file_cache"));

      await newCache().migrateLegacyCache();
      expect(await keep.exists(), isTrue);
    });

    test("its parent a link (chat.commet.app -> someone's directory)",
        () async {
      if (Platform.isWindows) return;
      await Link(p.dirname(legacyDir)).create(victim.path);
      expect(await File(p.join(legacyDir, "precious")).exists(), isTrue);

      await newCache().migrateLegacyCache();
      expect(await keep.exists(), isTrue);
      expect(
          await Directory(p.join(victim.path, "file_cache")).exists(), isTrue);
    });

    test("its parent someone else's", () async {
      // Needs root to give a directory away (CI containers run as root).
      if (!OwnerOnly.checksOwners || OwnerOnly.currentUid() != 0) return;
      await Directory(legacyDir).create(recursive: true);
      final file = File(p.join(legacyDir, "theirs"));
      await file.writeAsString("x");
      final chown = await Process.run("chown", ["65534", p.dirname(legacyDir)]);
      if (chown.exitCode != 0) return;
      expect(OwnerOnly.ownerOf(p.dirname(legacyDir)), 65534);

      await newCache().migrateLegacyCache();
      expect(await file.exists(), isTrue);
    });
  });

  group("the segmented format", () {
    final key = Uint8List.fromList(List.filled(32, 5));
    const seg = MediaCacheCrypto.sealedSegmentLength;
    const head = MediaCacheCrypto.headerLength;
    // Three full segments and a short fourth.
    final plain = _media(3 * MediaCacheCrypto.segmentLength + 1000);

    Uint8List segmentOf(Uint8List sealed, int index) {
      final start = head + index * seg;
      return Uint8List.sublistView(
          sealed, start, min(start + seg, sealed.length));
    }

    test("round-trips at every size around the segment edges", () async {
      for (final size in [
        0,
        1,
        MediaCacheCrypto.segmentLength - 1,
        MediaCacheCrypto.segmentLength,
        MediaCacheCrypto.segmentLength + 1,
        2 * MediaCacheCrypto.segmentLength,
      ]) {
        final media = _media(max(size, 8)).sublist(0, size);
        final sealed = await MediaCacheCrypto.seal(key, _id, 0, media);
        expect(sealed.length, MediaCacheCrypto.sealedLengthOf(size));
        expect(MediaCacheCrypto.plainLengthOf(sealed.length), size);
        expect(await MediaCacheCrypto.open(key, _id, sealed), media,
            reason: "$size bytes");
      }
    });

    test("cut short at a segment edge is a miss", () async {
      final sealed = await MediaCacheCrypto.seal(key, _id, 0, plain);
      for (final segments in [1, 2, 3]) {
        final cut = sealed.sublist(0, head + segments * seg);
        // The length alone looks fine: only the last-segment flag tells.
        expect(MediaCacheCrypto.plainLengthOf(cut.length), isNotNull);
        expect(await MediaCacheCrypto.open(key, _id, cut), isNull,
            reason: "$segments segments");
      }
      expect(await MediaCacheCrypto.open(key, _id, sealed.sublist(0, head)),
          isNull);
    });

    test("reordered segments are a miss", () async {
      final sealed = await MediaCacheCrypto.seal(key, _id, 0, plain);
      final swapped = Uint8List.fromList(sealed);
      swapped.setRange(head, head + seg, segmentOf(sealed, 1));
      swapped.setRange(head + seg, head + 2 * seg, segmentOf(sealed, 0));
      expect(await MediaCacheCrypto.open(key, _id, swapped), isNull);
    });

    test("extended files are a miss", () async {
      final sealed = await MediaCacheCrypto.seal(key, _id, 0, plain);
      // Another copy of a segment, or another file's last segment, added on.
      final again = Uint8List.fromList([...sealed, ...segmentOf(sealed, 3)]);
      expect(await MediaCacheCrypto.open(key, _id, again), isNull);
      final other = await MediaCacheCrypto.seal(key, _id, 0, plain);
      final spliced = Uint8List.fromList(
          [...sealed.sublist(0, head + 3 * seg), ...segmentOf(other, 3)]);
      expect(await MediaCacheCrypto.open(key, _id, spliced), isNull);
      // A segment sealed as the last one, with a full one after it.
      final short = await MediaCacheCrypto.seal(
          key, _id, 0, plain.sublist(0, MediaCacheCrypto.segmentLength));
      final grown = Uint8List.fromList([...short, ...segmentOf(sealed, 1)]);
      expect(await MediaCacheCrypto.open(key, _id, grown), isNull);
    });

    test("another identifier, key or a changed header is a miss", () async {
      final sealed = await MediaCacheCrypto.seal(key, _id, 0, plain);
      expect(await MediaCacheCrypto.open(key, "$_id-other", sealed), isNull);
      expect(
          await MediaCacheCrypto.open(
              Uint8List.fromList(List.filled(32, 6)), _id, sealed),
          isNull);
      for (final at in [4, 5, head - 1]) {
        final changed = Uint8List.fromList(sealed);
        changed[at] ^= 1;
        expect(await MediaCacheCrypto.open(key, _id, changed), isNull,
            reason: "header byte $at");
      }
    });

    test("opening reads and writes a segment at a time", () async {
      final sealed = await MediaCacheCrypto.seal(key, _id, 0, plain);
      var readAt = 0, biggestRead = 0, biggestWrite = 0, written = 0;
      final ok = await MediaCacheCrypto.openSegments(key, _id, sealed.length,
          (length) {
        biggestRead = max(biggestRead, length);
        final bytes = Uint8List.sublistView(sealed, readAt, readAt + length);
        readAt += length;
        return bytes;
      }, (chunk) {
        biggestWrite = max(biggestWrite, chunk.length);
        written += chunk.length;
      });
      expect(ok, isTrue);
      expect(written, plain.length);
      expect(biggestRead, seg);
      expect(biggestWrite, MediaCacheCrypto.segmentLength);
    });

    test("sealing hands out a segment at a time, whatever comes in", () async {
      final sealer = MediaCacheSealer(key, _id, 0);
      final out = BytesBuilder(copy: false)..add(sealer.header);
      // Fed 1 MiB, then a byte, then 100 KB.
      for (final piece in [
        _media(1024 * 1024),
        Uint8List(1),
        _media(100 * 1024, seed: 2)
      ]) {
        for (final segment in await sealer.add(piece)) {
          expect(segment.length, seg);
          out.add(segment);
        }
      }
      final last = await sealer.close();
      expect(last.length, lessThanOrEqualTo(seg));
      out.add(last);
      final opened = await MediaCacheCrypto.open(key, _id, out.takeBytes());
      expect(opened?.length, 1024 * 1024 + 1 + 100 * 1024);
    });

    test("big files are sealed and opened file to file", () async {
      final big = _media(5 * 1024 * 1024 + 123);
      final sealedPath = p.join(root.path, "big.sealed");
      final openedPath = p.join(root.path, "big.opened");
      await MediaCacheWorker.sealToFile(key, _id, 1, big, sealedPath);
      expect(await File(sealedPath).length(),
          MediaCacheCrypto.sealedLengthOf(big.length));
      expect(
          await MediaCacheCrypto.open(
              key, _id, await File(sealedPath).readAsBytes()),
          big);

      await File(openedPath).writeAsBytes(List.filled(10 << 20, 1));
      expect(
          await MediaCacheWorker.openToFile(key, _id, sealedPath, openedPath),
          isTrue);
      expect(await File(openedPath).readAsBytes(), big);
      expect(await MediaCacheWorker.openFileToBytes(key, _id, sealedPath), big);

      final bytes = await File(sealedPath).readAsBytes();
      await File(sealedPath).writeAsBytes(bytes.sublist(0, head + 40 * seg));
      expect(
          await MediaCacheWorker.openToFile(key, _id, sealedPath, openedPath),
          isFalse);
      expect(
          await MediaCacheWorker.openFileToBytes(key, _id, sealedPath), isNull);
    });
  });

  group("opening to a file and sealed app data", () {
    test("openToFile writes the media, plain or sealed", () async {
      final cache = newCache();
      final out = p.join(root.path, "out.bin");
      for (final size in [3000, 3 * 1024 * 1024]) {
        final media = _media(size, seed: size);
        await cache.writeFile("plain-$size", media);
        await cache.writeFile("$_id-$size", media, sensitive: true);
        expect(await cache.openToFile("plain-$size", out), isTrue);
        expect(await File(out).readAsBytes(), media);
        expect(
            await cache.openToFile("$_id-$size", out, sensitive: true), isTrue);
        expect(await File(out).readAsBytes(), media);
        expect(await cache.openToFile("$_id-$size", out), isFalse);
      }
      expect(await cache.openToFile("nope", out, sensitive: true), isFalse);
    });

    test("a big entry that doesn't open is dropped", () async {
      final cache = newCache();
      await cache.writeFile(_id, _media(2 * 1024 * 1024), sensitive: true);
      final row = (await db.select(db.fileCacheEntry).get()).single;
      final bytes = await File(row.path).readAsBytes();
      bytes[bytes.length - 3] ^= 1;
      await File(row.path).writeAsBytes(bytes);
      expect(
          await cache.openToFile(_id, p.join(root.path, "o"), sensitive: true),
          isFalse);
      expect(await File(row.path).exists(), isFalse);
      expect(await cache.hasFile(_id, sensitive: true), isFalse);
    });

    test("sealed app data round-trips under its own name", () async {
      final cache = newCache();
      final data = Uint8List.fromList(utf8.encode('{"text":"secret words"}'));
      final sealed = await cache.sealData("transcript:$_id", data);
      expect(sealed, isNotNull);
      expect(_contains(sealed!, utf8.encode("secret")), isFalse);
      expect(await cache.openData("transcript:$_id", sealed), data);
      expect(await cache.openData("transcript:other", sealed), isNull);
      // Media sealed for the same string can't stand in for it.
      expect(await cache.openData(_id, sealed), isNull);

      final name = await cache.dataNameOf("transcript:$_id");
      expect(name, isNotNull);
      expect(name!.contains("example"), isFalse);
      expect(name, isNot(await cache.dataNameOf("transcript:other")));

      await cache.forgetSensitive();
      expect(await cache.openData("transcript:$_id", sealed), isNull);
    });
  });

  group("the key", () {
    test(
        "forgetting while keys load never leaves the old key or a new key "
        "without its check", () async {
      for (var round = 0; round < 10; round++) {
        final cache = newCache();
        await cache.writeFile("$_id-$round", _media(500), sensitive: true);
        final oldStamp = vault.mediaKeyStamp;

        // Loads, writes and forgets all at once, from two engines.
        final other = newCache();
        await Future.wait([
          cache.readFile("$_id-$round", sensitive: true),
          other.hasFile("x", sensitive: true),
          cache.forgetSensitive(),
          cache.writeFile("$_id-a", _media(700, seed: round), sensitive: true),
          other.writeFile("$_id-b", _media(800, seed: round), sensitive: true),
          cache.forgetSensitive(),
          cache.writeFile("$_id-c", _media(900, seed: round), sensitive: true),
          cache.readFile("$_id-c", sensitive: true),
        ]);

        expect(await cache.readFile("$_id-$round", sensitive: true), isNull);
        final check = File(p.join(cacheDir, DriftFileCache.keyCheckFileName));
        expect(vault.mediaKeyStamp, isNot(oldStamp));
        if (await check.exists()) {
          final crypto =
              await MediaCacheCrypto.fromMasterKey(await vault.mediaKey());
          expect(await check.readAsString(), crypto.keyCheck);
        }
        // A fresh engine agrees with the one that wrote: same key, nothing
        // wiped.
        final fresh = newCache();
        expect(await fresh.readFile("$_id-c", sensitive: true),
            await cache.readFile("$_id-c", sensitive: true));
        await cache.forgetSensitive();
      }
    });

    test("a write sealing during a forget leaves nothing behind", () async {
      final cache = newCache();
      await cache.writeFile("first", _media(100), sensitive: true);
      final write =
          cache.writeFile(_id, _media(2 * 1024 * 1024), sensitive: true);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await cache.forgetSensitive();
      await write;
      // Whatever got written belongs to a key that is gone or new.
      final fresh = newCache();
      final rows = await db.select(db.fileCacheEntry).get();
      for (final row in rows) {
        expect(await File(row.path).exists(), isTrue);
      }
      expect(await fresh.readFile("first", sensitive: true), isNull);
    });

    test("a key vault that isn't ready turns sealed caching off", () async {
      final locked =
          await testKeyVault(p.join(root.path, "locked"), unlock: false);
      addTearDown(locked.dispose);
      final cache = newCache(withVault: locked);
      await cache.writeFile(_id, _media(3000), sensitive: true);
      expect(await cache.hasFile(_id, sensitive: true), isFalse);
      expect(await cache.readFile(_id, sensitive: true), isNull);
      expect(await cache.sealData("a", Uint8List(3)), isNull);
      expect(
          (await _files(Directory(cacheDir)))
              .where((f) => p.basename(f.path).startsWith("e1_")),
          isEmpty);
      // Plain media is unaffected.
      await cache.writeFile("plain", _media(10));
      expect(await cache.readFile("plain"), _media(10));
      await expectLater(VaultMediaCacheKey(locked).load(),
          throwsA(isA<MediaCacheKeyUnreadable>()));
    });

    test("another engine forgetting the key is noticed before writing",
        () async {
      final app = newCache();
      // Another engine: a vault of its own on the same keystore.json.
      final backgroundVault = await testKeyVault(keysDir, allowCreate: false);
      addTearDown(backgroundVault.dispose);
      final background = newCache(withVault: backgroundVault);
      await app.writeFile(_id, _media(3000), sensitive: true);
      expect(await background.readFile(_id, sensitive: true), _media(3000));

      // The app signs out; the background engine still has the key loaded.
      await app.forgetSensitive();
      await background.writeFile("$_id-late", _media(400), sensitive: true);
      expect(await background.readFile(_id, sensitive: true), isNull);

      // What it wrote is under the new key on disk, which the app uses too.
      expect(await app.readFile("$_id-late", sensitive: true), _media(400));
    });
  });

  test("sniffType reads a sealed entry's type", () {
    final head = [...MediaCacheCrypto.magic, CachedMediaType.videos.index];
    expect(FileCache.sniffType(head), CachedMediaType.videos);
    expect(FileCache.sniffType([...MediaCacheCrypto.magic, 200]),
        CachedMediaType.other);
    expect(MediaCacheCrypto.typeOf([1, 2]), isNull);
  });

  group("private copies for players and the share sheet", () {
    test("written owner-only and deleted on release", () async {
      final uri = await PrivateMediaFiles.write(_media(100), extension: "mp4");
      final file = File.fromUri(uri);
      expect(await file.readAsBytes(), _media(100));
      expect(p.extension(file.path), ".mp4");
      expect(
          p.isWithin(PrivateMediaFiles.directoryOverride!, file.path), isTrue);
      if (!Platform.isWindows) {
        expect((await file.stat()).mode & 0x1FF, 0x180);
        expect(
            (await Directory(PrivateMediaFiles.directoryOverride!).stat())
                    .mode &
                0x1FF,
            0x1C0);
      }
      await PrivateMediaFiles.release(uri);
      expect(await file.exists(), isFalse);
    });

    test("named copies for sharing go with their folder", () async {
      final file = await PrivateMediaFiles.writeNamed(_media(10), "photo.png");
      expect(p.basename(file.path), "photo.png");
      final folder = file.parent;
      await PrivateMediaFiles.release(file.uri);
      expect(await folder.exists(), isFalse);
      expect(await Directory(PrivateMediaFiles.directoryOverride!).exists(),
          isTrue);
    });

    test("release never touches files outside the private directory", () async {
      final outside = File(p.join(root.path, "user.mp4"));
      await outside.writeAsBytes([1]);
      await PrivateMediaFiles.release(outside.uri);
      expect(await outside.exists(), isTrue);
      await PrivateMediaFiles.release(null);
      await PrivateMediaFiles.release(Uri.parse("https://example.org/a"));
    });

    test("releaseAfter waits for the player", () async {
      final uri = await PrivateMediaFiles.write(_media(10));
      var disposed = false;
      final dispose = Future<void>.delayed(
          const Duration(milliseconds: 20), () => disposed = true);
      PrivateMediaFiles.releaseAfter(dispose, uri);
      expect(await File.fromUri(uri).exists(), isTrue);
      await dispose;
      expect(disposed, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await File.fromUri(uri).exists(), isFalse);
    });

    test("leftovers from a crash are swept at start-up", () async {
      final copy = File.fromUri(await PrivateMediaFiles.write(_media(10)));
      final share = await PrivateMediaFiles.writeNamed(_media(10), "a.png");
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await PrivateMediaFiles.sweep(olderThan: Duration.zero), 2);
      expect(await copy.exists(), isFalse);
      expect(await share.parent.exists(), isFalse);

      // The default leaves copies a player may still be opening.
      final fresh = File.fromUri(await PrivateMediaFiles.write(_media(10)));
      expect(await PrivateMediaFiles.sweep(), 0);
      expect(await fresh.exists(), isTrue);
    });

    test("unsafe extensions are dropped", () {
      expect(PrivateMediaFiles.safeExtension(".MP4"), "mp4");
      expect(PrivateMediaFiles.safeExtension("../x"), isNull);
      expect(PrivateMediaFiles.safeExtension("a/b"), isNull);
      expect(PrivateMediaFiles.safeExtension(""), isNull);
      expect(PrivateMediaFiles.safeExtension(null), isNull);
    });
  });

  test("benchmark: sealing and opening a thumbnail and a photo", () async {
    final crypto = await MediaCacheCrypto.fromMasterKey(List.filled(32, 9));
    final key = crypto.encryptionKey;
    final worker = MediaCacheWorker();
    try {
      for (final size in [50 * 1024, 5 * 1024 * 1024]) {
        final plain = _media(size);
        // Warm up.
        await MediaCacheCrypto.open(
            key, _id, await MediaCacheCrypto.seal(key, _id, 0, plain));

        final runs = size > 1024 * 1024 ? 3 : 20;
        var seal = 0, open = 0, sealWorker = 0, openWorker = 0;
        for (var i = 0; i < runs; i++) {
          var watch = Stopwatch()..start();
          final sealed = await MediaCacheCrypto.seal(key, _id, 0, plain);
          seal += watch.elapsedMicroseconds;
          watch = Stopwatch()..start();
          final opened = await MediaCacheCrypto.open(key, _id, sealed);
          open += watch.elapsedMicroseconds;
          expect(opened, plain);

          watch = Stopwatch()..start();
          final sealed2 = await worker.seal(key, _id, 0, plain);
          sealWorker += watch.elapsedMicroseconds;
          watch = Stopwatch()..start();
          final opened2 = await worker.open(key, _id, sealed2);
          openWorker += watch.elapsedMicroseconds;
          expect(opened2, plain);
        }
        String ms(int us) => (us / runs / 1000).toStringAsFixed(2);
        // ignore: avoid_print
        print("MEDIA-CACHE-BENCH ${size ~/ 1024} KB: seal ${ms(seal)} ms, "
            "open ${ms(open)} ms (inline); seal ${ms(sealWorker)} ms, "
            "open ${ms(openWorker)} ms (off the UI isolate, incl. transfer)");
      }
    } finally {
      worker.close();
    }
  });

  test("benchmark: a big video, streamed file to file", () async {
    final crypto = await MediaCacheCrypto.fromMasterKey(List.filled(32, 9));
    final key = crypto.encryptionKey;
    const size = 50 * 1024 * 1024;
    final plain = _media(size);
    final sealedPath = p.join(root.path, "big.sealed");
    final openedPath = p.join(root.path, "big.opened");
    await File(openedPath).create();
    final rssBefore = ProcessInfo.currentRss;

    var watch = Stopwatch()..start();
    await MediaCacheWorker.sealToFile(key, _id, 1, plain, sealedPath);
    final seal = watch.elapsedMilliseconds;
    watch = Stopwatch()..start();
    expect(await MediaCacheWorker.openToFile(key, _id, sealedPath, openedPath),
        isTrue);
    final open = watch.elapsedMilliseconds;
    watch = Stopwatch()..start();
    final bytes = await MediaCacheWorker.openFileToBytes(key, _id, sealedPath);
    final openBytes = watch.elapsedMilliseconds;
    expect(bytes?.length, size);
    expect(await File(openedPath).length(), size);
    // ignore: avoid_print
    print("MEDIA-CACHE-BENCH ${size ~/ (1024 * 1024)} MB: sealToFile $seal ms, "
        "openToFile $open ms, openFileToBytes $openBytes ms; RSS "
        "${rssBefore ~/ (1 << 20)} -> ${ProcessInfo.currentRss ~/ (1 << 20)} "
        "MB, max ${ProcessInfo.maxRss ~/ (1 << 20)} MB");
  });
}
