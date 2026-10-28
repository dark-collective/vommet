import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Vommet: how media from encrypted rooms is kept in the file cache.
///
/// Entries are sealed with XChaCha20-Poly1305 (the `cryptography`
/// package's Dart implementation; no hand-rolled primitives) under a
/// 256-bit key derived with HKDF-SHA256 from the cache's master key. File
/// names and database rows use an HMAC-SHA256 of the identifier under a
/// second derived key, so neither shows which media is cached.
///
/// A sealed file ("VME2") is a header, then the media in segments of
/// [segmentLength] bytes (the last one shorter, or empty for empty media),
/// each sealed on its own with its 16-byte tag after it:
///
///     "VME2" | media type (1) | nonce prefix (16) | segment 0 | segment 1 ...
///
/// Segment i's nonce is the file's random prefix followed by i (64-bit big
/// endian), so no two segments of any file share a nonce. Its associated
/// data binds the header, i, whether it is the last segment and the entry's
/// identifier: a file moved to another entry's name, changed in any byte,
/// cut short (even at a segment boundary), extended or with segments
/// swapped fails to open (a cache miss, never wrong media). Segments let a
/// big video be sealed and opened in bounded memory, file to file. The media
/// type ([CachedMediaType] index) stays readable for the storage page's
/// per-type usage and "clear images/videos".
class MediaCacheCrypto {
  static const List<int> magic = [0x56, 0x4D, 0x45, 0x32]; // "VME2"
  static const int prefixLength = 16;
  static const int nonceLength = 24;
  static const int tagLength = 16;
  static const int headerLength = 4 + 1 + prefixLength;
  static const int segmentLength = 64 * 1024;
  static const int sealedSegmentLength = segmentLength + tagLength;

  /// Sealed files are named this followed by the hex HMAC.
  static const String fileNamePrefix = "e1_";

  /// Database rows of sealed entries use this followed by the hex HMAC.
  static const String rowIdPrefix = "enc1:";

  /// Entries this size or larger are sealed and opened in an isolate of
  /// their own, streaming segment by segment, so a big video neither holds
  /// up the thumbnails behind it in the shared worker nor needs a second
  /// copy of itself in memory.
  static const int ownIsolateBytes = 1024 * 1024;

  static const String _encInfo = "vommet media cache v1 encryption";
  static const String _nameInfo = "vommet media cache v1 names";
  static const String _checkInfo = "vommet media cache v1 key check";

  MediaCacheCrypto._(this.encryptionKey, this._names, this.keyCheck);

  /// The sealing key (never leaves the process).
  final Uint8List encryptionKey;
  final crypto.Hmac _names;

  /// A value derived from the master key, kept next to the cache to tell
  /// whether its entries were sealed under this key (a lost, replaced or
  /// rotated key means they can't be opened and are wiped).
  final String keyCheck;

  static Future<MediaCacheCrypto> fromMasterKey(List<int> master) async {
    if (master.length != 32) {
      throw ArgumentError("The media cache key must be 32 bytes");
    }
    final hkdf = DartHkdf(hmac: DartHmac.sha256(), outputLength: 32);
    Future<Uint8List> derive(String info) async {
      final key = await hkdf.deriveKey(
          secretKey: SecretKeyData(master), info: utf8.encode(info));
      return Uint8List.fromList(await key.extractBytes());
    }

    final enc = await derive(_encInfo);
    final names = await derive(_nameInfo);
    final check = await derive(_checkInfo);
    return MediaCacheCrypto._(
        enc, crypto.Hmac(crypto.sha256, names), _hex(check.sublist(0, 16)));
  }

  /// The keyed hash of [identifier] that names its file and row.
  String hashOf(String identifier) =>
      _names.convert(utf8.encode(identifier)).toString();

  String fileNameOf(String identifier) =>
      "$fileNamePrefix${hashOf(identifier)}";

  String rowIdOf(String identifier) => "$rowIdPrefix${hashOf(identifier)}";

  /// The media type byte of a sealed file, or null if [head] isn't one.
  static int? typeOf(List<int> head) {
    if (head.length < 5) return null;
    for (var i = 0; i < magic.length; i++) {
      if (head[i] != magic[i]) return null;
    }
    return head[4];
  }

  /// The size of [plainLength] bytes once sealed.
  static int sealedLengthOf(int plainLength) {
    final segments = plainLength == 0
        ? 1
        : (plainLength + segmentLength - 1) ~/ segmentLength;
    return headerLength + plainLength + segments * tagLength;
  }

  /// The size of the media in a sealed file of [sealedLength] bytes, or null
  /// when no sealed file has that size.
  static int? plainLengthOf(int sealedLength) {
    final body = sealedLength - headerLength;
    if (body < tagLength) return null;
    final segments = (body + sealedSegmentLength - 1) ~/ sealedSegmentLength;
    final last = body - (segments - 1) * sealedSegmentLength;
    if (last < tagLength) return null;
    // Only empty media has an empty segment, and then only one.
    if (last == tagLength && segments > 1) return null;
    return body - segments * tagLength;
  }

  static final Random _random = Random.secure();

  static final Cipher _cipher = DartXchacha20.poly1305Aead();

  static Uint8List _nonce(Uint8List header, int index) {
    final nonce = Uint8List(nonceLength);
    nonce.setRange(0, prefixLength, header, 5);
    ByteData.sublistView(nonce).setUint64(prefixLength, index);
    return nonce;
  }

  static Uint8List _aad(
      Uint8List header, List<int> identifier, int index, bool last) {
    final aad = Uint8List(headerLength + 9 + identifier.length);
    aad.setRange(0, headerLength, header);
    ByteData.sublistView(aad).setUint64(headerLength, index);
    aad[headerLength + 8] = last ? 1 : 0;
    aad.setRange(headerLength + 9, aad.length, identifier);
    return aad;
  }

  /// [plain] sealed for [identifier], in memory (for small entries). Runs
  /// wherever it is called; see [MediaCacheWorker] to keep it off the UI
  /// isolate.
  static Future<Uint8List> seal(
      Uint8List key, String identifier, int type, Uint8List plain) async {
    final out = Uint8List(sealedLengthOf(plain.length));
    final sealer = MediaCacheSealer(key, identifier, type);
    var at = 0;
    void put(Uint8List bytes) {
      out.setRange(at, at + bytes.length, bytes);
      at += bytes.length;
    }

    put(sealer.header);
    for (final segment in await sealer.add(plain)) {
      put(segment);
    }
    put(await sealer.close());
    if (at != out.length) throw StateError("Unexpected sealed length");
    return out;
  }

  /// The media in [sealed] if it is [identifier]'s entry sealed under [key];
  /// null for anything else (wrong key, another entry's file, a changed,
  /// cut-short, extended or reordered file). Never throws.
  static Future<Uint8List?> open(
      Uint8List key, String identifier, Uint8List sealed) async {
    final plainLength = plainLengthOf(sealed.length);
    if (plainLength == null) return null;
    final out = Uint8List(plainLength);
    var readAt = 0;
    var writeAt = 0;
    final ok = await openSegments(key, identifier, sealed.length, (length) {
      final bytes = Uint8List.sublistView(sealed, readAt, readAt + length);
      readAt += length;
      return bytes;
    }, (plain) {
      out.setRange(writeAt, writeAt + plain.length, plain);
      writeAt += plain.length;
    });
    return ok ? out : null;
  }

  /// Opens a sealed entry of [sealedLength] bytes segment by segment: [read]
  /// gives the next bytes of the sealed file (never asked for more than a
  /// segment at a time), [write] takes the media one segment at a time. At
  /// most a segment of each is held, whatever the file's size. False (after
  /// some segments may already have gone to [write]: the caller discards
  /// them) when the file isn't [identifier]'s entry sealed under [key].
  /// Never throws for a bad file; errors of [read] and [write] pass through.
  static Future<bool> openSegments(
    Uint8List key,
    String identifier,
    int sealedLength,
    FutureOr<Uint8List> Function(int length) read,
    FutureOr<void> Function(Uint8List plain) write,
  ) async {
    if (plainLengthOf(sealedLength) == null) return false;
    final header = await read(headerLength);
    if (header.length != headerLength || typeOf(header) == null) return false;
    final headerCopy = Uint8List.fromList(header);
    final secretKey = SecretKeyData(key);
    final id = utf8.encode(identifier);

    var remaining = sealedLength - headerLength;
    var index = 0;
    while (remaining > 0) {
      final length = min(remaining, sealedSegmentLength);
      final last = length == remaining;
      final segment = await read(length);
      if (segment.length != length) return false;
      final Uint8List plain;
      try {
        final decrypted = await _cipher.decrypt(
            SecretBox(Uint8List.sublistView(segment, 0, length - tagLength),
                nonce: _nonce(headerCopy, index),
                mac: Mac(Uint8List.sublistView(segment, length - tagLength))),
            secretKey: secretKey,
            aad: _aad(headerCopy, id, index, last));
        plain =
            decrypted is Uint8List ? decrypted : Uint8List.fromList(decrypted);
      } catch (_) {
        return false;
      }
      await write(plain);
      remaining -= length;
      index++;
    }
    return true;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, "0")).join();
}

/// Vommet: seals media for the cache a piece at a time: write [header],
/// then whatever [add] returns as the media comes in, then what [close]
/// returns. It holds at most one segment of media, so it never needs the
/// whole file at once, and it doesn't need to know the size up front (the
/// last full segment is only sealed, as the last one, at [close]).
class MediaCacheSealer {
  MediaCacheSealer(Uint8List key, String identifier, this.type)
      : _key = SecretKeyData(key),
        _identifier = utf8.encode(identifier),
        header = Uint8List(MediaCacheCrypto.headerLength) {
    header.setRange(0, 4, MediaCacheCrypto.magic);
    header[4] = type;
    for (var i = 5; i < MediaCacheCrypto.headerLength; i++) {
      header[i] = MediaCacheCrypto._random.nextInt(256);
    }
  }

  final int type;
  final SecretKeyData _key;
  final List<int> _identifier;

  /// The sealed file's first bytes.
  final Uint8List header;

  final Uint8List _pending = Uint8List(MediaCacheCrypto.segmentLength);
  int _filled = 0;
  int _index = 0;
  bool _closed = false;

  /// Takes the next [data]; returns the segments now sealed, in order.
  Future<List<Uint8List>> add(List<int> data) async {
    if (_closed) throw StateError("Sealer closed");
    final out = <Uint8List>[];
    var at = 0;
    while (at < data.length) {
      if (_filled == _pending.length) {
        // More media follows the full segment, so it isn't the last.
        out.add(await _seal(_pending, false));
        _filled = 0;
      }
      final take = min(data.length - at, _pending.length - _filled);
      _pending.setRange(_filled, _filled + take, data, at);
      _filled += take;
      at += take;
    }
    return out;
  }

  /// The last segment (empty media still gets one).
  Future<Uint8List> close() async {
    if (_closed) throw StateError("Sealer closed");
    _closed = true;
    return _seal(Uint8List.sublistView(_pending, 0, _filled), true);
  }

  Future<Uint8List> _seal(Uint8List plain, bool last) async {
    final index = _index++;
    final box = await MediaCacheCrypto._cipher.encrypt(plain,
        secretKey: _key,
        nonce: MediaCacheCrypto._nonce(header, index),
        aad: MediaCacheCrypto._aad(header, _identifier, index, last));
    final tag = box.mac.bytes;
    if (tag.length != MediaCacheCrypto.tagLength) {
      throw StateError("Unexpected tag length");
    }
    final out = Uint8List(box.cipherText.length + tag.length);
    out.setRange(0, box.cipherText.length, box.cipherText);
    out.setRange(box.cipherText.length, out.length, tag);
    return out;
  }
}

/// Vommet: seals and opens cache entries off the UI isolate.
///
/// Small entries go through one long-lived worker isolate (a screen of
/// thumbnails doesn't pay an isolate start each). They cross as
/// [TransferableTypedData], which copies them once on the way in and once
/// on the way out (cheap at this size). If the worker can't start, the work
/// runs where it was asked for.
///
/// Big entries ([MediaCacheCrypto.ownIsolateBytes] and up) each get an
/// isolate of their own that reads and writes the files itself, segment by
/// segment: opening one to a file holds about a segment in memory whatever
/// its size; opening one to bytes holds the result once (it is handed back
/// with [Isolate.exit], not copied); sealing one is fed the media
/// [feedChunk] bytes at a time, so the media is never copied whole.
class MediaCacheWorker {
  SendPort? _port;
  Future<SendPort?>? _starting;
  RawReceivePort? _receive;
  Isolate? _isolate;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  bool _closed = false;

  /// How much media one message to a sealing isolate carries.
  static const int feedChunk = 16 * MediaCacheCrypto.segmentLength;

  /// [plain] sealed in memory, for a small entry.
  Future<Uint8List> seal(
      Uint8List key, String identifier, int type, Uint8List plain) async {
    final result = await _run(0, key, identifier, type, plain);
    if (result is TransferableTypedData) {
      return result.materialize().asUint8List();
    }
    if (identical(result, _inline)) {
      return MediaCacheCrypto.seal(key, identifier, type, plain);
    }
    throw StateError("Media cache sealing failed: $result");
  }

  /// A small sealed entry opened in memory (null if it doesn't open).
  Future<Uint8List?> open(
      Uint8List key, String identifier, Uint8List sealed) async {
    final result = await _run(1, key, identifier, 0, sealed);
    if (result is TransferableTypedData) {
      return result.materialize().asUint8List();
    }
    if (identical(result, _inline)) {
      return MediaCacheCrypto.open(key, identifier, sealed);
    }
    return null;
  }

  /// Seals [plain] into [outPath] (created or truncated), in an isolate of
  /// its own fed [feedChunk] bytes at a time (each once the one before is
  /// written). Throws on failure; [outPath] may then hold part of the file.
  static Future<void> sealToFile(Uint8List key, String identifier, int type,
      Uint8List plain, String outPath) async {
    final replies = ReceivePort();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(_sealToFileMain,
          <Object?>[replies.sendPort, key, identifier, type, outPath],
          debugName: "media cache seal",
          onExit: replies.sendPort,
          onError: replies.sendPort,
          errorsAreFatal: true);
      final messages = StreamIterator(replies);
      SendPort? feed;
      var at = 0;
      var fed = false;
      while (await messages.moveNext()) {
        final message = messages.current;
        if (message is SendPort) {
          feed = message;
        } else if (message == true) {
          return;
        } else if (message != "next") {
          throw StateError("Media cache sealing failed: $message");
        }
        if (fed || feed == null) continue;
        if (at == plain.length) {
          feed.send(null);
          fed = true;
          continue;
        }
        final end = min(at + feedChunk, plain.length);
        feed.send(TransferableTypedData.fromList(
            [Uint8List.sublistView(plain, at, end)]));
        at = end;
      }
      throw StateError("Media cache sealing stopped");
    } finally {
      replies.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }

  static Future<void> _sealToFileMain(List<Object?> args) async {
    final reply = args[0] as SendPort;
    final sealer = MediaCacheSealer(
        args[1] as Uint8List, args[2] as String, args[3] as int);
    final out = await File(args[4] as String).open(mode: FileMode.writeOnly);
    try {
      await out.writeFrom(sealer.header);
      final chunks = ReceivePort();
      final incoming = StreamIterator(chunks);
      reply.send(chunks.sendPort);
      while (await incoming.moveNext()) {
        final chunk = incoming.current;
        if (chunk == null) break;
        final data = (chunk as TransferableTypedData).materialize();
        for (final segment in await sealer.add(data.asUint8List())) {
          await out.writeFrom(segment);
        }
        reply.send("next");
      }
      chunks.close();
      await out.writeFrom(await sealer.close());
      await out.flush();
    } finally {
      await out.close();
    }
    reply.send(true);
  }

  /// Opens the sealed file [sealedPath] into the existing file [outPath]
  /// (truncated first, its permissions kept), streaming in an isolate of its
  /// own. False when the file doesn't open; [outPath] may then hold part of
  /// the media and must be deleted. Throws on I/O errors.
  static Future<bool> openToFile(
      Uint8List key, String identifier, String sealedPath, String outPath) {
    return Isolate.run(
        () => openFileToFile(key, identifier, sealedPath, outPath),
        debugName: "media cache open");
  }

  /// [openToFile]'s work, wherever it is called.
  static Future<bool> openFileToFile(Uint8List key, String identifier,
      String sealedPath, String outPath) async {
    final input = await File(sealedPath).open();
    try {
      final output = await File(outPath).open(mode: FileMode.writeOnly);
      try {
        final ok = await MediaCacheCrypto.openSegments(
            key,
            identifier,
            await input.length(),
            (length) => input.read(length),
            (plain) => output.writeFrom(plain));
        await output.flush();
        return ok;
      } finally {
        await output.close();
      }
    } finally {
      await input.close();
    }
  }

  /// The media in the sealed file [sealedPath], opened in an isolate of its
  /// own (null if it doesn't open). Holds the media once, plus a segment.
  static Future<Uint8List?> openFileToBytes(
      Uint8List key, String identifier, String sealedPath) {
    return Isolate.run(() async {
      final input = await File(sealedPath).open();
      try {
        final sealedLength = await input.length();
        final plainLength = MediaCacheCrypto.plainLengthOf(sealedLength);
        if (plainLength == null) return null;
        final out = Uint8List(plainLength);
        var at = 0;
        final ok = await MediaCacheCrypto.openSegments(
            key, identifier, sealedLength, (length) => input.read(length),
            (plain) {
          out.setRange(at, at + plain.length, plain);
          at += plain.length;
        });
        return ok ? out : null;
      } finally {
        await input.close();
      }
    }, debugName: "media cache open");
  }

  /// Answer meaning "no worker: do it here".
  static final Object _inline = Object();

  Future<Object?> _run(int op, Uint8List key, String identifier, int type,
      Uint8List data) async {
    final port = await _start();
    if (port == null) return _inline;
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    port.send([
      id,
      op,
      key,
      identifier,
      type,
      TransferableTypedData.fromList([data]),
    ]);
    return completer.future;
  }

  Future<SendPort?> _start() {
    if (_closed) return Future.value(null);
    if (_port != null) return Future.value(_port);
    return _starting ??= _spawn();
  }

  Future<SendPort?> _spawn() async {
    final ready = Completer<SendPort?>();
    final receive = RawReceivePort();
    receive.handler = (Object? message) {
      if (message is SendPort) {
        _port = message;
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is List && message.length == 2 && message[0] is int) {
        _pending.remove(message[0])?.complete(message[1]);
      } else if (message == null) {
        // The worker exited or failed: everything waiting runs inline.
        _port = null;
        _starting = null;
        _isolate = null;
        if (!ready.isCompleted) ready.complete(null);
        final waiting = List.of(_pending.values);
        _pending.clear();
        for (final completer in waiting) {
          completer.complete(_inline);
        }
      }
      // Other messages are the worker's uncaught errors; its exit follows.
    };
    _receive = receive;
    try {
      _isolate = await Isolate.spawn(_workerMain, receive.sendPort,
          debugName: "media cache crypto",
          onExit: receive.sendPort,
          onError: receive.sendPort,
          errorsAreFatal: true);
    } catch (_) {
      receive.close();
      _receive = null;
      _starting = null;
      return null;
    }
    return ready.future;
  }

  /// Stops the worker; later work runs inline.
  void close() {
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receive?.close();
    _receive = null;
    _port = null;
    final waiting = List.of(_pending.values);
    _pending.clear();
    for (final completer in waiting) {
      completer.complete(_inline);
    }
  }

  static void _workerMain(SendPort reply) {
    final port = RawReceivePort();
    port.handler = (Object? message) async {
      final job = message as List;
      final id = job[0] as int;
      try {
        final op = job[1] as int;
        final key = job[2] as Uint8List;
        final identifier = job[3] as String;
        final type = job[4] as int;
        final data =
            (job[5] as TransferableTypedData).materialize().asUint8List();
        final Uint8List? out = op == 0
            ? await MediaCacheCrypto.seal(key, identifier, type, data)
            : await MediaCacheCrypto.open(key, identifier, data);
        reply.send([
          id,
          out == null ? null : TransferableTypedData.fromList([out])
        ]);
      } catch (error) {
        reply.send([id, error.toString()]);
      }
    };
    reply.send(port.sendPort);
  }
}
