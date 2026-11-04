// Vommet issue 1035: thumbnails took minutes and voice messages waited for no
// good reason. A picture in the open room queued behind every avatar asked
// for before it, media the server can't get holds a slot for up to ~20 s
// (Vommet issue 584), originals had no line of their own, and every media url
// waited for the sync being saved.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/cache/file_cache.dart';
import 'package:commet/client/matrix/matrix_media_failures.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_sdk_client.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

const _roomId = "!media:example.com";

// 1x1 PNG
final _png = base64Decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==");

class _MemoryCache implements FileCache {
  final files = <String, Uint8List>{};

  @override
  Future<Uint8List?> readFile(String identifier,
          {bool sensitive = false}) async =>
      files[identifier];

  @override
  Future<void> writeFile(String identifier, Uint8List bytes,
          {bool sensitive = false}) async =>
      files[identifier] = bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {"content-type": "application/json"});

http.Response _bytes(List<int> body) => http.Response.bytes(body, 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Client client;
  late Room room;
  late _MemoryCache cache;

  /// Media requests the server got, by media id.
  late List<String> asked;

  /// Answers media requests; ids that aren't handled get a picture.
  late Future<http.Response> Function(String id)? answer;

  var clients = 0;

  setUp(() async {
    asked = [];
    answer = null;
    cache = _MemoryCache();
    fileCache = cache;
    MatrixMediaFailures.instance.clear();
    final server = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith("/versions")) {
        return _json({
          "versions": ["v1.11"]
        });
      }
      if (!path.contains("/media/")) return _json({});
      final id = path.split("/").last;
      asked.add(id);
      return await answer?.call(id) ?? _bytes(_png);
    });
    final name = "media-speed-${clients++}";
    client = MatrixSdkClient(name,
        database:
            await MatrixSdkDriftDatabase.init(NativeDatabase.memory(), name),
        httpClient: server);
    await client.init(
      newToken: "token",
      newHomeserver: Uri.parse("https://example.com"),
      newUserID: "@me:example.com",
      newDeviceID: "DEVICE",
      newDeviceName: "test",
      waitForFirstSync: false,
    );
    await client.abortSync();
    await client.handleSync(SyncUpdate(
        nextBatch: "b0",
        rooms: RoomsUpdate(join: {_roomId: JoinedRoomUpdate()})));
    room = client.getRoomById(_roomId)!;
  });

  tearDown(() async {
    fileCache = null;
    await client.dispose(closeDatabase: true);
  });

  Event picture(int i) => Event(
          type: "m.room.message",
          eventId: "\$picture$i",
          senderId: "@alice:example.com",
          originServerTs: DateTime(2026, 11),
          room: room,
          content: {
            "msgtype": "m.image",
            "body": "picture.png",
            "url": "mxc://example.com/original$i",
            "info": {
              "mimetype": "image/png",
              "thumbnail_url": "mxc://example.com/thumbnail$i",
              "thumbnail_info": {"mimetype": "image/png"},
            },
          });

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  group("the thumbnail line", () {
    test("a picture in the room doesn't wait for avatars that hang", () async {
      final hang = Completer<http.Response>();
      answer = (id) async {
        if (id.startsWith("avatar")) return hang.future;
        return _bytes(_png);
      };

      final avatars = [
        for (var i = 0; i < 40; i++)
          MatrixMxcImage.loadMatrixThumbnail(
              client, Uri.parse("mxc://example.com/avatar$i"), null)
      ];
      await settle();

      final event = picture(0);
      final bytes = await MatrixMxcImage.loadMatrixThumbnail(
              client, event.thumbnailMxcUrl!, event)
          .timeout(const Duration(seconds: 2));
      expect(bytes, isNotNull);
      expect(asked, contains("thumbnail0"));

      hang.complete(_bytes(_png));
      await Future.wait(avatars);
    });

    test("avatars asked for last go first: they are the ones on screen",
        () async {
      final hang = Completer<http.Response>();
      answer = (id) async => id == "blocker" ? hang.future : _bytes(_png);
      final limiter = MatrixMxcImage.thumbnailRequestsOf(client);
      limiter.maxConcurrent = 2;
      addTearDown(
          () => limiter.maxConcurrent = MatrixMxcImage.maxThumbnailRequests);

      final blocker = MatrixMxcImage.loadMatrixThumbnail(
          client, Uri.parse("mxc://example.com/blocker"), null);
      await settle();
      final avatars = [
        for (final id in ["older", "newer"])
          MatrixMxcImage.loadMatrixThumbnail(
              client, Uri.parse("mxc://example.com/$id"), null)
      ];
      await settle();

      hang.complete(_bytes(_png));
      await Future.wait([blocker, ...avatars]);
      expect(asked.indexOf("newer"), lessThan(asked.indexOf("older")));
    });

    test("a banner or profile picture someone opened goes before avatars",
        () async {
      final hang = Completer<http.Response>();
      answer = (id) async {
        if (id.startsWith("avatar")) return hang.future;
        return _bytes(_png);
      };
      final avatars = [
        for (var i = 0; i < 40; i++)
          MatrixMxcImage.loadMatrixThumbnail(
              client, Uri.parse("mxc://example.com/avatar$i"), null)
      ];
      await settle();

      await MatrixMxcImage.loadMatrixThumbnail(
              client, Uri.parse("mxc://example.com/banner"), null,
              scaled: true)
          .timeout(const Duration(seconds: 2));

      hang.complete(_bytes(_png));
      await Future.wait(avatars);
    });

    test("a slot is given up before media the server can't get answers", () {
      // Vommet issue 584: such failures take the server up to ~20 s.
      expect(MatrixMxcImage.thumbnailSlotAtMost,
          lessThan(const Duration(seconds: 20)));
    });
  });

  group("an error answer to an event's thumbnail", () {
    test("isn't cached as the thumbnail and is remembered as a failure",
        () async {
      answer = (_) async =>
          _json({"errcode": "M_NOT_FOUND", "error": "Not found"}, status: 404);
      final event = picture(0);

      await expectLater(
          MatrixMxcImage.loadMatrixThumbnail(
              client, event.thumbnailMxcUrl!, event),
          throwsA(isA<MatrixException>()
              .having((e) => e.errcode, "errcode", "M_NOT_FOUND")));
      await settle();
      expect(cache.files, isEmpty);
      expect(asked, hasLength(1));

      // Vommet issue 584: not asked for again.
      await expectLater(
          MatrixMxcImage.loadMatrixThumbnail(
              client, event.thumbnailMxcUrl!, event),
          throwsA(isA<MatrixException>()));
      expect(asked, hasLength(1));
    });

    test("a proxy's error page isn't cached and isn't remembered", () async {
      answer = (_) async => http.Response("<html>Bad gateway</html>", 502);
      final event = picture(0);

      await expectLater(
          MatrixMxcImage.loadMatrixThumbnail(
              client, event.thumbnailMxcUrl!, event),
          throwsA(isNot(isA<MatrixException>())));
      await settle();
      expect(cache.files, isEmpty);

      answer = null;
      expect(
          await MatrixMxcImage.loadMatrixThumbnail(
              client, event.thumbnailMxcUrl!, event),
          isNotNull);
    });
  });

  group("the line of originals", () {
    Future<Uint8List?> original(int i) {
      final event = picture(i);
      return MatrixMxcImage.loadMatrixFullRes(
          client, event.attachmentMxcUrl!, event);
    }

    test("a few download at once", () async {
      final release = Completer<void>();
      var running = 0;
      var most = 0;
      answer = (_) async {
        most = running + 1 > most ? running + 1 : most;
        running++;
        await release.future;
        running--;
        return _bytes(_png);
      };

      final all = [for (var i = 0; i < 20; i++) original(i)];
      await settle();
      expect(most, MatrixMxcImage.maxFullResRequests);

      release.complete();
      await Future.wait(all);
      expect(asked, hasLength(20));
    });

    test("a picture showing nothing goes before sharpening others", () async {
      final release = Completer<void>();
      answer = (_) async {
        await release.future;
        return _bytes(_png);
      };

      final sharpen = RequestLimiter.runInBackground(() => [
            for (var i = 0; i < 10; i++) original(i),
          ]);
      await settle();
      expect(asked, hasLength(MatrixMxcImage.maxFullResRequests - 1),
          reason: "sharpening leaves a slot free");

      final needed = original(99);
      await settle();
      expect(asked, contains("original99"));

      release.complete();
      await Future.wait([needed, ...sharpen]);
    });

    test("isn't downloaded when it was fetched while waiting", () async {
      final release = Completer<void>();
      answer = (_) async {
        await release.future;
        return _bytes(_png);
      };
      final first = [
        for (var i = 0; i < MatrixMxcImage.maxFullResRequests; i++) original(i)
      ];
      await settle();

      final waiting = original(99);
      await settle();
      final fetched = Uint8List.fromList([1, 2, 3]);
      cache.files[MatrixMxcImage.getIdentifier(picture(99).attachmentMxcUrl!)] =
          fetched;

      release.complete();
      expect(await waiting, fetched);
      await Future.wait(first);
      expect(asked, isNot(contains("original99")));
    });

    test("an error answer isn't cached as the picture", () async {
      answer = (_) async =>
          _json({"errcode": "M_NOT_FOUND", "error": "Not found"}, status: 404);
      await expectLater(original(0), throwsA(isA<MatrixException>()));
      await settle();
      expect(cache.files, isEmpty);

      await expectLater(original(0), throwsA(isA<MatrixException>()));
      expect(asked, hasLength(1), reason: "remembered as a failure");
    });

    test("media without an event isn't in this line", () async {
      final limiter = MatrixMxcImage.fullResRequestsOf(client);
      await MatrixMxcImage.loadMatrixFullRes(
          client, Uri.parse("mxc://example.com/emoji"), null);
      expect(limiter.takeStats().waited, 0);
      expect(limiter.running, 0);
      expect(asked, ["emoji"]);
    });
  });

  group("sharpening", () {
    Future<ImageInfo?> shown(LODImageCompleter completer) {
      final done = Completer<ImageInfo?>();
      completer.addListener(ImageStreamListener((image, _) {
        if (!done.isCompleted) done.complete(image);
      }));
      return done.future;
    }

    LODImageCompleter picture(
            {required void Function(RequestPriority) onFullRes,
            bool tooSmall = true}) =>
        LODImageCompleter(
          callback: (buffer, {getTargetSize}) {
            getTargetSize?.call(1, 1);
            return PaintingBinding.instance
                .instantiateImageCodecWithSize(buffer);
          },
          autoLoadFullres: false,
          thumbnailTooSmall: (_, __) => tooSmall,
          loadThumbnail: () async => Uint8List.fromList(_png),
          loadFullRes: () async {
            onFullRes(RequestLimiter.currentPriority);
            return Uint8List.fromList(_png);
          },
        );

    test("a thumbnail too small waits behind pictures showing nothing",
        () async {
      RequestPriority? priority;
      await shown(picture(onFullRes: (p) => priority = p));
      await settle();
      expect(priority, RequestPriority.background);
    });

    test("asking for the full image doesn't", () async {
      RequestPriority? priority;
      final completer =
          picture(onFullRes: (p) => priority = p, tooSmall: false);
      await shown(completer);
      await settle();
      expect(priority, isNull);

      await completer.fetchFullRes();
      expect(priority, RequestPriority.foreground);
    });
  });

  group("a media url", () {
    test("doesn't wait for the sync being saved", () async {
      await client.authenticatedMediaSupported();

      final saved = Completer<void>();
      final saving = client.database.transaction(() => saved.future);
      await settle();

      final url = await Uri.parse("mxc://example.com/voice")
          .getDownloadUri(client)
          .timeout(const Duration(seconds: 2));
      expect(url.path, contains("/_matrix/client/v1/media/download/"));

      saved.complete();
      await saving;
    });

    test("a failed read isn't kept", () async {
      final failing = _FlakyVersionsClient(
          database: await MatrixSdkDriftDatabase.init(
              NativeDatabase.memory(), "media-speed-flaky"));
      addTearDown(() => failing.dispose(closeDatabase: true));
      await failing.init(
        newToken: "token",
        newHomeserver: Uri.parse("https://example.com"),
        newUserID: "@me:example.com",
        newDeviceID: "DEVICE",
        newDeviceName: "test",
        waitForFirstSync: false,
      );
      await failing.abortSync();

      failing.fail = true;
      await expectLater(failing.authenticatedMediaSupported(), throwsException);

      failing.fail = false;
      expect(await failing.authenticatedMediaSupported(), isTrue);
    });
  });
}

class _FlakyVersionsClient extends MatrixSdkClient {
  _FlakyVersionsClient({required DatabaseApi database})
      : super("media-speed-flaky", database: database,
            httpClient: MockClient((request) async {
          if (request.url.path.endsWith("/versions")) {
            return _json({
              "versions": ["v1.11"]
            });
          }
          return _json({});
        }));

  bool fail = false;

  @override
  Future<GetVersionsResponse> getVersions({
    Duration cacheLifetime = const Duration(days: 3),
    bool throwOnUpdateFailure = false,
  }) async {
    if (fail) throw Exception("no network");
    return super.getVersions(
        cacheLifetime: cacheLifetime,
        throwOnUpdateFailure: throwOnUpdateFailure);
  }
}
