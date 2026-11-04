// Vommet issue 1065 (telemetry schema v46): a voice message or video that
// hangs while loading leaves a media_load_stall event saying where it hangs,
// and media_load once it ends. Drives the real MxcFileProvider (resolve, the
// voice message path, and getStreamSource -> MediaStream, the video path)
// against a real HTTP homeserver on loopback that holds the answer or the
// rest of the body back, like the reporter's stalled loads. Before, nothing
// was recorded until a download ended, so a hung one left no trace.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/cache/file_cache.dart';
import 'package:commet/cache/streamable_file_provider.dart';
import 'package:commet/client/matrix/matrix_mxc_file_provider.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/telemetry/media_load_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;

class _Client extends Fake implements matrix.Client {
  _Client(this.homeserver);
  @override
  final Uri homeserver;
  @override
  String get accessToken => "token";
  @override
  final http.Client httpClient = http.Client();
  @override
  Future<bool> authenticatedMediaSupported() async => true;
  @override
  final matrix.DatabaseApi database = _Database();
}

/// The SDK's attachment store; nothing is kept there (maxFileSize 0), as
/// for a voice message too big for it.
class _Database extends Fake implements matrix.DatabaseApi {
  @override
  int get maxFileSize => 0;
}

/// A plain file cache in [dir] (MxcFileProvider.resolve ends in putFile).
class _Cache extends Fake implements FileCache {
  _Cache(this.dir);
  final Directory dir;
  @override
  Future<bool> hasFile(String identifier, {bool sensitive = false}) async =>
      false;
  @override
  Future<Uri?> getFile(String identifier) async => null;
  @override
  Future<Uint8List?> readFile(
    String identifier, {
    bool sensitive = false,
  }) async =>
      null;
  @override
  Future<Uri> putFile(String identifier, Uint8List bytes) async {
    final f = File("${dir.path}/cached");
    await f.writeAsBytes(bytes);
    return f.uri;
  }
}

/// A homeserver on loopback serving [body] at the media download path.
/// [headersFirst]: it answers with the headers and the first [head] bytes,
/// then holds the rest until [release]; otherwise it holds the whole answer
/// (no headers either) until [release]. Range probes get a 200 with no
/// Content-Range (no range support).
class _Homeserver {
  _Homeserver(this.body, {this.head = 4096, this.headersFirst = true});
  final Uint8List body;
  final int head;
  final bool headersFirst;
  final release = Completer<void>();
  final paths = <String>[];
  late HttpServer server;

  Uri get uri => Uri.parse("http://127.0.0.1:${server.port}/");

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      paths.add(request.uri.path);
      final r = request.response;
      try {
        if (request.headers.value("range") != null) {
          r.statusCode = 200;
          r.contentLength = body.length;
          r.add(body);
          await r.close();
          return;
        }
        if (!headersFirst) await release.future;
        r.statusCode = 200;
        r.contentLength = body.length;
        r.add(body.sublist(0, head));
        await r.flush();
        await release.future;
        r.add(body.sublist(head));
        await r.close();
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    if (!release.isCompleted) release.complete();
    await server.close(force: true);
  }
}

Uint8List _bytes(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + 7) % 256));

Future<(Uint8List, Map<String, Object?>)> _encrypt(Uint8List plain) async {
  final key = Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));
  final iv = Uint8List(16)..setAll(0, [1, 2, 3, 4, 5, 6, 7, 8]);
  final box = await const DartAesCtr.with256bits(
    macAlgorithm: MacAlgorithm.empty,
  ).encrypt(plain, secretKey: SecretKeyData(key), nonce: iv);
  final cipher = Uint8List.fromList(box.cipherText);
  String b64(List<int> v) => base64.encode(v).replaceAll("=", "");
  return (
    cipher,
    <String, Object?>{
      "url": "mxc://example.org/media",
      "v": "v2",
      "mimetype": "video/mp4",
      "iv": b64(iv),
      "hashes": {"sha256": b64(crypto.sha256.convert(cipher).bytes)},
      "key": {
        "k": base64Url.encode(key).replaceAll("=", ""),
        "key_ops": ["encrypt", "decrypt"],
        "alg": "A256CTR",
        "kty": "oct",
        "ext": true,
      },
    },
  );
}

matrix.Event _event(
  matrix.Client client,
  Map<String, Object?> content, {
  bool encrypted = false,
}) {
  final room = matrix.Room(id: "!room:example.org", client: client);
  if (encrypted) {
    room.states[matrix.EventTypes.Encryption] = {
      "": matrix.Event.fromJson({
        "type": matrix.EventTypes.Encryption,
        "event_id": "\$enc",
        "sender": "@a:example.org",
        "origin_server_ts": 1700000000000,
        "state_key": "",
        "content": {"algorithm": "m.megolm.v1.aes-sha2"},
      }, room),
    };
  }
  return matrix.Event.fromJson({
    "type": matrix.EventTypes.Message,
    "event_id": "\$media",
    "sender": "@a:example.org",
    "origin_server_ts": 1700000000000,
    "content": content,
  }, room);
}

Map<String, Object?> _voice(int size) => {
      "msgtype": "m.audio",
      "body": "voice.ogg",
      "url": "mxc://example.org/media",
      "info": {"size": size, "mimetype": "audio/ogg"},
      "org.matrix.msc3245.voice": {},
    };

const _wait = Duration(seconds: 20);

void main() {
  late Directory dir;
  late TelemetrySchema schema;
  final events = <Map<String, Object?>>[];

  Future<Map<String, Object?>> next(String name) async {
    final deadline = DateTime.now().add(_wait);
    while (DateTime.now().isBefore(deadline)) {
      for (final e in events) {
        if (e["e"] == name) return e;
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }
    fail("no $name event; recorded: $events");
  }

  setUpAll(() {
    schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync(),
    );
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp("t1065stall");
    PrivateMediaFiles.directoryOverride = "${dir.path}/media_open";
    app.fileCache = _Cache(dir);
    resetRangeSupportCache();
    events.clear();
    MediaLoadWatch.stallAfter = const Duration(milliseconds: 300);
    MediaLoadWatch.enabled = () => true;
    MediaLoadWatch.record = (name, fields) {
      final ev = <String, Object?>{"e": name, "t": 1};
      fields.forEach((k, v) {
        if (v != null) ev[k] = v;
      });
      expect(
        schema.validateEvent(ev),
        isTrue,
        reason: "$name must fit the telemetry schema: $ev",
      );
      events.add(ev);
    };
  });

  tearDown(() async {
    MediaLoadWatch.stallAfter = const Duration(seconds: 10);
    PrivateMediaFiles.directoryOverride = null;
    app.fileCache = null;
    await dir.delete(recursive: true);
  });

  test("1065 voice message whose body stalls records step body", () async {
    const size = 64 * 1024;
    final hs = _Homeserver(_bytes(size), head: 4096);
    await hs.start();
    final client = _Client(hs.uri);
    try {
      final provider = MxcFileProvider(
        client,
        Uri.parse("mxc://example.org/media"),
        event: _event(client, _voice(size)),
      );
      final resolving = provider.resolve();

      final stall = await next("media_load_stall");
      expect(stall["path"], "resolve");
      expect(stall["kind"], "voice");
      expect(stall["step"], "body");
      expect(stall["bytes"], 4096);
      expect(stall["size"], size);
      expect(stall["encrypted"], false);
      expect(stall["endpoint"], "v1");
      expect(stall["elapsed_ms"] as int, greaterThanOrEqualTo(300));
      expect(events.where((e) => e["e"] == "media_load"), isEmpty);
      // Nothing that names the file, the room or the server.
      expect(jsonEncode(events), isNot(contains("example.org")));
      expect(jsonEncode(events), isNot(contains("127.0.0.1")));

      hs.release.complete();
      expect(await resolving.timeout(_wait), isNotNull);
      final end = await next("media_load");
      expect(end["outcome"], "ok");
      expect(end["stalled"], true);
      expect(end["bytes"], size);
      expect(
        end["total_ms"] as int,
        greaterThanOrEqualTo(stall["elapsed_ms"] as int),
      );
      expect(events.where((e) => e["e"] == "media_load_stall").length, 1);
    } finally {
      client.httpClient.close();
      await hs.stop();
    }
  });

  test("1065 voice message with no answer records step request_sent", () async {
    const size = 8 * 1024;
    final hs = _Homeserver(_bytes(size), head: 1024, headersFirst: false);
    await hs.start();
    final client = _Client(hs.uri);
    try {
      final provider = MxcFileProvider(
        client,
        Uri.parse("mxc://example.org/media"),
        event: _event(client, _voice(size)),
      );
      final resolving = provider.resolve();

      final stall = await next("media_load_stall");
      expect(stall["step"], "request_sent");
      expect(stall["bytes"], 0);
      expect(stall["size"], size, reason: "from the event's info.size");
      expect(hs.paths.single, startsWith("/_matrix/client/v1/media/"));

      hs.release.complete();
      await resolving.timeout(_wait);
      expect((await next("media_load"))["outcome"], "ok");
    } finally {
      client.httpClient.close();
      await hs.stop();
    }
  });

  test(
    "1065 encrypted video stream that stalls records it (MediaStream)",
    () async {
      const size = 256 * 1024;
      final (cipher, file) = await _encrypt(_bytes(size));
      final hs = _Homeserver(cipher, head: 16 * 1024);
      await hs.start();
      final client = _Client(hs.uri);
      try {
        final provider = MxcFileProvider(
          client,
          Uri.parse("mxc://example.org/media"),
          event: _event(
              client,
              {
                "msgtype": "m.video",
                "body": "clip.mp4",
                "file": file,
                "info": {"size": size, "mimetype": "video/mp4"},
              },
              encrypted: true),
        );
        final source = await provider.getStreamSource().timeout(_wait);
        expect(source, isNotNull);

        final stall = await next("media_load_stall");
        expect(stall["path"], "stream");
        expect(stall["kind"], "video");
        expect(stall["step"], "body");
        expect(stall["bytes"], 16 * 1024);
        expect(stall["size"], size);
        expect(stall["encrypted"], true);
        expect(stall["endpoint"], "v1");

        hs.release.complete();
        await source!.verified!.timeout(_wait);
        final end = await next("media_load");
        expect(end["outcome"], "ok");
        expect(end["stalled"], true);
        expect(end["bytes"], size);
        await source.close?.call();
      } finally {
        client.httpClient.close();
        await hs.stop();
      }
    },
  );
}
