import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:commet/debug/log.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:http/http.dart' as http;

/// Vommet: the key of a Matrix encrypted attachment (the event's `file`
/// object): AES-256-CTR with a 64-bit counter, and the SHA-256 of the
/// encrypted bytes.
class AttachmentKey {
  final Uint8List key;
  final Uint8List iv;
  final Uint8List sha256;

  AttachmentKey(this.key, this.iv, this.sha256);

  /// Reads the event's `file` object, or null when it is incomplete or its
  /// key isn't for decrypting.
  static AttachmentKey? fromFileMap(Map<String, Object?>? file) {
    try {
      final keyMap = file?["key"];
      final hashes = file?["hashes"];
      if (keyMap is! Map || hashes is! Map) return null;
      final ops = keyMap["key_ops"];
      if (ops is! List || !ops.contains("decrypt")) return null;
      final k = keyMap["k"], iv = file?["iv"], hash = hashes["sha256"];
      if (k is! String || iv is! String || hash is! String) return null;
      final parsed =
          AttachmentKey(_unpadded(k), _unpadded(iv), _unpadded(hash));
      if (parsed.key.length != 32 ||
          parsed.iv.length != 16 ||
          parsed.sha256.length != 32) {
        return null;
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  /// Unpadded base64, either alphabet (the key is base64url, the rest
  /// standard base64).
  static Uint8List _unpadded(String value) => base64.decode(
      base64.normalize(value.replaceAll("-", "+").replaceAll("_", "/")));
}

/// Vommet: the downloaded file didn't match the checksum in the event, or
/// ended early.
class MediaIntegrityError implements Exception {
  final String message;
  MediaIntegrityError(this.message);

  @override
  String toString() => "MediaIntegrityError: $message";
}

/// Vommet: one file being played while it downloads (Vommet issue 338 for
/// encrypted rooms and for homeservers without range requests).
///
/// The file is downloaded from the start, in order, into [copy] (an
/// owner-only private file); media from an encrypted room is decrypted on
/// the way, which AES-CTR allows at any offset. The player reads it through
/// [MediaStreamServer] and gets each byte as soon as it has arrived. A read
/// past what has arrived waits for it, unless the homeserver answers range
/// requests ([rangeRequests]): then a read that far ahead is fetched (and
/// decrypted) on its own, so seeking doesn't wait for the download.
///
/// The checksum of an encrypted file covers the whole file, so it can only
/// be checked at the end: until then the player is fed bytes that aren't
/// verified yet. A mismatch ends the stream: open reads fail, [done]
/// completes with a [MediaIntegrityError] and the file isn't cached.
class MediaStream {
  MediaStream({
    required this.url,
    required this.copy,
    required this.client,
    this.headers = const {},
    this.key,
    this.size,
    this.contentType,
    this.rangeRequests = false,
    this.onComplete,
  }) {
    // Nobody may be listening when it fails (the player went away).
    _done.future.ignore();
  }

  /// Where the (possibly encrypted) file is downloaded from.
  final Uri url;
  final Map<String, String> headers;

  /// The private file the plain bytes are written to.
  final File copy;
  final http.Client client;

  /// The attachment key, or null for a file that isn't encrypted.
  final AttachmentKey? key;

  /// The size from the event (`info.size`), used until the download says.
  final int? size;
  final String? contentType;

  /// Whether the homeserver answers range requests.
  final bool rangeRequests;

  /// Called once with [copy] when the whole file has arrived and checked out
  /// (to cache it). The copy stays in place until [close].
  final Future<void> Function(File copy)? onComplete;

  /// A read this far past what has arrived is fetched on its own when the
  /// server answers range requests; closer ones wait for the download.
  static const int fetchAheadBytes = 2 * 1024 * 1024;

  static const DartAesCtr _aes =
      DartAesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);

  int _arrived = 0;
  int? _total;
  bool _finished = false;
  bool _closed = false;
  Object? _failure;
  Completer<void> _progress = Completer<void>();
  final Completer<void> _done = Completer<void>();
  Future<void>? _started;
  StreamSubscription<List<int>>? _download;
  RandomAccessFile? _writer;
  Future<void>? _writing;

  /// How many bytes from the start have arrived.
  int get arrived => _arrived;

  /// The file's size, once known.
  int? get total => _total;

  /// Completes when the whole file has arrived and checked out; fails with
  /// a [MediaIntegrityError] (or the download's error) otherwise.
  Future<void> get done => _done.future;

  /// Starts the download (once) and waits for the server's answer, which
  /// gives the size.
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    _total = size;
    try {
      _writer = await copy.open(mode: FileMode.write);
      final request = http.Request("GET", url)..headers.addAll(headers);
      final response = await client.send(request);
      if (response.statusCode != 200) {
        await response.stream.listen(null).cancel();
        throw HttpException("Unexpected response: ${response.statusCode}",
            uri: url);
      }
      final length = response.contentLength;
      if (length != null && length >= 0) _total = length;

      final hash = _HashSink();
      final hashing = crypto.sha256.startChunkedConversion(hash);
      // Writes are chained so the file grows in order; the subscription is
      // paused while one is pending so memory stays bounded.
      _download = response.stream.listen(null, cancelOnError: true);
      _download!.onData((chunk) {
        _download!.pause();
        final writing = _writing = _write(chunk, hashing);
        writing.then((_) => _download?.resume(),
            onError: (Object error) => _fail(error));
      });
      _download!.onError((Object error) => _fail(error));
      _download!.onDone(() async {
        try {
          hashing.close();
          await _finish(hash.value);
        } catch (error) {
          _fail(error);
        }
      });
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _write(List<int> chunk, Sink<List<int>> hashing) async {
    if (_closed) return;
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    if (key != null) hashing.add(bytes);
    final plain = await _decrypt(bytes, _arrived);
    await _writer!.writeFrom(plain);
    _arrived += plain.length;
    _notify();
  }

  Future<List<int>> _decrypt(Uint8List bytes, int offset) async {
    final k = key;
    if (k == null) return bytes;
    return _aes.decrypt(SecretBox(bytes, nonce: k.iv, mac: Mac.empty),
        secretKey: SecretKeyData(k.key), keyStreamIndex: offset);
  }

  Future<void> _finish(crypto.Digest? digest) async {
    if (_closed) return;
    await _writer?.flush();
    await _writer?.close();
    _writer = null;
    final total = _total;
    if (total != null && _arrived != total) {
      throw MediaIntegrityError("expected $total bytes, got $_arrived");
    }
    final k = key;
    if (k != null) {
      final actual = digest?.bytes;
      if (actual == null || !_equal(actual, k.sha256)) {
        throw MediaIntegrityError("checksum mismatch");
      }
    }
    _total = _arrived;
    _finished = true;
    _notify();
    if (!_done.isCompleted) _done.complete();
    final complete = onComplete;
    if (complete != null) {
      try {
        await complete(copy);
      } catch (error) {
        Log.w("Couldn't cache streamed media: $error");
      }
    }
  }

  /// Stops the download and closes the file once a pending write is done.
  Future<void> _stop() async {
    final download = _download;
    _download = null;
    await download?.cancel();
    try {
      await _writing;
    } catch (_) {}
    final writer = _writer;
    _writer = null;
    try {
      await writer?.close();
    } catch (_) {}
  }

  void _fail(Object error) {
    if (_failure != null || _finished) return;
    _failure = error;
    _stop().ignore();
    if (!_closed) Log.w("Media stream failed: $error");
    if (!_done.isCompleted) _done.completeError(error);
    _notify();
  }

  void _notify() {
    final previous = _progress;
    _progress = Completer<void>();
    previous.complete();
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// The plain bytes from [start] up to and including [end] (to the end of
  /// the file when null), as they arrive.
  Stream<List<int>> read(int start, int? end) async* {
    await this.start();
    var position = start;
    RandomAccessFile? reader;
    try {
      while (true) {
        if (_closed) return;
        final last = end ?? (_finished ? _arrived - 1 : null);
        if (last != null && position > last) return;
        final failure = _failure;
        if (failure != null) throw failure;

        if (position < _arrived) {
          reader ??= await copy.open();
          var until = _arrived;
          if (last != null && last + 1 < until) until = last + 1;
          await reader.setPosition(position);
          while (position < until) {
            final count = min(until - position, 64 * 1024);
            final bytes = await reader.read(count);
            if (bytes.isEmpty) break;
            position += bytes.length;
            yield bytes;
          }
          continue;
        }

        if (rangeRequests &&
            !_finished &&
            position - _arrived > fetchAheadBytes) {
          yield* _fetchRange(position, last);
          return;
        }
        await _progress.future;
      }
    } finally {
      await reader?.close();
    }
  }

  /// Fetches [start]..[end] straight from the homeserver with a range
  /// request, decrypting it at its offset.
  Stream<List<int>> _fetchRange(int start, int? end) async* {
    final request = http.Request("GET", url)
      ..headers.addAll(headers)
      ..headers["range"] = "bytes=$start-${end ?? ""}";
    final response = await client.send(request);
    if (response.statusCode != 206) {
      await response.stream.listen(null).cancel();
      throw HttpException("Range request answered with ${response.statusCode}",
          uri: url);
    }
    var offset = start;
    await for (final chunk in response.stream) {
      if (_closed) return;
      final failure = _failure;
      if (failure != null) throw failure;
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      yield await _decrypt(bytes, offset);
      offset += bytes.length;
    }
  }

  /// Stops the download and fails open reads. The copy is the caller's to
  /// delete.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _stop();
    if (!_done.isCompleted) {
      _done.completeError(StateError("closed"));
    }
    _notify();
  }
}

class _HashSink implements Sink<crypto.Digest> {
  crypto.Digest? value;

  @override
  void add(crypto.Digest data) => value = data;

  @override
  void close() {}
}

/// Vommet: serves [MediaStream]s to the video player over HTTP on the
/// loopback interface, with range requests so it can seek. Each stream gets
/// an address with a random 256-bit token: other apps on the device can
/// reach the port but can't guess an address. The server runs only while a
/// stream is registered.
class MediaStreamServer {
  MediaStreamServer._();

  static final MediaStreamServer instance = MediaStreamServer._();

  final Map<String, MediaStream> _streams = {};
  Future<HttpServer>? _server;
  final Random _random = Random.secure();

  /// Whether a server is running (tests).
  bool get running => _server != null;

  /// Registers [stream] and returns the address the player opens.
  /// [extension] (".mp4") helps players that go by the name.
  Future<Uri> register(MediaStream stream, {String? extension}) async {
    final HttpServer server;
    try {
      server = await (_server ??= _bind());
    } catch (_) {
      _server = null;
      rethrow;
    }
    final token = List.generate(32, (_) => _random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, "0"))
        .join();
    _streams[token] = stream;
    return Uri(
        scheme: "http",
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        pathSegments: [token, "media${extension ?? ""}"]);
  }

  /// Closes the stream at [address] and stops the server when it was the
  /// last one.
  Future<void> unregister(Uri address) async {
    final token =
        address.pathSegments.isEmpty ? null : address.pathSegments.first;
    final stream = _streams.remove(token);
    await stream?.close();
    if (_streams.isEmpty) {
      final server = _server;
      _server = null;
      if (server != null) {
        try {
          await (await server).close(force: true);
        } catch (_) {}
      }
    }
  }

  Future<HttpServer> _bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    server.listen((request) {
      _handle(request).catchError((Object error) {
        try {
          request.response.close().ignore();
        } catch (_) {}
      });
    }, onError: (Object _) {});
    return server;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final segments = request.uri.pathSegments;
    final stream = segments.isEmpty ? null : _streams[segments.first];
    if (stream == null ||
        (request.method != "GET" && request.method != "HEAD")) {
      response.statusCode =
          stream == null ? HttpStatus.notFound : HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    await stream.start();
    final total = stream.total;
    final type = stream.contentType;
    if (type != null) {
      response.headers.set(HttpHeaders.contentTypeHeader, type);
    }

    var start = 0;
    int? end;
    if (total != null) {
      response.headers.set(HttpHeaders.acceptRangesHeader, "bytes");
      final range = _parseRange(request.headers.value(HttpHeaders.rangeHeader));
      if (range != null) {
        start = range.$1;
        end = range.$2 == null || range.$2! >= total ? total - 1 : range.$2;
        if (start >= total || start > end!) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers
              .set(HttpHeaders.contentRangeHeader, "bytes */$total");
          await response.close();
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers
            .set(HttpHeaders.contentRangeHeader, "bytes $start-$end/$total");
      } else {
        end = total - 1;
      }
      response.contentLength = end - start + 1;
    }

    if (request.method == "HEAD") {
      await response.close();
      return;
    }
    try {
      await response.addStream(stream.read(start, end));
    } finally {
      await response.close();
    }
  }

  /// `bytes=a-b` or `bytes=a-` (suffix ranges and lists aren't used by the
  /// players and are answered with the whole file).
  static (int, int?)? _parseRange(String? header) {
    if (header == null) return null;
    final match = RegExp(r"^bytes=(\d+)-(\d*)$").firstMatch(header.trim());
    if (match == null) return null;
    final start = int.parse(match.group(1)!);
    final endText = match.group(2)!;
    return (start, endText.isEmpty ? null : int.parse(endText));
  }
}
