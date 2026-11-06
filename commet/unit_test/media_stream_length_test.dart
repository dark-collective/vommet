// Vommet issue 1065: a video on a homeserver that gzips media (no
// Content-Length) and doesn't answer range requests goes through MxcFileProvider.getStreamSource ->
// MediaStream -> MediaStreamServer -> mpv. The length the local server
// announces to mpv must be the number of bytes it really serves.
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/cache/streamable_file_provider.dart';
import 'package:commet/client/matrix/matrix_mxc_file_provider.dart';
import 'package:commet/client/matrix/matrix_sdk_client.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

const _roomId = "!video:example.com";

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory root;
  late Client client;
  late Room room;
  var clients = 0;
  final body = Uint8List.fromList(List.generate(300000, (i) => i * 13 % 251));

  /// nginx with `gzip on` for every type: an answer without a
  /// Content-Length unless the file is asked for uncompressed (dart:io asks
  /// for gzip by default). Range requests are ignored, as Synapse does.
  http.StreamedResponse gzipProxy(http.BaseRequest request) {
    final identity = request.headers["accept-encoding"] == "identity";
    Stream<List<int>> pieces() async* {
      for (var i = 0; i < body.length; i += 4096) {
        yield body.sublist(i, i + 4096 > body.length ? body.length : i + 4096);
      }
    }

    return http.StreamedResponse(pieces(), 200,
        contentLength: identity ? body.length : null);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp("media_stream_length");
    PrivateMediaFiles.directoryOverride = "${root.path}/private";
    fileCache = null;
    resetRangeSupportCache();
    final name = "media-stream-length-${clients++}";
    client = MatrixSdkClient(name,
        database:
            await MatrixSdkDriftDatabase.init(NativeDatabase.memory(), name),
        httpClient: MockClient.streaming((request, _) async {
      if (request.url.path.endsWith("/versions")) {
        return http.StreamedResponse(
            Stream.value('{"versions":["v1.11"]}'.codeUnits), 200,
            headers: {"content-type": "application/json"});
      }
      if (request.url.path.contains("/media/download/")) {
        return gzipProxy(request);
      }
      return http.StreamedResponse(Stream.value("{}".codeUnits), 200);
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
    PrivateMediaFiles.directoryOverride = null;
    await root.delete(recursive: true);
  });

  MxcFileProvider video({int? size}) {
    final event = Event(
        type: "m.room.message",
        eventId: "\$video",
        senderId: "@alice_whatsapp:example.com",
        originServerTs: DateTime(2026, 11),
        room: room,
        content: {
          "msgtype": "m.video",
          "body": "video.mp4",
          "url": "mxc://example.com/video",
          "info": {"mimetype": "video/mp4", if (size != null) "size": size},
        });
    return MxcFileProvider(client, Uri.parse("mxc://example.com/video"),
        event: event);
  }

  /// What mpv sees: the status, Content-Length, Accept-Ranges and the bytes
  /// of a `Range: bytes=<from>-` request to the local server.
  Future<(int, int, String?, int)> player(Uri address, int from) async {
    final http = HttpClient();
    try {
      final request = await http.getUrl(address);
      request.headers.set(HttpHeaders.rangeHeader, "bytes=$from-");
      final response = await request.close();
      var got = 0;
      try {
        await for (final chunk in response) {
          got += chunk.length;
        }
      } catch (_) {}
      return (
        response.statusCode,
        response.contentLength,
        response.headers.value(HttpHeaders.acceptRangesHeader),
        got
      );
    } finally {
      http.close(force: true);
    }
  }

  Future<StreamSource> open(MxcFileProvider provider) async {
    final source = await http.runWithClient(provider.getStreamSource,
        () => MockClient.streaming((r, _) async => gzipProxy(r)));
    expect(source, isNotNull, reason: "goes through MediaStreamServer");
    expect(source!.uri.host, "127.0.0.1");
    return source;
  }

  for (final (label, size) in [
    ("info.size right", 300000),
    ("info.size too big (bridge)", 301000),
    ("info.size too small", 299000),
    ("no info.size", null),
  ]) {
    test("$label: mpv is told the real length and can seek", () async {
      final source = await open(video(size: size));
      // mpv's first request, then the seek to an MP4 index at the end.
      final first = await player(source.uri, 0);
      final tail = await player(source.uri, body.length - 1000);
      await source.close!();

      expect(first.$3, "bytes", reason: "seekable");
      expect(first.$2, body.length, reason: "announced length");
      expect(first.$4, body.length, reason: "bytes served");
      expect(tail.$1, 206);
      expect(tail.$4, 1000);
    });
  }
}
