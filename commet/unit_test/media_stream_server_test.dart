import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:commet/cache/media_stream_server.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An encrypted attachment as a Matrix client sends it.
class Fixture {
  final Uint8List plain;
  final Uint8List cipher;
  final Map<String, Object?> file;
  Fixture(this.plain, this.cipher, this.file);

  static Future<Fixture> make(int length, {bool badHash = false}) async {
    final random = Random(length);
    final plain =
        Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
    final key = Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));
    // Matrix IVs: random high 64 bits, counter (low 64 bits) zero.
    final iv = Uint8List(16)..setAll(0, [1, 2, 3, 4, 5, 6, 7, 8]);
    final box =
        await const DartAesCtr.with256bits(macAlgorithm: MacAlgorithm.empty)
            .encrypt(plain, secretKey: SecretKeyData(key), nonce: iv);
    final cipher = Uint8List.fromList(box.cipherText);
    var hash = crypto.sha256.convert(cipher).bytes;
    if (badHash) hash = [...hash.reversed];
    String b64(List<int> v) => base64.encode(v).replaceAll("=", "");
    return Fixture(plain, cipher, {
      "url": "mxc://example.org/x",
      "iv": b64(iv),
      "hashes": {"sha256": b64(hash)},
      "key": {
        "k": base64Url.encode(key).replaceAll("=", ""),
        "key_ops": ["encrypt", "decrypt"],
        "alg": "A256CTR",
        "kty": "oct",
        "ext": true,
      },
    });
  }
}

void main() {
  late Directory dir;
  final url =
      Uri.parse("https://hs.example/_matrix/client/v1/media/download/x");

  setUp(() async {
    dir = await Directory.systemTemp.createTemp("media_stream_test");
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// A homeserver that sends [body] in [chunk]-byte pieces, each after
  /// [gate] (when given) lets it through; range requests are answered when
  /// [ranges] is set. Records the requests.
  MockClient homeserver(Uint8List body,
      {int chunk = 4096,
      bool ranges = false,
      Stream<void> Function()? gate,
      List<http.BaseRequest>? seen}) {
    return MockClient.streaming((request, _) async {
      seen?.add(request);
      final range = request.headers["range"];
      if (ranges && range != null) {
        final m = RegExp(r"bytes=(\d+)-(\d*)").firstMatch(range)!;
        final start = int.parse(m.group(1)!);
        final end =
            m.group(2)!.isEmpty ? body.length - 1 : int.parse(m.group(2)!);
        final part = body.sublist(start, end + 1);
        return http.StreamedResponse(Stream.value(part), 206,
            contentLength: part.length);
      }
      Stream<List<int>> pieces() async* {
        final ticks = gate?.call();
        final iterator = ticks == null ? null : StreamIterator(ticks);
        for (var i = 0; i < body.length; i += chunk) {
          if (iterator != null && !await iterator.moveNext()) return;
          yield body.sublist(i, min(i + chunk, body.length));
        }
      }

      return http.StreamedResponse(pieces(), 200, contentLength: body.length);
    });
  }

  Future<(int, Uint8List, HttpHeaders)> get(Uri address,
      {String? range}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(address);
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      final bytes = await response
          .fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d))
          .then((b) => b.takeBytes());
      return (response.statusCode, bytes, response.headers);
    } finally {
      client.close(force: true);
    }
  }

  test("reads the key of an encrypted attachment", () async {
    final fixture = await Fixture.make(10);
    expect(AttachmentKey.fromFileMap(fixture.file), isNotNull);

    final noDecrypt = jsonDecode(jsonEncode(fixture.file)) as Map;
    (noDecrypt["key"] as Map)["key_ops"] = ["encrypt"];
    expect(
        AttachmentKey.fromFileMap(noDecrypt.cast<String, Object?>()), isNull);
    expect(AttachmentKey.fromFileMap({"iv": "x"}), isNull);
    expect(AttachmentKey.fromFileMap(null), isNull);
  });

  test("serves an encrypted file decrypted, whole and in ranges", () async {
    final fixture = await Fixture.make(300000);
    File? completed;
    final stream = MediaStream(
      url: url,
      copy: File("${dir.path}/copy.mp4"),
      client: homeserver(fixture.cipher),
      key: AttachmentKey.fromFileMap(fixture.file),
      contentType: "video/mp4",
      onComplete: (copy) async => completed = copy,
    );
    final address = await MediaStreamServer.instance.register(stream);
    expect(address.host, "127.0.0.1");

    final whole = await get(address);
    expect(whole.$1, 200);
    expect(whole.$2, fixture.plain);
    expect(whole.$3.value(HttpHeaders.acceptRangesHeader), "bytes");
    expect(whole.$3.contentType?.mimeType, "video/mp4");

    // An unaligned range (AES-CTR blocks are 16 bytes).
    final part = await get(address, range: "bytes=1237-99999");
    expect(part.$1, 206);
    expect(part.$2, fixture.plain.sublist(1237, 100000));
    expect(part.$3.value(HttpHeaders.contentRangeHeader),
        "bytes 1237-99999/300000");

    final tail = await get(address, range: "bytes=299990-");
    expect(tail.$2, fixture.plain.sublist(299990));

    expect((await get(address, range: "bytes=300000-")).$1, 416);

    await stream.done;
    expect(completed, isNotNull);
    expect(await completed!.readAsBytes(), fixture.plain);

    await MediaStreamServer.instance.unregister(address);
    expect(MediaStreamServer.instance.running, isFalse);
  });

  test("serves an unencrypted file from a server without ranges", () async {
    final body = Uint8List.fromList(List.generate(50000, (i) => i % 251));
    final stream = MediaStream(
        url: url, copy: File("${dir.path}/plain"), client: homeserver(body));
    final address = await MediaStreamServer.instance.register(stream);

    final part = await get(address, range: "bytes=40000-");
    expect(part.$1, 206);
    expect(part.$2, body.sublist(40000));

    await MediaStreamServer.instance.unregister(address);
  });

  test("a read past what has arrived waits for it", () async {
    final fixture = await Fixture.make(64 * 1024);
    final ticks = StreamController<void>();
    final stream = MediaStream(
      url: url,
      copy: File("${dir.path}/slow"),
      client: homeserver(fixture.cipher,
          chunk: 16 * 1024, gate: () => ticks.stream),
      key: AttachmentKey.fromFileMap(fixture.file),
    );
    await stream.start();

    ticks.add(null);
    final head = await stream.read(0, 999).expand((b) => b).toList();
    expect(head, fixture.plain.sublist(0, 1000));

    var tailDone = false;
    final tail = stream
        .read(60000, null)
        .expand((b) => b)
        .toList()
        .whenComplete(() => tailDone = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(tailDone, isFalse);

    for (var i = 0; i < 3; i++) {
      ticks.add(null);
    }
    expect(await tail, fixture.plain.sublist(60000));
    await stream.done;
    // Not awaited: the finished download no longer listens for the end.
    ticks.close().ignore();
    await stream.close();
  });

  test("a wrong checksum fails the stream and isn't cached", () async {
    final fixture = await Fixture.make(20000, badHash: true);
    var completed = false;
    final stream = MediaStream(
      url: url,
      copy: File("${dir.path}/bad"),
      client: homeserver(fixture.cipher),
      key: AttachmentKey.fromFileMap(fixture.file),
      onComplete: (_) async => completed = true,
    );
    await stream.start();

    await expectLater(stream.done, throwsA(isA<MediaIntegrityError>()));
    expect(completed, isFalse);
    // A whole-file read ends in the error instead of the end of the file.
    await expectLater(stream.read(0, null).drain<void>(),
        throwsA(isA<MediaIntegrityError>()));
    await stream.close();
  });

  test("a file cut short fails the stream", () async {
    final fixture = await Fixture.make(20000);
    final stream = MediaStream(
      url: url,
      copy: File("${dir.path}/short"),
      client: homeserver(fixture.cipher.sublist(0, 10000)),
      key: AttachmentKey.fromFileMap(fixture.file),
      size: 20000,
    );
    await stream.start();
    await expectLater(stream.done, throwsA(isA<MediaIntegrityError>()));
    await stream.close();
  });

  test("a far seek is fetched with a range request when the server can",
      () async {
    final fixture = await Fixture.make(MediaStream.fetchAheadBytes * 2);
    final seen = <http.BaseRequest>[];
    final ticks = StreamController<void>();
    final stream = MediaStream(
      url: url,
      copy: File("${dir.path}/seek"),
      client: homeserver(fixture.cipher,
          ranges: true, gate: () => ticks.stream, seen: seen),
      key: AttachmentKey.fromFileMap(fixture.file),
      rangeRequests: true,
    );
    await stream.start();

    // The download hasn't moved; the seek doesn't wait for it.
    final start = fixture.plain.length - 5000;
    final bytes = await stream.read(start, null).expand((b) => b).toList();
    expect(bytes, fixture.plain.sublist(start));
    expect(seen.last.headers["range"], "bytes=$start-");

    ticks.close().ignore();
    await stream.close();
  });

  test("an unknown address is not found", () async {
    final stream = MediaStream(
        url: url,
        copy: File("${dir.path}/x"),
        client: homeserver(Uint8List(10)));
    final address = await MediaStreamServer.instance.register(stream);
    final wrong = address.replace(pathSegments: ["0" * 64, "media"]);
    expect((await get(wrong)).$1, 404);
    await MediaStreamServer.instance.unregister(address);
  });
}
