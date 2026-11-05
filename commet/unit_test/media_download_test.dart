// Vommet issue 1065: voice and video messages took minutes to load. Media
// was asked for with dart:io's default `Accept-Encoding: gzip`, which some
// homeservers' proxies answer by compressing it on the fly, without a
// Content-Length; such a chunked answer was then gathered a byte at a time
// into a growable List<int>.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/cache/media_download.dart';
import 'package:commet/client/matrix/matrix_mxc_file_provider.dart';
import 'package:commet/client/matrix/matrix_sdk_client.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

const _roomId = "!voice:example.com";
const _fiveMb = 5 * 1024 * 1024;

Uint8List _file(int length) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 31 + 7) % 256));

/// [bytes] in [chunk]-byte pieces, as a chunked answer arrives.
Stream<List<int>> _chunks(Uint8List bytes, int chunk) async* {
  for (var i = 0; i < bytes.length; i += chunk) {
    final end = i + chunk < bytes.length ? i + chunk : bytes.length;
    yield Uint8List.sublistView(bytes, i, end);
  }
}

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {"content-type": "application/json"});

/// The accumulation before Vommet issue 1065, for comparison.
Future<Uint8List> _before(Stream<List<int>> body) async {
  List<int> downloaded = [];
  await body.listen((chunk) => downloaded.addAll(chunk)).asFuture();
  return Uint8List.fromList(downloaded);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group("reading a media body", () {
    test("5 MB in 1 KB chunks without a Content-Length is quick", () async {
      final file = _file(_fiveMb);

      final clock = Stopwatch()..start();
      final bytes = await readMediaBody(_chunks(file, 1024));
      final now = clock.elapsedMilliseconds;

      clock.reset();
      await _before(_chunks(file, 1024));
      final before = clock.elapsedMilliseconds;
      // ignore: avoid_print
      print("5 MB in 1 KB chunks: $now ms (before Vommet issue 1065: "
          "$before ms)");

      expect(bytes, file);
      expect(now, lessThan(2000));
    });

    test("with a Content-Length fills one buffer and counts the progress",
        () async {
      final file = _file(10000);
      final progress = <int>[];

      final bytes = await readMediaBody(_chunks(file, 3000),
          contentLength: file.length, onChunk: progress.add);

      expect(bytes, file);
      expect(progress, [3000, 6000, 9000, 10000]);
    });

    test("keeps bytes past a Content-Length that was too small", () async {
      final file = _file(10000);

      final bytes =
          await readMediaBody(_chunks(file, 4096), contentLength: 5000);

      expect(bytes, file);
    });

    test("an empty answer is an empty file", () async {
      expect(await readMediaBody(const Stream.empty()), isEmpty);
      expect(
          await readMediaBody(const Stream.empty(), contentLength: 0), isEmpty);
    });
  });

  group("a voice message's download", () {
    late Client client;
    late Room room;
    var clients = 0;

    setUp(() async {
      fileCache = null;
      final name = "media-download-${clients++}";
      client = MatrixSdkClient(name,
          database:
              await MatrixSdkDriftDatabase.init(NativeDatabase.memory(), name),
          httpClient: MockClient((request) async {
        if (request.url.path.endsWith("/versions")) {
          return _json({
            "versions": ["v1.11"]
          });
        }
        return _json({});
      }));
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
      await client.dispose(closeDatabase: true);
    });

    MxcFileProvider voice(int size) {
      final event = Event(
          type: "m.room.message",
          eventId: "\$voice",
          senderId: "@alice:example.com",
          originServerTs: DateTime(2026, 11),
          room: room,
          content: {
            "msgtype": "m.audio",
            "body": "voice.ogg",
            "url": "mxc://example.com/voice",
            "info": {"mimetype": "audio/ogg", "size": size},
          });
      final uri = Uri.parse("mxc://example.com/voice");
      return MxcFileProvider(client, uri, event: event);
    }

    test("asks for the file uncompressed and reads a chunked answer", () async {
      final file = _file(_fiveMb);
      final seen = <http.BaseRequest>[];
      final server = MockClient.streaming((request, _) async {
        seen.add(request);
        // No Content-Length, as a proxy compressing on the fly answers.
        return http.StreamedResponse(_chunks(file, 1024), 200);
      });

      final provider = voice(file.length);
      final progress = <DownloadProgress>[];
      final sub = provider.onProgressChanged!.listen(progress.add);

      final clock = Stopwatch()..start();
      final bytes =
          await http.runWithClient(provider.getFileData, () => server);
      clock.stop();
      await sub.cancel();

      expect(bytes, file);
      expect(clock.elapsedMilliseconds, lessThan(5000));
      expect(seen.single.url.path,
          "/_matrix/client/v1/media/download/example.com/voice");
      expect(seen.single.headers["accept-encoding"], "identity");
      expect(seen.single.headers["authorization"], "Bearer token");
      // The size comes from the event when the answer doesn't give it.
      for (final p in progress) {
        expect(p.total, file.length);
        expect(p.downloaded, lessThanOrEqualTo(file.length));
      }
    });

    test("a download that goes quiet fails instead of loading for good",
        () async {
      // The connection stalls after a few bytes: no more, and no end.
      final body = StreamController<List<int>>()..add([1, 2, 3]);
      final server = MockClient.streaming(
          (request, _) async => http.StreamedResponse(body.stream, 200));
      final before = mediaStallTimeout;
      mediaStallTimeout = const Duration(milliseconds: 200);
      addTearDown(() {
        mediaStallTimeout = before;
        body.close();
      });

      await expectLater(
          http.runWithClient(voice(100).getFileData, () => server),
          throwsA(isA<TimeoutException>()));
    });

    test("a server that never answers fails too", () async {
      final server = MockClient.streaming(
          (request, _) => Completer<http.StreamedResponse>().future);
      final before = mediaStallTimeout;
      mediaStallTimeout = const Duration(milliseconds: 200);
      addTearDown(() => mediaStallTimeout = before);

      await expectLater(
          http.runWithClient(voice(100).getFileData, () => server),
          throwsA(isA<TimeoutException>()));
    });

    test("an error answer is still an error", () async {
      final server = MockClient((request) async => http.Response("", 404));

      await expectLater(
          http.runWithClient(voice(100).getFileData, () => server),
          throwsA(isA<MediaDownloadException>()));
    });
  });
}
