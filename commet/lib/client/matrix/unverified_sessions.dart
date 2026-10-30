// Vommet issue 947: sessions that can't read what you send.
//
// With the SDK's default (ShareKeysWith.crossVerifiedIfEnabled), a session
// whose owner has turned on verification but hasn't verified it gets no
// message keys. Nobody used to be told: the other person saw "waiting for
// the key" on every message from Vommet, while Element's got through. Now
// the room warns before you send, names each person and session, and lets
// you send to a session anyway (the SDK's UnverifiedDevices list).
//
// Redesign (10-30): most such sessions are old devices nobody signed out of,
// so the strip only shows in DMs, and only for a session in use (it wrote,
// or asked us for a message key, in the last 30 days). Group rooms mark the
// messages sent from one instead, and room settings list them all. A
// dehydrated device (MSC3814, Element's offline key mailbox) is never listed.

import 'dart:async';
import 'dart:convert';

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

  /// When each session of someone else's last showed it's in use, as
  /// "<our user id>|<user id>|<device id>" → [epoch ms, "asked" | "wrote"].
  static final StringPreference _activity = StringPreference(
      "vommet_unverified_sessions_activity",
      defaultValue: "{}");

  /// How long a key request or a message counts as the session being in use.
  static const activityWindow = Duration(days: 30);

  static Map<String, List<dynamic>>? _activityCache;

  static Map<String, List<dynamic>> get _activityMap {
    if (_activityCache != null) return _activityCache!;
    final map = <String, List<dynamic>>{};
    try {
      final decoded = jsonDecode(_activity.value);
      if (decoded is Map) {
        final oldest =
            DateTime.now().subtract(activityWindow).millisecondsSinceEpoch;
        for (final e in decoded.entries) {
          final v = e.value;
          if (e.key is String &&
              v is List &&
              v.length == 2 &&
              v.first is int &&
              v.first >= oldest &&
              v.last is String) {
            map[e.key] = v;
          }
        }
      }
    } catch (_) {}
    return _activityCache = map;
  }

  /// Notes that [userId]'s session [deviceId] is in use: it [asked] us for
  /// a message key, or wrote, at [at].
  static void noteActivity(
      matrix.Client client, String userId, String deviceId, DateTime at,
      {required bool asked}) {
    if (userId == client.userID) return;
    if (DateTime.now().difference(at) > activityWindow) return;
    final key = "${client.userID}|$userId|$deviceId";
    final map = _activityMap;
    final old = map[key];
    final ms = at.millisecondsSinceEpoch;
    // A newer sign wins; within a minute only a key request replaces a
    // message (it says more: the session tried and failed to read).
    if (old != null &&
        ((old.first as int) >= ms ||
            (ms - (old.first as int) < 60000 && !asked))) {
      return;
    }
    map[key] = [ms, asked ? "asked" : "wrote"];
    unawaited(_activity.set(jsonEncode(map)));
    // Often noted while a message builds: tell listeners after the frame.
    scheduleMicrotask(() {
      for (final state in _rooms.values) {
        if (state.client == client) state.revision.value++;
      }
    });
  }

  /// The latest sign within [activityWindow] that [device] is in use.
  static ({DateTime at, bool asked})? activityOf(
      matrix.Client client, matrix.DeviceKeys device) {
    final v =
        _activityMap["${client.userID}|${device.userId}|${device.deviceId}"];
    if (v == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(v.first as int);
    if (DateTime.now().difference(at) > activityWindow) return null;
    return (at: at, asked: v.last == "asked");
  }

  /// Listens for key requests: a session asking us for a key it never got
  /// is the clearest sign someone is using it and can't read.
  static void watch(matrix.Client client) {
    client.onToDeviceEvent.stream.listen((event) {
      if (event.type != matrix.EventTypes.RoomKeyRequest) return;
      if (event.content["action"] != "request") return;
      final device = event.content["requesting_device_id"];
      if (device is! String) return;
      noteActivity(client, event.sender, device, DateTime.now(), asked: true);
    });
  }

  /// A dehydrated device (MSC3814) holds keys for its owner's next login;
  /// nobody uses or verifies it, so it's never named.
  static bool isDehydrated(matrix.DeviceKeys d) =>
      d.toJson()["dehydrated"] == true ||
      d.deviceDisplayName?.trim() == "Dehydrated device";

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
      final skipped = (await encryption.keyManager.withheldDevicesInRoom(room))
          .where((d) => !isDehydrated(d))
          .toList();
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

  /// The withheld sessions the strip names: only in a DM, only sessions in
  /// use, none unless the setting is Ask, and not the ones the user closed
  /// the warning for.
  List<matrix.DeviceKeys> get shown {
    if (policy != UnverifiedSessionsPolicy.ask) return const [];
    if (!room.isDirectChat) return const [];
    final closed = _dismissed.value.toSet();
    return withheld.value
        .where((d) => !closed.contains("${room.id}|${_deviceKey(d)}"))
        .where((d) => activityOf(client, d) != null)
        .toList();
  }

  /// The withheld session someone's [event] was sent from, for the mark by
  /// its time; null when it came from a session that gets our keys, or the
  /// setting isn't Ask. Notes that session as in use.
  matrix.DeviceKeys? withheldSender(matrix.Event event) {
    if (policy != UnverifiedSessionsPolicy.ask) return null;
    if (event.senderId == client.userID || withheld.value.isEmpty) return null;
    final device = sendingDevice(event);
    if (device == null) return null;
    final key = _deviceKey(device);
    final match = withheld.value.firstWhereOrNull((d) => _deviceKey(d) == key);
    if (match == null) return null;
    if (match.deviceId != null) {
      noteActivity(client, match.userId, match.deviceId!, event.originServerTs,
          asked: false);
    }
    return match;
  }

  /// Notes the withheld sessions that wrote among [events] (newest first;
  /// the first 50 are looked at) as in use.
  void noteWrites(Iterable<matrix.Event> events) {
    if (withheld.value.isEmpty) return;
    for (final event in events.take(50)) {
      withheldSender(event);
    }
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
