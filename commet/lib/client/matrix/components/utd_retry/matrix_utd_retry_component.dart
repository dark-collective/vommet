// Vommet (issues 32, 100): ask again for the keys of messages that failed to
// decrypt, as soon as asking can succeed, so they decrypt in place without
// "Retry Decrypt", a room switch or a restart.
//
// The SDK asks for a missing key once, when a message first fails to decrypt
// (KeyManager.maybeAutoRequest), and only from the online key backup. While
// this device isn't verified it doesn't ask at all (isUnknownSession), and
// nothing asks again once it is verified or the backup key arrives (only the
// room list's last message is retried then). So messages received before
// verification stayed "Failed to decrypt" until the user retried each one.
//
// This component watches for those two moments and asks again for the
// undecryptable messages of the rooms that are open: from the backup, and
// once the device is verified also from the user's other devices (what
// "Retry Decrypt" does). Keys that arrive re-decrypt the open timelines
// through the SDK (Timeline._sessionKeyReceived), which re-renders them.

import 'dart:async';

import 'package:commet/client/components/component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixUtdRetryComponent implements Component<MatrixClient> {
  @override
  final MatrixClient client;

  /// At most this many sessions are asked for per room and moment, so a
  /// room full of old failures doesn't flood the user's devices.
  static const maxSessionsPerRoom = 50;

  bool? _verified;
  bool _backupCached = false;
  bool _checking = false;
  bool _justVerified = false;
  DateTime? _backupCheckedAt;

  /// Sessions already asked for from other devices / from the backup by this
  /// component, as "room|session".
  final Set<String> _askedDevices = {};
  final Set<String> _askedBackup = {};

  /// [listenToSync] is off in unit tests, which call [check] themselves.
  MatrixUtdRetryComponent(this.client, {bool listenToSync = true}) {
    if (listenToSync) {
      client.matrixClient.onSync.stream.listen((_) => check());
    }
  }

  /// Runs after every sync: asks again when the device has just been
  /// verified or the backup key has just arrived.
  Future<void> check() async {
    if (_checking) return;
    final mx = client.matrixClient;
    final encryption = mx.encryption;
    if (!mx.encryptionEnabled || encryption == null) return;
    _checking = true;
    try {
      final verified = !mx.isUnknownSession;
      if (_verified != verified) {
        Log.i("Undecryptable retry: this device is "
            "${verified ? "verified" : "not verified"}");
      }
      // Kept until a room is open to ask for.
      if (verified && _verified == false) _justVerified = true;
      _verified = verified;

      final timelines = _openTimelines();
      if (timelines.isEmpty) return;

      // Until the backup key is here, looking for it reads the database:
      // at most every 30 s.
      var backupArrived = false;
      final now = DateTime.now();
      if (!_backupCached &&
          (_backupCheckedAt == null ||
              now.difference(_backupCheckedAt!).inSeconds >= 30)) {
        _backupCheckedAt = now;
        final cached = await encryption.keyManager
            .isCached()
            .timeout(const Duration(seconds: 10), onTimeout: () => false);
        if (cached) {
          Log.i("Undecryptable retry: the key backup's key is here");
          _backupCached = true;
          backupArrived = true;
        }
      }
      final becameVerified = _justVerified;
      _justVerified = false;
      if (!becameVerified && !backupArrived) return;

      for (final timeline in timelines) {
        await retry(
          timeline,
          encryption.keyManager,
          fromDevices: verified,
          tryBackup: _backupCached,
        );
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Retrying undecryptable messages failed");
    } finally {
      _checking = false;
    }
  }

  List<matrix.Timeline> _openTimelines() => [
        for (final room in client.rooms)
          if (room is MatrixRoom &&
              (room.timeline as MatrixTimeline?)?.matrixTimeline != null)
            (room.timeline as MatrixTimeline).matrixTimeline!,
      ];

  /// Asks for the keys of [timeline]'s undecryptable messages that this
  /// component hasn't asked for in the same way yet. Returns how many
  /// sessions it asked for.
  Future<int> retry(
    matrix.Timeline timeline,
    KeyManager keyManager, {
    required bool fromDevices,
    required bool tryBackup,
  }) async {
    final room = timeline.room;
    final asked = fromDevices ? _askedDevices : _askedBackup;
    final sessions = undecryptableSessions(timeline.events)
        .where((s) => !asked.contains("${room.id}|${s.sessionId}"))
        .take(maxSessionsPerRoom)
        .toList();
    for (final s in sessions) {
      asked.add("${room.id}|${s.sessionId}");
      if (fromDevices) _askedBackup.add("${room.id}|${s.sessionId}");
      try {
        await keyManager.request(
          room,
          s.sessionId,
          s.senderKey,
          tryOnlineBackup: tryBackup,
          onlineKeyBackupOnly: !fromDevices,
        );
      } catch (e, trace) {
        Log.onError(e, trace, content: "Asking for a room key failed");
      }
    }
    if (sessions.isNotEmpty) {
      Log.i("Asked again for ${sessions.length} room key(s) "
          "(${fromDevices ? "devices and backup" : "backup"})");
    }
    return sessions.length;
  }

  /// The distinct (session, sender key) pairs of [events] that failed to
  /// decrypt and whose key can be asked for.
  static List<({String sessionId, String? senderKey})> undecryptableSessions(
      Iterable<matrix.Event> events) {
    final seen = <String>{};
    final result = <({String sessionId, String? senderKey})>[];
    for (final e in events) {
      if (e.type != matrix.EventTypes.Encrypted) continue;
      if (e.content['can_request_session'] != true) continue;
      final sessionId = e.content.tryGet<String>('session_id');
      if (sessionId == null || !seen.add(sessionId)) continue;
      result.add((
        sessionId: sessionId,
        senderKey: e.content.tryGet<String>('sender_key'),
      ));
    }
    return result;
  }
}
