import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:commet/cache/drift_file_cache.dart';
import 'package:commet/cache/file_cache.dart';
import 'package:commet/client/components/push_notification/linux/linux_notifier.dart';
import 'package:commet/client/components/push_notification/modifiers/linux_notification_formatting.dart';
import 'package:commet/client/matrix/matrix_media_privacy.dart';
import 'package:commet/client/matrix/matrix_mxc_file_provider.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:commet/utils/private_files/sign_out_wipe.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:path/path.dart' as p;

// Vommet: the paths that hand encrypted-room media to the file cache, the
// notification daemon and sign-out: what is sealed, what never touches the
// cache, and what goes when a session ends.

class _FakeSdkClient extends Fake implements matrix.Client {}

/// A file cache that records every call; anything it doesn't expect fails.
class _RecordingCache extends Fake implements FileCache {
  final calls = <String>[];
  final Map<String, Uint8List> sealed = {};

  @override
  Future<Uint8List?> readFile(String identifier,
      {bool sensitive = false}) async {
    calls.add("readFile $identifier sensitive=$sensitive");
    return sensitive ? sealed[identifier] : null;
  }

  @override
  Future<bool> hasFile(String identifier, {bool sensitive = false}) async {
    calls.add("hasFile $identifier sensitive=$sensitive");
    return sensitive && sealed.containsKey(identifier);
  }

  @override
  Future<bool> openToFile(String identifier, String path,
      {bool sensitive = false}) async {
    calls.add("openToFile $identifier sensitive=$sensitive");
    final bytes = sensitive ? sealed[identifier] : null;
    if (bytes == null) return false;
    await File(path).writeAsBytes(bytes);
    return true;
  }

  /// Writes wait for this (a slow seal) when set.
  Completer<void>? holdWrites;

  /// Writes throw this when set.
  Object? failWrites;
  int writesDone = 0;

  @override
  Future<void> writeFile(String identifier, Uint8List bytes,
      {bool sensitive = false}) async {
    calls.add("writeFile $identifier sensitive=$sensitive");
    await holdWrites?.future;
    if (failWrites != null) throw failWrites!;
    writesDone++;
  }

  @override
  Future<Uri> putFile(String identifier, Uint8List bytes) async {
    calls.add("putFile $identifier");
    throw StateError("putFile");
  }

  @override
  Future<Uri?> getFile(String identifier) async {
    calls.add("getFile $identifier");
    return null;
  }

  @override
  Future<void> forgetSensitive() async => calls.add("forgetSensitive");
}

/// A provider whose file "downloads" without a homeserver.
class _DownloadingProvider extends MxcFileProvider {
  _DownloadingProvider(super.client, super.uri,
      {super.event, required this.bytes});

  final Uint8List bytes;

  @override
  Future<Uint8List?> getFileData() async => bytes;
}

matrix.Room _room({required bool encrypted}) {
  final room = matrix.Room(id: "!room:example.org", client: _FakeSdkClient());
  if (encrypted) {
    room.states[matrix.EventTypes.Encryption] = {
      "": matrix.Event.fromJson({
        "type": matrix.EventTypes.Encryption,
        "event_id": "\$enc",
        "sender": "@a:example.org",
        "origin_server_ts": 1700000000000,
        "state_key": "",
        "content": {"algorithm": "m.megolm.v1.aes-sha2"},
      }, room)
    };
  }
  return room;
}

matrix.Event _image(matrix.Room room,
    {bool encryptedFile = false, bool encryptedThumbnail = false}) {
  return matrix.Event.fromJson({
    "type": matrix.EventTypes.Message,
    "event_id": "\$image",
    "sender": "@a:example.org",
    "origin_server_ts": 1700000000000,
    "content": {
      "msgtype": "m.image",
      "body": "photo.png",
      if (encryptedFile)
        "file": {"url": "mxc://example.org/media", "v": "v2"}
      else
        "url": "mxc://example.org/media",
      "info": {
        if (encryptedThumbnail)
          "thumbnail_file": {"url": "mxc://example.org/thumb", "v": "v2"},
      },
    },
  }, room);
}

// A 1x1 PNG.
final Uint8List _png = base64Decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==");

void main() {
  late Directory root;
  FileCache? previousCache;

  setUp(() async {
    root = Directory(p.join(Directory.current.path, ".dart_tool",
        "vommet_media_paths_test", "${Random().nextInt(1 << 32)}"));
    await root.create(recursive: true);
    PrivateMediaFiles.directoryOverride = p.join(root.path, "media_open");
    previousCache = app.fileCache;
  });

  tearDown(() async {
    app.fileCache = previousCache;
    PrivateMediaFiles.directoryOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  group("which media is sealed", () {
    test("MatrixMediaPrivacy", () {
      final plainRoom = _room(encrypted: false);
      final e2eeRoom = _room(encrypted: true);
      expect(MatrixMediaPrivacy.isSensitive(null), isFalse);
      expect(MatrixMediaPrivacy.isSensitive(_image(plainRoom)), isFalse);
      expect(MatrixMediaPrivacy.isSensitive(_image(e2eeRoom)), isTrue);
      expect(
          MatrixMediaPrivacy.isSensitive(
              _image(plainRoom, encryptedFile: true)),
          isTrue);
      expect(
          MatrixMediaPrivacy.isSensitive(
              _image(plainRoom, encryptedThumbnail: true)),
          isTrue);
    });

    test("the providers of an encrypted room's media", () {
      final client = _FakeSdkClient();
      final uri = Uri.parse("mxc://example.org/media");
      final e2ee = _image(_room(encrypted: true), encryptedFile: true);
      final plain = _image(_room(encrypted: false));

      expect(MxcFileProvider(client, uri, event: e2ee).sensitive, isTrue);
      expect(MxcFileProvider(client, uri, event: plain).sensitive, isFalse);
      expect(MxcFileProvider(client, uri).sensitive, isFalse);

      expect(MatrixMxcImage(uri, client, matrixEvent: e2ee).sensitive, isTrue);
      expect(
          MatrixMxcImage(uri, client, matrixEvent: plain).sensitive, isFalse);
      // Emoji in an encrypted room's message: the caller says so.
      expect(MatrixMxcImage(uri, client, sensitive: true).sensitive, isTrue);
    });

    test("an encrypted room's thumbnail is read sealed", () async {
      final cache = _RecordingCache();
      app.fileCache = cache;
      final uri = Uri.parse("mxc://example.org/media");
      final id = MatrixMxcImage.getThumbnailIdentifier(uri);
      cache.sealed[id] = _png;

      final bytes = await MatrixMxcImage.loadMatrixThumbnail(_FakeSdkClient(),
          uri, _image(_room(encrypted: true), encryptedFile: true));
      expect(bytes, _png);
      expect(cache.calls, ["readFile $id sensitive=true"]);
    });

    test("an encrypted room's file is read and opened sealed", () async {
      final cache = _RecordingCache();
      app.fileCache = cache;
      final uri = Uri.parse("mxc://example.org/media");
      cache.sealed[uri.toString()] = _png;
      final provider = MxcFileProvider(_FakeSdkClient(), uri,
          event: _image(_room(encrypted: true), encryptedFile: true));

      expect(await provider.getFileData(), _png);
      final copy = await provider.resolve();
      expect(copy, isNotNull);
      expect(
          p.isWithin(PrivateMediaFiles.directoryOverride!, copy!.toFilePath()),
          isTrue);
      expect(p.extension(copy.toFilePath()), ".png");
      expect(await File.fromUri(copy).readAsBytes(), _png);
      if (!Platform.isWindows) {
        expect((await File.fromUri(copy).stat()).mode & 0x1FF, 0x180);
      }
      expect(cache.calls, [
        "readFile $uri sensitive=true",
        "openToFile $uri sensitive=true",
      ]);
      await PrivateMediaFiles.release(copy);
    });
  });

  group("a freshly downloaded encrypted file", () {
    final uri = Uri.parse("mxc://example.org/media");

    test("plays before it is sealed into the cache", () async {
      final cache = _RecordingCache()..holdWrites = Completer<void>();
      app.fileCache = cache;
      final provider = _DownloadingProvider(_FakeSdkClient(), uri,
          event: _image(_room(encrypted: true), encryptedFile: true),
          bytes: _png);

      // Returns while the seal is still held up.
      final copy = await provider.resolve();
      expect(copy, isNotNull);
      expect(await File.fromUri(copy!).readAsBytes(), _png);
      expect(cache.calls, [
        "openToFile $uri sensitive=true",
        "writeFile $uri sensitive=true",
      ]);
      expect(cache.writesDone, 0);

      cache.holdWrites!.complete();
      await provider.sealing;
      expect(cache.writesDone, 1);
      await PrivateMediaFiles.release(copy);
    });

    test("a seal that fails is only logged", () async {
      final cache = _RecordingCache()
        ..failWrites = const FileSystemException("disk full");
      app.fileCache = cache;
      final provider = _DownloadingProvider(_FakeSdkClient(), uri,
          event: _image(_room(encrypted: true), encryptedFile: true),
          bytes: _png);
      final copy = await provider.resolve();
      expect(await File.fromUri(copy!).readAsBytes(), _png);
      await provider.sealing;
      expect(cache.writesDone, 0);
      await PrivateMediaFiles.release(copy);
    });

    test("a sign-out during the seal leaves nothing sealed", () async {
      final db = DriftFileCacheDatabase(NativeDatabase.memory());
      final cacheDir = p.join(root.path, "media_cache");
      final keyPath = p.join(root.path, "key", "media_cache.key");
      final cache = DriftFileCache(
          cacheDir: cacheDir,
          keyPath: keyPath,
          tempDir: p.join(root.path, "t"));
      cache.database = db;
      app.fileCache = cache;
      try {
        // Big enough to be sealed a segment at a time in its own isolate.
        final big = Uint8List(3 * 1024 * 1024);
        for (var i = 0; i < big.length; i++) {
          big[i] = i * 31;
        }
        final provider = _DownloadingProvider(_FakeSdkClient(), uri,
            event: _image(_room(encrypted: true), encryptedFile: true),
            bytes: big);
        final copy = await provider.resolve();
        expect(provider.sealing, isNotNull);
        await cache.forgetSensitive();
        await provider.sealing;

        expect(await cache.hasFile(uri.toString(), sensitive: true), isFalse);
        expect(await db.select(db.fileCacheEntry).get(), isEmpty);
        final left = await Directory(cacheDir)
            .list()
            .where((e) => e is File && !e.path.endsWith(".keycheck"))
            .toList();
        expect(left, isEmpty);
        expect(await File.fromUri(copy!).length(), big.length);
        await PrivateMediaFiles.release(copy);
      } finally {
        cache.database = null;
        await db.close();
      }
    });

    test("a write asked for during a sign-out is dropped", () async {
      final db = DriftFileCacheDatabase(NativeDatabase.memory());
      final cache = DriftFileCache(
          cacheDir: p.join(root.path, "media_cache"),
          keyPath: p.join(root.path, "key", "media_cache.key"),
          tempDir: p.join(root.path, "t"));
      cache.database = db;
      try {
        await cache.writeFile("before", _png, sensitive: true);
        final forget = cache.forgetSensitive();
        await cache.writeFile("during", _png, sensitive: true);
        await forget;
        expect(await cache.readFile("during", sensitive: true), isNull);
        expect(await db.select(db.fileCacheEntry).get(), isEmpty);
        // After it, writes are cached again (under a new key).
        await cache.writeFile("after", _png, sensitive: true);
        expect(await cache.readFile("after", sensitive: true), _png);
      } finally {
        cache.database = null;
        await db.close();
      }
    });
  });

  group("notification images", () {
    testWidgets("go to private files, never the file cache", (tester) async {
      final cache = _RecordingCache();
      app.fileCache = cache;
      final uri = await tester.runAsync(() =>
          NotificationModifierLinuxFormatting()
              .prepareImageForInline(MemoryImage(_png), 100));
      expect(uri, isNotNull);
      final path = uri!.toFilePath();
      expect(p.isWithin(PrivateMediaFiles.directoryOverride!, path), isTrue);
      expect(cache.calls, isEmpty);
      await tester.runAsync(() async {
        final file = File(path);
        expect(await file.exists(), isTrue);
        if (!Platform.isWindows) {
          expect((await file.stat()).mode & 0x1FF, 0x180);
        }
        await PrivateMediaFiles.release(uri);
      });
    });

    test("the files a notification body points at are found", () {
      const body = 'hello <img src="file:///home/u/.cache/a/media_open/'
          'x1&amp;y.png"/> <img src="https://example.org/a.png"/>'
          '<img src="file:///b.png" alt="b"/>';
      expect(LinuxNotifier.bodyImageFiles(body).map((u) => u.toFilePath()), [
        "/home/u/.cache/a/media_open/x1&y.png",
        "/b.png",
      ]);
      expect(LinuxNotifier.bodyImageFiles("plain text"), isEmpty);
    });
  });

  group("sign-out", () {
    test("a session the server ended counts, one signed out here doesn't", () {
      bool ended(matrix.LoginState state,
              {bool had = true, bool loggingOut = false}) =>
          SignOutWipe.endedRemotely(state,
              hadSession: had, loggingOut: loggingOut);
      expect(ended(matrix.LoginState.loggedOut), isTrue);
      expect(ended(matrix.LoginState.loggedIn), isFalse);
      expect(ended(matrix.LoginState.loggedOut, had: false), isFalse);
      expect(ended(matrix.LoginState.loggedOut, loggingOut: true), isFalse);
    });

    test(
        "a remote sign-out wipes everything, once at a time, and again is "
        "harmless", () async {
      final db = DriftFileCacheDatabase(NativeDatabase.memory());
      final keyPath = p.join(root.path, "media_cache.key");
      final cache = DriftFileCache(
          cacheDir: p.join(root.path, "media_cache"),
          keyPath: keyPath,
          tempDir: p.join(root.path, "tmp"));
      cache.database = db;
      try {
        await cache.writeFile("mxc://example.org/x", _png, sensitive: true);
        expect(await File(keyPath).exists(), isTrue);

        final steps = <String>[];
        final wipe = SignOutWipe(
          deleteIndex: () async => steps.add("index"),
          cache: cache,
          clearTranscripts: () async {
            steps.add("transcripts");
            throw const FileSystemException("busy");
          },
          sweepCopies: () async => steps.add("copies"),
        );
        // The remote sign-out and then removing the account.
        final first = wipe.run();
        expect(identical(wipe.run(), first), isTrue);
        await first;
        expect(steps..sort(), ["copies", "index", "transcripts"]);
        expect(await File(keyPath).exists(), isFalse);
        expect(await cache.readFile("mxc://example.org/x", sensitive: true),
            isNull);

        steps.clear();
        await wipe.run();
        expect(steps..sort(), ["copies", "index", "transcripts"]);
      } finally {
        cache.database = null;
        await db.close();
      }
    });

    test("Android share and clipboard copies are swept", () async {
      final base = p.join(root.path, "android_cache");
      final share = File(p.join(base, "share_plus", "photo.png"));
      final oldClip = File(p.join(base, "clipboard", "image-1.png"));
      final newClip = File(p.join(base, "clipboard", "image-2.png"));
      final other = File(p.join(base, "other", "keep.png"));
      for (final f in [share, oldClip, newClip, other]) {
        await f.create(recursive: true);
      }
      await oldClip
          .setLastModified(DateTime.now().subtract(const Duration(hours: 1)));

      // Start-up: the share copies and an old copied image.
      expect(
          await PrivateMediaFiles.sweepAndroidCopies(cacheDirectory: base), 2);
      expect(await share.exists(), isFalse);
      expect(await oldClip.exists(), isFalse);
      expect(await newClip.exists(), isTrue);

      // Sign-out: everything.
      expect(
          await PrivateMediaFiles.sweepAndroidCopies(
              all: true, cacheDirectory: base),
          1);
      expect(await newClip.exists(), isFalse);
      expect(await other.exists(), isTrue);
    });
  });

  test("a private folder someone opened up is made owner-only again", () async {
    if (Platform.isWindows) return;
    final dir = PrivateMediaFiles.directoryOverride!;
    await Directory(dir).create(recursive: true);
    await Process.run("chmod", ["755", dir]);
    final uri = await PrivateMediaFiles.write(_png, extension: "png");
    expect((await Directory(dir).stat()).mode & 0x1FF, 0x1C0);
    expect((await File.fromUri(uri).stat()).mode & 0x1FF, 0x180);
    await PrivateMediaFiles.release(uri);
  });
}
