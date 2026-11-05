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
import 'package:media_kit/media_kit.dart';

import 'media_load_fake_player.dart';

class _Client extends Fake implements matrix.Client {
  _Client(this.homeserver);
  @override
  final Uri homeserver;
  @override
  String get accessToken => "token";
  @override
  final http.Client httpClient = http.Client();
  /// Holds the URL lookup (getDownloadUri asks this first).
  Future<void>? urlHold;
  @override
  Future<bool> authenticatedMediaSupported() async {
    await urlHold;
    return true;
  }
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

  /// Set: the cache lookup waits for it (a cache that never answers).
  Future<void>? hold;

  /// Opening a cached sealed entry fails (no private copy can be made).
  Object? openError;

  @override
  Future<bool> hasFile(String identifier, {bool sensitive = false}) async {
    await hold;
    return false;
  }

  @override
  Future<bool> openToFile(String identifier, String path,
      {bool sensitive = false}) async {
    await hold;
    if (openError != null) throw openError!;
    return false;
  }

  @override
  Future<void> writeFile(String identifier, Uint8List bytes,
      {bool sensitive = false}) async {}

  @override
  Future<Uint8List?> sealData(String identifier, Uint8List bytes) async => null;
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
/// Content-Range (no range support), or a 206 when [ranges]. [status]:
/// every download is answered with that error status.
class _Homeserver {
  _Homeserver(this.body,
      {this.head = 16 * 1024,
      this.headersFirst = true,
      this.ranges = false,
      this.status});
  final Uint8List body;
  final int head;
  final bool headersFirst;
  final bool ranges;
  final int? status;
  final release = Completer<void>();
  final paths = <String>[];
  late HttpServer server;

  Uri get uri => Uri.parse("http://127.0.0.1:${server.port}/");

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      paths.add(request.uri.path);
      final r = request.response;
      // Send what was written at once, as a homeserver streaming a file
      // does: dart:io holds writes below 8 KB back otherwise.
      r.bufferOutput = false;
      try {
        if (request.headers.value("range") != null) {
          if (ranges) {
            r.statusCode = 206;
            r.headers.set("content-range", "bytes 0-0/${body.length}");
            r.contentLength = 1;
            r.add(body.sublist(0, 1));
          } else {
            r.statusCode = 200;
            r.contentLength = body.length;
            r.add(body);
          }
          await r.close();
          return;
        }
        if (status != null) {
          r.statusCode = status!;
          r.write('{"errcode":"M_NOT_FOUND"}');
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

Map<String, Object?> _video(int size, [Map<String, Object?>? file]) => {
      "msgtype": "m.video",
      "body": "clip.mp4",
      if (file != null) "file": file else "url": "mxc://example.org/media",
      "info": {"size": size, "mimetype": "video/mp4"},
    };

const _wait = Duration(seconds: 20);

/// The video player's part (VideoPlayerImplementation): a player opens the
/// source and loads it (LoadingFakePlayer: 300 ms after open()).
Future<void> _playerLoads(StreamSource source) async {
  final player = LoadingFakePlayer();
  PlayerLoadWatch(source.opening!, player);
  await player.open(Playlist(const []));
  await Future.delayed(const Duration(milliseconds: 400));
}

void main() {
  late Directory dir;
  late TelemetrySchema schema;
  final events = <Map<String, Object?>>[];

  // The watches made so far. The stall timer is set far out and each test
  // fires the stall once the load is in the step it checks: a short real
  // timer raced the first body chunk on a busy runner.
  final watches = <MediaLoadWatch>[];
  Future<void> stallWhen(bool Function(MediaLoadWatch w) ready) async {
    final deadline = DateTime.now().add(_wait);
    while (DateTime.now().isBefore(deadline)) {
      for (final w in watches) {
        if (ready(w)) return w.stallNow();
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }
    fail("no load reached the step: ${watches.map((w) => w.step)}");
  }

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
    watches.clear();
    MediaLoadWatch.stallAfter = const Duration(hours: 1);
    MediaLoadWatch.onCreate = watches.add;
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
    MediaLoadWatch.onCreate = null;
    MediaLoadWatch.enabled = () => true;
    PrivateMediaFiles.directoryOverride = null;
    app.fileCache = null;
    await dir.delete(recursive: true);
  });

  test("1065 voice message whose body stalls records step body", () async {
    const size = 64 * 1024;
    final hs = _Homeserver(_bytes(size), head: 16 * 1024);
    await hs.start();
    final client = _Client(hs.uri);
    try {
      final provider = MxcFileProvider(
        client,
        Uri.parse("mxc://example.org/media"),
        event: _event(client, _voice(size)),
      );
      final resolving = provider.resolve();

      await stallWhen((w) => w.bytes >= 16 * 1024);
      final stall = await next("media_load_stall");
      expect(stall["path"], "resolve");
      expect(stall["kind"], "voice");
      expect(stall["step"], "body");
      expect(stall["bytes"], 16 * 1024);
      expect(stall["size"], size);
      expect(stall["encrypted"], false);
      expect(stall["endpoint"], "v1");
      expect(stall["elapsed_ms"] as int, greaterThanOrEqualTo(0));
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

      await stallWhen((w) => hs.paths.isNotEmpty && w.step != "cache");
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

        await stallWhen((w) => w.bytes >= 16 * 1024);
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
        // Downloaded; the player hasn't loaded it yet.
        expect(events.where((e) => e["e"] == "media_load"), isEmpty);
        await _playerLoads(source);
        final end = await next("media_load");
        expect(end["outcome"], "ok");
        expect(end["step"], "opening");
        expect(end["stalled"], true);
        expect(end["bytes"], size);
        await source.close?.call();
      } finally {
        client.httpClient.close();
        await hs.stop();
      }
    },
  );

  test(
    "1065 encrypted-room voice message stuck in the cache records step cache",
    () async {
      // The 11-03 Android case: the download never starts. The cache lookup
      // of the private copy (MxcFileProvider.sensitive) holds.
      const size = 8 * 1024;
      final hs = _Homeserver(_bytes(size));
      await hs.start();
      final client = _Client(hs.uri);
      final cache = app.fileCache as _Cache;
      final hold = Completer<void>();
      cache.hold = hold.future;
      try {
        final provider = MxcFileProvider(
          client,
          Uri.parse("mxc://example.org/media"),
          event: _event(client, _voice(size), encrypted: true),
        );
        expect(provider.sensitive, isTrue);
        final resolving = provider.resolve();

        await stallWhen((w) => w.path == "resolve");
        final stall = await next("media_load_stall");
        expect(stall["path"], "resolve");
        expect(stall["kind"], "voice");
        expect(stall["step"], "cache");
        expect(stall["encrypted"], true);
        expect(stall.containsKey("endpoint"), isFalse);
        expect(hs.paths, isEmpty, reason: "no request was made");

        // Then no private copy can be made.
        cache.openError = const FileSystemException("no private copy");
        hold.complete();
        expect(await resolving.timeout(_wait), isNull);
        final end = await next("media_load");
        expect(end["outcome"], "error");
        expect(end["step"], "cache");
        expect(end["stalled"], true);
        expect(end["error_type"], "FileSystemException");
        expect(events.where((e) => e["e"] == "media_load").length, 1);
      } finally {
        if (!hold.isCompleted) hold.complete();
        client.httpClient.close();
        await hs.stop();
      }
    },
  );

  test("1065 video stuck before its stream starts records stream step cache",
      () async {
    const size = 64 * 1024;
    final hs = _Homeserver(_bytes(size));
    await hs.start();
    final client = _Client(hs.uri);
    final cache = app.fileCache as _Cache;
    final hold = Completer<void>();
    cache.hold = hold.future;
    try {
      final provider = MxcFileProvider(
        client,
        Uri.parse("mxc://example.org/media"),
        event: _event(client, _video(size)),
      );
      final starting = provider.getStreamSource();

      await stallWhen((w) => w.path == "stream");
      final stall = await next("media_load_stall");
      expect(stall["path"], "stream");
      expect(stall["kind"], "video");
      expect(stall["step"], "cache");
      expect(stall["encrypted"], false);
      expect(hs.paths, isEmpty, reason: "no request was made");

      hold.complete();
      final source = await starting.timeout(_wait);
      expect(source, isNotNull);
      hs.release.complete();
      await source!.verified!.timeout(_wait);
      await _playerLoads(source);
      final end = await next("media_load");
      expect(end["path"], "stream");
      expect(end["outcome"], "ok");
      expect(end["stalled"], true);
      expect(end["bytes"], size);
      await source.close?.call();
    } finally {
      if (!hold.isCompleted) hold.complete();
      client.httpClient.close();
      await hs.stop();
    }
  });

  test("1065 video streamed straight from the homeserver is watched", () async {
    // Unencrypted, the server answers ranges: mpv streams from the server
    // itself, so the watch runs through the range probe to the player's
    // open (the video player ends it).
    const size = 64 * 1024;
    final hs = _Homeserver(_bytes(size), ranges: true);
    await hs.start();
    final client = _Client(hs.uri);
    try {
      final provider = MxcFileProvider(
        client,
        Uri.parse("mxc://example.org/media"),
        event: _event(client, _video(size)),
      );
      final source = await provider.getStreamSource().timeout(_wait);
      expect(source, isNotNull);
      expect(source!.uri.path, startsWith("/_matrix/client/v1/media/"));

      await stallWhen((w) => w.path == "stream");
      final stall = await next("media_load_stall");
      expect(stall["path"], "stream");
      expect(stall["kind"], "video");
      expect(stall["step"], "opening");
      expect(stall["endpoint"], "v1");
      expect(stall["encrypted"], false);
      expect(hs.paths, hasLength(1), reason: "only the range probe");
    } finally {
      client.httpClient.close();
      await hs.stop();
    }
  });

  test(
    "1065 encrypted video downloaded but never loaded by the player stalls at opening",
    () async {
      const size = 64 * 1024;
      final (cipher, file) = await _encrypt(_bytes(size));
      final hs = _Homeserver(cipher);
      await hs.start();
      final client = _Client(hs.uri);
      try {
        final provider = MxcFileProvider(
          client,
          Uri.parse("mxc://example.org/media"),
          event: _event(client, _video(size, file), encrypted: true),
        );
        final source = await provider.getStreamSource().timeout(_wait);
        expect(source, isNotNull);
        expect(source!.opening, isNotNull);
        final player = LoadingFakePlayer()..openHangs = true;
        final load = PlayerLoadWatch(source.opening!, player);
        await player.open(Playlist(const []));
        hs.release.complete();
        await source.verified!.timeout(_wait);
        await Future.delayed(const Duration(milliseconds: 400));
        expect(events, isEmpty, reason: "no ok before the player loads it");

        await stallWhen((w) => w.path == "stream");
        final stall = await next("media_load_stall");
        expect(stall["step"], "opening");
        expect(stall["bytes"], size);
        expect(stall["encrypted"], true);

        // The player goes away.
        load.cancel();
        final end = await next("media_load");
        expect(end["outcome"], "cancelled");
        expect(end["step"], "opening");
        expect(end["stalled"], true);
        await source.close?.call();
      } finally {
        client.httpClient.close();
        await hs.stop();
      }
    },
  );

  for (final stream in [false, true]) {
    final what = stream ? "video" : "voice message";
    test("1065 $what whose URL lookup hangs records step url", () async {
      const size = 8 * 1024;
      final hs = _Homeserver(_bytes(size));
      await hs.start();
      final client = _Client(hs.uri);
      final hold = Completer<void>();
      client.urlHold = hold.future;
      try {
        final provider = MxcFileProvider(
          client,
          Uri.parse("mxc://example.org/media"),
          event: _event(client, stream ? _video(size) : _voice(size)),
        );
        final loading =
            stream ? provider.getStreamSource() : provider.resolve();
        final path = stream ? "stream" : "resolve";

        await stallWhen((w) => w.path == path && w.step == "url");
        final stall = await next("media_load_stall");
        expect(stall["path"], path);
        expect(stall["step"], "url");
        expect(stall.containsKey("endpoint"), isFalse);
        expect(hs.paths, isEmpty, reason: "no request was made");
        hold.complete();
        hs.release.complete();
        final got = await loading.timeout(_wait);
        if (got is StreamSource) await got.close?.call();
      } finally {
        if (!hold.isCompleted) hold.complete();
        client.httpClient.close();
        await hs.stop();
      }
    });
  }

  test("1065 voice message answered 404 records an error end", () async {
    final hs = _Homeserver(_bytes(1024), status: 404);
    await hs.start();
    final client = _Client(hs.uri);
    try {
      final provider = MxcFileProvider(
        client,
        Uri.parse("mxc://example.org/media"),
        event: _event(client, _voice(1024)),
      );
      try {
        await provider.resolve().timeout(_wait);
      } catch (_) {}
      final end = await next("media_load");
      expect(end["path"], "resolve");
      expect(end["outcome"], "error");
      expect(end["http_status"], 404);
      expect(end["stalled"], false);
      expect(end["error_type"], isNotNull);
      expect(events.where((e) => e["e"] == "media_load_stall"), isEmpty);
    } finally {
      client.httpClient.close();
      await hs.stop();
    }
  });

  test("1065 encrypted video answered 502 records an error end", () async {
    final (cipher, file) = await _encrypt(_bytes(4096));
    final hs = _Homeserver(cipher, status: 502);
    await hs.start();
    final client = _Client(hs.uri);
    try {
      final provider = MxcFileProvider(
        client,
        Uri.parse("mxc://example.org/media"),
        event: _event(client, _video(4096, file), encrypted: true),
      );
      final source = await provider.getStreamSource().timeout(_wait);
      expect(source, isNotNull);
      await expectLater(source!.verified!.timeout(_wait), throwsA(anything));
      final end = await next("media_load");
      expect(end["path"], "stream");
      expect(end["outcome"], "error");
      expect(end["http_status"], 502);
      expect(end["stalled"], false);
      expect(end["encrypted"], true);
      await source.close?.call();
    } finally {
      client.httpClient.close();
      await hs.stop();
    }
  });

  test("1065 video closed mid-download records a cancelled end", () async {
    const size = 64 * 1024;
    final (cipher, file) = await _encrypt(_bytes(size));
    final hs = _Homeserver(cipher, head: 16 * 1024);
    await hs.start();
    final client = _Client(hs.uri);
    try {
      final provider = MxcFileProvider(
        client,
        Uri.parse("mxc://example.org/media"),
        event: _event(client, _video(size, file), encrypted: true),
      );
      final source = await provider.getStreamSource().timeout(_wait);
      expect(source, isNotNull);
      final deadline = DateTime.now().add(_wait);
      while (!watches.any((w) => w.bytes >= 16 * 1024) &&
          DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      // The player goes away.
      await source!.close!.call().timeout(_wait);
      final end = await next("media_load");
      expect(end["outcome"], "cancelled");
      expect(end["step"], "body");
      expect(end["stalled"], false);
      expect(end.containsKey("error_type"), isFalse);
    } finally {
      client.httpClient.close();
      await hs.stop();
    }
  });

  test("1065 telemetry off: a stalled load records nothing", () async {
    MediaLoadWatch.enabled = () => false;
    MediaLoadWatch.stallAfter = const Duration(milliseconds: 50);
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
      final deadline = DateTime.now().add(_wait);
      while (hs.paths.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      expect(hs.paths, isNotEmpty);
      await Future.delayed(const Duration(milliseconds: 300));
      hs.release.complete();
      expect(await resolving.timeout(_wait), isNotNull);
      expect(events, isEmpty);
    } finally {
      client.httpClient.close();
      await hs.stop();
    }
  });

  group("1065 the real stall timer (stallAfter 200 ms)", () {
    setUp(() {
      MediaLoadWatch.onCreate = null;
      MediaLoadWatch.stallAfter = const Duration(milliseconds: 200);
    });

    test("a held voice message records media_load_stall", () async {
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
        expect(stall["path"], "resolve");
        expect(stall["elapsed_ms"] as int, greaterThanOrEqualTo(150));
        hs.release.complete();
        await resolving.timeout(_wait);
        expect((await next("media_load"))["stalled"], true);
        expect(events.where((e) => e["e"] == "media_load_stall").length, 1);
      } finally {
        client.httpClient.close();
        await hs.stop();
      }
    });

    test("a fast voice message records none", () async {
      const size = 8 * 1024;
      final hs = _Homeserver(_bytes(size), head: 1024, headersFirst: false);
      hs.release.complete();
      await hs.start();
      final client = _Client(hs.uri);
      try {
        final provider = MxcFileProvider(
          client,
          Uri.parse("mxc://example.org/media"),
          event: _event(client, _voice(size)),
        );
        expect(await provider.resolve().timeout(_wait), isNotNull);
        final end = await next("media_load");
        expect(end["outcome"], "ok");
        expect(end["stalled"], false);
        // Past the stall time: the ended load's timer is gone.
        await Future.delayed(const Duration(milliseconds: 400));
        expect(events.where((e) => e["e"] == "media_load_stall"), isEmpty);
      } finally {
        client.httpClient.close();
        await hs.stop();
      }
    });
  });
}
