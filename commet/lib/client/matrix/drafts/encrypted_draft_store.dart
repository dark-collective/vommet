// Vommet issue 1070: a draft-specific prerequisite, not enabled by the app yet.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'draft_revision.dart';

/// Uses the SDK's SSSS encryption, without its plaintext secret cache or its
/// unbounded OpenSSSS.store sync loop. The JSON is base64-wrapped so the SDK's
/// byte-to-character decrypt conversion cannot corrupt non-ASCII draft text.
abstract class DraftCipher {
  const DraftCipher();
  Future<EncryptedContent> seal(String plain, Uint8List key, String type);
  Future<String> open(EncryptedContent data, Uint8List key, String type);
}

class SsssDraftCipher extends DraftCipher {
  const SsssDraftCipher();
  @override
  Future<EncryptedContent> seal(String plain, Uint8List key, String type) =>
      SSSS.encryptAes(plain, key, type);
  @override
  Future<String> open(EncryptedContent data, Uint8List key, String type) =>
      SSSS.decryptAes(data, key, type);
}

enum DraftProblem { locked, invalid, stale, limit, closed }

class DraftStoreException implements Exception {
  const DraftStoreException(this.problem);
  final DraftProblem problem;
  // Never include text, ciphertext, room identifiers or keys in errors.
  @override
  String toString() => 'DraftStoreException(${problem.name})';
}

/// Instantiate only after per-account opt-in, for a single writer process per
/// Matrix device. The future composer owns debounce, conflict choices and send
/// acknowledgments; this store never sends messages or clears drafts itself.
/// Dispose on account removal. Unacknowledged edits are intentionally RAM-only.
class EncryptedDraftStore {
  EncryptedDraftStore(this.mx, {this.cipher = const SsssDraftCipher()})
      : userId = mx.userID!,
        account = "${mx.homeserver!.origin}\u0000${mx.userID!}",
        writer = mx.deviceID! {
    if (_owners[mx] != null)
      throw const DraftStoreException(DraftProblem.stale);
    _owners[mx] = this;
    for (final event in mx.accountData.values) {
      _adopt(event);
    }
    _sync = mx.onSync.stream.listen((update) {
      for (final event in update.accountData ?? <matrix.BasicEvent>[]) {
        if (event.type == matrix.EventTypes.SecretStorageDefaultKey) {
          if (event.content['key'] != _keyId) lock();
        } else {
          _adopt(event);
        }
      }
    });
    _login = mx.onLoginStateChanged.stream.listen((state) {
      if (state != matrix.LoginState.loggedIn) lock();
    });
  }

  static final _owners = Expando<EncryptedDraftStore>();
  static const prefix = 'im.nether.vommet.draft.v1.';
  static const requestLimit = Duration(seconds: 20);
  final matrix.Client mx;
  final DraftCipher cipher;
  final String account, userId, writer;
  final _events = <String, Map<String, matrix.BasicEvent>>{};
  final _changes = StreamController<String>.broadcast();
  final _decoded = <String, Map<String, DraftRevision>>{};
  final _queues = <String, Future<void>>{};
  late final StreamSubscription<matrix.SyncUpdate> _sync;
  late final StreamSubscription<matrix.LoginState> _login;
  Uint8List? _key;
  String? _keyId;
  int _generation = 0;
  bool _closed = false;

  Stream<String> get changedRooms => _changes.stream;
  bool get isUnlocked => !_closed && _key != null;

  static String _encode(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  static String typeFor(String room, String writer) =>
      '$prefix${_encode(room)}.${_encode(writer)}';

  // Bound sync comparison work before encoding or decrypting any payload.
  static Map<String, Object?> _bounded(Map<String, Object?> content) {
    final encrypted = content['encrypted'];
    if (content.length != 1 || encrypted is! Map || encrypted.length != 1)
      return {};
    final id = encrypted.keys.single;
    final data = encrypted[id];
    if (id is! String || id.length > 255 || data is! Map || data.length != 3)
      return {};
    for (final field in ['iv', 'ciphertext', 'mac']) {
      final limit = field == 'iv'
          ? 24
          : field == 'mac'
              ? 44
              : 65536;
      if (data[field] is! String || (data[field] as String).length > limit)
        return {};
    }
    return {
      'encrypted': {
        id: {
          'iv': data['iv'],
          'ciphertext': data['ciphertext'],
          'mac': data['mac']
        }
      }
    };
  }

  void _adopt(matrix.BasicEvent event) {
    if (_closed || event.type.length > 4096 || !event.type.startsWith(prefix))
      return;
    final parts = event.type.substring(prefix.length).split('.');
    if (parts.length != 2) return;
    String room, device;
    try {
      room = utf8.decode(base64Url.decode(base64Url.normalize(parts[0])));
      device = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    } catch (_) {
      return;
    }
    if (!room.startsWith('!') ||
        room.length > 1024 ||
        device.isEmpty ||
        device.length > 255 ||
        typeFor(room, device) != event.type) return;
    event =
        matrix.BasicEvent(type: event.type, content: _bounded(event.content));
    final bucket = _events.putIfAbsent(room, () => {});
    final previous = bucket[device];
    if (previous != null &&
        jsonEncode(previous.content) == jsonEncode(event.content)) return;
    // Keep at most one overflow sentinel: load/write fails rather than evicting
    // an unsent version. Concurrent new devices can exceed the advertised cap.
    if (bucket.length > DraftRevision.maxWriters &&
        !bucket.containsKey(device)) {
      return;
    }
    bucket[device] = event;
    _changes.add(room);
  }

  Future<String?> _defaultKey() async {
    final value = await mx
        .getAccountData(userId, matrix.EventTypes.SecretStorageDefaultKey)
        .timeout(requestLimit);
    return value['key'] as String?;
  }

  Future<void> unlock(OpenSSSS handle) async {
    if (_closed) throw const DraftStoreException(DraftProblem.closed);
    if (!identical(handle.ssss.client, mx) ||
        !handle.isUnlocked ||
        handle.privateKey?.length != 32 ||
        await _defaultKey() != handle.keyId) {
      throw const DraftStoreException(DraftProblem.locked);
    }
    lock();
    _keyId = handle.keyId;
    _key = Uint8List.fromList(handle.privateKey!);
  }

  void lock() {
    _generation++;
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
    _keyId = null;
    _decoded.clear();
  }

  void _check(int generation) {
    if (_closed) throw const DraftStoreException(DraftProblem.closed);
    if (_key == null ||
        generation != _generation ||
        mx.userID != userId ||
        "${mx.homeserver!.origin}\u0000${mx.userID!}" != account ||
        mx.deviceID != writer ||
        !mx.isLogged()) {
      throw const DraftStoreException(DraftProblem.locked);
    }
  }

  Future<DraftRevision> _open(
    matrix.BasicEvent event,
    String room,
    String device,
    int generation,
  ) async {
    _check(generation);
    try {
      final encrypted = _bounded(event.content)['encrypted'] as Map;
      final data = encrypted[_keyId] as Map;
      for (final field in ['iv', 'ciphertext', 'mac']) {
        if (data[field] is! String || (data[field] as String).length > 65536) {
          throw const FormatException();
        }
      }
      final ascii = await cipher.open(
        EncryptedContent(
          iv: data['iv'],
          ciphertext: data['ciphertext'],
          mac: data['mac'],
        ),
        _key!,
        event.type,
      );
      _check(generation);
      if (ascii.length > 45000) throw const FormatException();
      final bytes = base64.decode(ascii);
      if (bytes.length > DraftRevision.maxRecordBytes) {
        throw const FormatException();
      }
      final record = DraftRevision.fromJson(jsonDecode(utf8.decode(bytes)));
      if (record.account != account ||
          record.room != room ||
          record.writer != device) throw const FormatException();
      return record;
    } on DraftStoreException {
      rethrow;
    } catch (_) {
      throw const DraftStoreException(DraftProblem.invalid);
    }
  }

  /// Reads this room only. One bad/locked/unknown-schema slot blocks the view:
  /// unreadable data must never be interpreted as an empty draft to overwrite.
  Future<DraftView> load(String room) async {
    final generation = _generation;
    _check(generation);
    final events = Map.of(_events[room] ?? <String, matrix.BasicEvent>{});
    if (events.length > DraftRevision.maxWriters) {
      throw const DraftStoreException(DraftProblem.limit);
    }
    final records = <DraftRevision>[];
    for (final entry in events.entries) {
      final record = await _open(entry.value, room, entry.key, generation);
      final known = _decoded[room]?[entry.key];
      final latest =
          known != null && known.revision > record.revision ? known : record;
      (_decoded[room] ??= {})[entry.key] = latest;
      records.add(latest);
    }
    _check(generation);
    return DraftView(account, room, records);
  }

  /// [basedOn] is exactly what the composer saw/resolved, not the latest sync
  /// snapshot. An unseen remote edit remains concurrent. Empty text+reply is a
  /// tombstone; an empty text with a reply remains a real draft.
  Future<DraftRevision> write(
    DraftView basedOn,
    String text, {
    String? replyTo,
  }) {
    final result = Completer<DraftRevision>();
    final generation = _generation;
    final previous = _queues[basedOn.room] ?? Future<void>.value();
    final next = previous.then((_) async {
      try {
        result.complete(await _write(basedOn, text, replyTo, generation));
      } catch (e, s) {
        result.completeError(e, s);
      }
    });
    _queues[basedOn.room] = next;
    unawaited(
      next.then((_) {
        if (identical(_queues[basedOn.room], next))
          _queues.remove(basedOn.room);
      }),
    );
    return result.future;
  }

  Future<DraftRevision> _write(
    DraftView basedOn,
    String text,
    String? replyTo,
    int generation,
  ) async {
    _check(generation);
    if (basedOn.account != account || !basedOn.room.startsWith('!')) {
      throw const DraftStoreException(DraftProblem.invalid);
    }
    if (await _defaultKey() != _keyId) {
      lock();
      throw const DraftStoreException(DraftProblem.locked);
    }
    _check(generation);
    final room = basedOn.room;
    final type = typeFor(room, writer);
    matrix.BasicEvent? fresh;
    try {
      fresh = matrix.BasicEvent(
        type: type,
        content: await mx.getAccountData(userId, type).timeout(requestLimit),
      );
    } on matrix.MatrixException catch (e) {
      if (e.error != matrix.MatrixError.M_NOT_FOUND) rethrow;
    }
    _check(generation);
    final current =
        fresh == null ? null : await _open(fresh, room, writer, generation);
    final observed = basedOn.frontier;
    // Protect a newer local edit, including one acknowledged before its sync
    // echo. A stale send completion must not clear that edit.
    if ((current?.revision ?? 0) != (observed[writer] ?? 0) ||
        (_decoded[room]?[writer]?.revision ?? 0) > (current?.revision ?? 0)) {
      throw const DraftStoreException(DraftProblem.stale);
    }
    final bucket = _events[room] ?? {};
    if (bucket.length > DraftRevision.maxWriters ||
        (!bucket.containsKey(writer) &&
            bucket.length >= DraftRevision.maxWriters) ||
        {...observed.keys, writer}.length > DraftRevision.maxWriters) {
      throw const DraftStoreException(DraftProblem.limit);
    }
    final cleared = text.trim().isEmpty && replyTo == null;
    if (current != null &&
        !basedOn.hasConflict &&
        current.text == (cleared ? '' : text) &&
        current.replyTo == replyTo &&
        current.cleared == cleared) return current;
    final record = DraftRevision(
      account: account,
      room: room,
      writer: writer,
      revision: (current?.revision ?? 0) + 1,
      observed: observed,
      text: cleared ? '' : text,
      replyTo: replyTo,
      cleared: cleared,
    );
    final plain = utf8.encode(jsonEncode(record.toJson()));
    if (plain.length > DraftRevision.maxRecordBytes) {
      throw const DraftStoreException(DraftProblem.limit);
    }
    final encrypted = await cipher.seal(base64.encode(plain), _key!, type);
    _check(generation);
    // Check again after encryption: a reset during a suspended crypto call
    // must not make an old-key upload. The endpoint has no atomic key guard.
    if (await _defaultKey() != _keyId) {
      lock();
      throw const DraftStoreException(DraftProblem.locked);
    }
    _check(generation);
    final content = <String, Object?>{
      'encrypted': {
        _keyId!: {
          'iv': encrypted.iv,
          'ciphertext': encrypted.ciphertext,
          'mac': encrypted.mac,
        },
      },
    };
    await mx.setAccountData(userId, type, content).timeout(requestLimit);
    _check(generation);
    (_decoded[room] ??= {})[writer] = record;
    // Acknowledged writes are available before their later sync echo.
    _adopt(matrix.BasicEvent(type: type, content: content));
    return record;
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    lock();
    await _sync.cancel();
    await _login.cancel();
    _events.clear();
    _owners[mx] = null;
    await _changes.close();
  }
}
