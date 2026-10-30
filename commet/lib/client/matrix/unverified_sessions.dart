// Vommet issue 947: sessions that can't read what you send.
//
// With the SDK's default (ShareKeysWith.crossVerifiedIfEnabled), a session
// whose owner has turned on verification but hasn't verified it gets no
// message keys. Nobody used to be told: the other person saw "waiting for
// the key" on every message from Vommet, while Element's got through. Now
// the room warns before you send, names each person and session, and lets
// you send to a session anyway (the SDK's UnverifiedDevices list).

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/main.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/session_key.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Settings › Security › Sessions their owner hasn't verified.
enum UnverifiedSessionsPolicy {
  /// Warn above the message box and let the user choose per session.
  ask,

  /// Send to them too, like Element. Blocked sessions are still skipped.
  always,

  /// Don't send to them, and don't warn (the SDK's default before 947).
  never;

  static UnverifiedSessionsPolicy parse(String value) =>
      values.firstWhereOrNull((p) => p.name == value) ?? ask;
}

class UnverifiedSessions {
  static final StringPreference _policy =
      StringPreference("vommet_unverified_sessions", defaultValue: "ask");

  /// Sessions the user closed the warning for ("Not now"), as
  /// "<room id>|<user id>|<device id>|<ed25519 key>": a new session, or
  /// the same one with other keys, brings the warning back.
  static final StringListPreference _dismissed = StringListPreference(
      "vommet_unverified_sessions_dismissed",
      defaultValue: []);

  static UnverifiedSessionsPolicy get policy =>
      UnverifiedSessionsPolicy.parse(_policy.value);

  static Stream<String> get onPolicyChanged => _policy.onChanged;

  static Future<void> setPolicy(UnverifiedSessionsPolicy value) async {
    await _policy.set(value.name);
    for (final client in clientManager?.clients ?? const []) {
      if (client is MatrixClient) apply(client.getMatrixClient());
    }
    for (final room in _rooms.values) {
      unawaited(room.refresh());
    }
  }

  /// Sets [client]'s key sharing to the user's choice.
  static void apply(matrix.Client client) {
    client.shareKeysWith = policy == UnverifiedSessionsPolicy.always
        ? matrix.ShareKeysWith.all
        : matrix.ShareKeysWith.crossVerifiedIfEnabled;
  }

  static final Map<String, UnverifiedSessions> _rooms = {};

  /// The state of [room], shared by its banner and its messages' notes.
  static UnverifiedSessions of(MatrixRoom room) {
    final key = "${room.client.identifier}|${room.matrixRoom.id}";
    return _rooms[key] ??= UnverifiedSessions._(room.matrixRoom);
  }

  UnverifiedSessions._(this.room);

  final matrix.Room room;
  matrix.Client get client => room.client;
  UnverifiedDevices? get _allowList => client.encryption?.unverifiedDevices;

  /// The sessions of the room's members that our keys skip now.
  final ValueNotifier<List<matrix.DeviceKeys>> withheld = ValueNotifier([]);

  /// Sessions here the user chose to send to: they can't read what was sent
  /// before that.
  List<matrix.DeviceKeys> _allowed = const [];

  /// Bumped whenever [withheld] or the allowed sessions change, for the
  /// messages' notes.
  final ValueNotifier<int> revision = ValueNotifier(0);

  Future<void>? _refreshing;
  DateTime? _refreshedAt;

  /// Looks the room's sessions up again. Each member's keys are fetched at
  /// most once a minute (the SDK limits it), but a room open, a member change
  /// and a choice each want a fresh look.
  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() {
        _refreshing = null;
      });

  Timer? _trailing;

  /// [refresh], at most every 30 seconds: a call inside that window looks
  /// again when it ends, so a session that shows up meanwhile isn't missed.
  void refreshIfStale() {
    final at = _refreshedAt;
    final wait = at == null
        ? Duration.zero
        : const Duration(seconds: 30) - DateTime.now().difference(at);
    if (wait <= Duration.zero) {
      unawaited(refresh());
      return;
    }
    _trailing ??= Timer(wait, () {
      _trailing = null;
      unawaited(refresh());
    });
  }

  Future<void> _refresh() async {
    final encryption = client.encryption;
    if (!room.encrypted || encryption == null) {
      _set(const [], const []);
      return;
    }
    try {
      final skipped = await encryption.keyManager.withheldDevicesInRoom(room);
      final allowList = _allowList;
      final allowed = allowList == null
          ? const <matrix.DeviceKeys>[]
          : (await room.getUserDeviceKeys())
              .where((d) => allowList.isAllowed(d))
              .toList();
      _refreshedAt = DateTime.now();
      _set(skipped, allowed);
    } catch (e, s) {
      matrix.Logs().w("[UnverifiedSessions] Could not check ${room.id}", e, s);
    }
  }

  void _set(List<matrix.DeviceKeys> skipped, List<matrix.DeviceKeys> allowed) {
    String ids(Iterable<matrix.DeviceKeys> list) =>
        list.map(_deviceKey).join(",");
    if (ids(skipped) == ids(withheld.value) && ids(allowed) == ids(_allowed)) {
      return;
    }
    _allowed = allowed;
    withheld.value = skipped;
    revision.value++;
  }

  static String _deviceKey(matrix.DeviceKeys d) =>
      "${d.userId}|${d.deviceId}|${d.ed25519Key}";

  /// The withheld sessions the banner names: none unless the setting is Ask,
  /// and not the ones the user closed the warning for.
  List<matrix.DeviceKeys> get shown {
    if (policy != UnverifiedSessionsPolicy.ask) return const [];
    final closed = _dismissed.value.toSet();
    return withheld.value
        .where((d) => !closed.contains("${room.id}|${_deviceKey(d)}"))
        .toList();
  }

  /// "Not now": hides the warning for [devices] in this room.
  Future<void> dismiss(List<matrix.DeviceKeys> devices) async {
    await _dismissed.set({
      ..._dismissed.value,
      for (final d in devices) "${room.id}|${_deviceKey(d)}",
    }.toList());
    revision.value++;
  }

  /// Sends our keys to [devices] from now on, in every room we share with
  /// their owners.
  Future<void> allow(List<matrix.DeviceKeys> devices) async {
    final allowList = _allowList;
    if (allowList == null) return;
    for (final device in devices) {
      await allowList.allow(device);
    }
    for (final state in _rooms.values) {
      if (state.client == client) unawaited(state.refresh());
    }
  }

  /// The sessions withheld now, or allowed since, that never got the key of
  /// our message [event]: they can't read it. Empty for anyone else's
  /// message, an unencrypted one, or one whose key we no longer have.
  List<matrix.DeviceKeys> cantRead(matrix.Event event) {
    if (event.senderId != client.userID) return const [];
    if (policy == UnverifiedSessionsPolicy.never) return const [];
    final candidates = [...withheld.value, ..._allowed];
    if (candidates.isEmpty) return const [];
    final inbound = _inboundSession(event);
    if (inbound == null) return const [];
    return candidates
        .where(
            (d) => inbound.allowedAtIndex[d.userId]?[d.curve25519Key] == null)
        .toList();
  }

  /// The session someone's [event] was sent from, if we know its keys.
  matrix.DeviceKeys? sendingDevice(matrix.Event event) {
    final inbound = _inboundSession(event);
    if (inbound == null) return null;
    return client.userDeviceKeys[event.senderId]?.deviceKeys.values
        .firstWhereOrNull((d) => d.curve25519Key == inbound.senderKey);
  }

  /// [userId]'s newest message among [events] (newest first) and the session
  /// it came from, or null if they haven't written there.
  ({matrix.DeviceKeys? device, DateTime time})? lastSession(
      String userId, Iterable<matrix.Event> events) {
    final event = events.firstWhereOrNull((e) =>
        e.senderId == userId &&
        e.originalSource?.type == matrix.EventTypes.Encrypted);
    if (event == null) return null;
    return (device: sendingDevice(event), time: event.originServerTs);
  }

  SessionKey? _inboundSession(matrix.Event event) {
    final content = event.originalSource?.content;
    if (event.originalSource?.type != matrix.EventTypes.Encrypted) {
      return null;
    }
    final sessionId = content?.tryGet<String>("session_id");
    if (sessionId == null) return null;
    return client.encryption?.keyManager
        .getInboundGroupSession(room.id, sessionId);
  }
}
