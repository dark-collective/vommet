import 'dart:async';
import 'dart:io';

import 'package:commet/client/components/room_call/room_call_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/matrix/components/matrix_sync_listener.dart';
import 'package:commet/client/matrix/components/room_call/matrix_room_call_invite.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// Vommet: joins a MatrixRTC call (Element Call / Element X) in a room that
/// isn't a voice room. The join itself is the voice-room one
/// ([MatrixLivekitBackend]): same membership, SFU and media keys.
class MatrixRoomCallComponent
    implements
        RoomCallComponent<MatrixClient, MatrixRoom>,
        MatrixRoomSyncListener {
  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  late final MatrixLivekitBackend backend = MatrixLivekitBackend(room);

  MatrixRoomCallComponent(this.client, this.room);

  final StreamController<void> _onParticipantsChanged =
      StreamController.broadcast();

  @override
  Stream<void> get onParticipantsChanged => _onParticipantsChanged.stream;

  @override
  void onSync(JoinedRoomUpdate update) {
    final events = [
      ...?update.timeline?.events,
      ...?update.state,
    ];
    if (events
        .any((e) => e.type == MatrixVoipRoomComponent.callMemberStateEvent)) {
      _onParticipantsChanged.add(null);
    }

    if (preferences.experimentRoomCalls.value) {
      for (final e in update.timeline?.events ?? <MatrixEvent>[]) {
        _maybeRing(e);
      }
    }
  }

  final Set<String> _rungFor = {};

  void _maybeRing(MatrixEvent e) {
    final ring = ringDuration(
      type: e.type,
      content: e.content,
      sender: e.senderId,
      self: client.matrixClient.userID ?? "",
      sent: e.originServerTs,
      now: DateTime.now(),
    );
    if (ring == null || !_rungFor.add(e.eventId)) return;
    final calls = clientManager?.callManager;
    if (calls == null || calls.getCallInRoom(client, room.identifier) != null) {
      return;
    }
    calls.onClientSessionStarted(MatrixRoomCallInvite(this,
        eventId: e.eventId, callerId: e.senderId, ring: ring));
  }

  static const rtcNotificationEvent = "org.matrix.msc4075.rtc.notification";

  /// MSC4075: how much longer [type]/[content] should ring us, or null if it
  /// shouldn't (not a ring, ours, or already over). Both the original
  /// `call.notify` (`notify_type`) and the newer `rtc.notification`
  /// (`notification_type`, `sender_ts`, `lifetime`) are understood.
  static Duration? ringDuration({
    required String type,
    required Map<String, dynamic> content,
    required String sender,
    required String self,
    required DateTime sent,
    required DateTime now,
  }) {
    if (type != callNotifyEvent && type != rtcNotificationEvent) return null;
    if (sender == self) return null;
    final kind = content["notify_type"] ?? content["notification_type"];
    if (kind != "ring") return null;
    final lifetime = content["lifetime"] is int
        ? Duration(milliseconds: (content["lifetime"] as int).clamp(0, 120000))
        : const Duration(seconds: 30);
    final senderTs = content["sender_ts"];
    final start =
        senderTs is int ? DateTime.fromMillisecondsSinceEpoch(senderTs) : sent;
    final left = start.add(lifetime).difference(now);
    if (left <= Duration.zero) return null;
    return left > lifetime ? lifetime : left;
  }

  /// A membership counts while it has content, is for a room-wide `m.call`,
  /// and hasn't passed its `expires` (a crashed client leaves its membership
  /// behind, and the chat would otherwise show a call that isn't there).
  static bool isLiveMembership(
      Map<String, dynamic> content, DateTime originServerTs, DateTime now) {
    if (content.isEmpty) return false;
    final application = content["application"];
    if (application != null && application != "m.call") return false;
    final scope = content["scope"];
    if (scope != null && scope != "m.room") return false;
    final expires = content["expires"];
    if (expires is int &&
        originServerTs.add(Duration(milliseconds: expires)).isBefore(now)) {
      return false;
    }
    return true;
  }

  @override
  List<String> getCurrentParticipants() {
    final state =
        room.matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent];
    if (state == null) return [];

    final now = DateTime.now();
    final participants = <String>[];
    for (final event in state.values) {
      if (event is! Event) continue;
      if (!isLiveMembership(event.content, event.originServerTs, now)) {
        continue;
      }
      if (!participants.contains(event.senderId)) {
        participants.add(event.senderId);
      }
    }
    return participants;
  }

  @override
  bool get canJoinCall => room.matrixRoom
      .canChangeStateEvent(MatrixVoipRoomComponent.callMemberStateEvent);

  @override
  RoomCallPermissions get permissions {
    final r = room.matrixRoom;
    final required = r.powerForChangingStateEvent(
        MatrixVoipRoomComponent.callMemberStateEvent);
    final me = r.client.userID;
    final joined = r.getParticipants([Membership.join]);
    var othersBlocked = joined
        .any((u) => u.id != me && r.getPowerLevelByUserId(u.id) < required);
    // Members not loaded yet (lazy loading) sit at the default level.
    final total = r.summary.mJoinedMemberCount;
    if (!othersBlocked && total != null && total > joined.length) {
      othersBlocked = _usersDefault(r) < required;
    }
    return RoomCallPermissions(
        requiredLevel: required,
        ownLevel: r.ownPowerLevel,
        canChangePermissions: r.canChangePowerLevel,
        othersBlocked: othersBlocked);
  }

  static int _usersDefault(Room r) {
    final value =
        r.getState(EventTypes.RoomPowerLevels)?.content["users_default"];
    return value is int ? value : 0;
  }

  @override
  Future<void> letEveryoneJoin() async {
    final r = room.matrixRoom;
    final content = Map<String, Object?>.from(
        r.getState(EventTypes.RoomPowerLevels)?.content ?? const {});
    final events = Map<String, Object?>.from(
        (content["events"] as Map?)?.cast<String, Object?>() ?? const {});
    events[MatrixVoipRoomComponent.callMemberStateEvent] = _usersDefault(r);
    content["events"] = events;
    await r.client
        .setRoomStateWithKey(r.id, EventTypes.RoomPowerLevels, "", content);
  }

  @override
  Future<VoipSession?> joinCall() async {
    try {
      return await backend.join();
    } catch (e) {
      // Same as voice rooms: a dropped connection fails the first try.
      if (!_isTransientNetworkError(e)) rethrow;
      Log.w("Joining the call failed (${e.runtimeType}), retrying once");
      await Future.delayed(const Duration(seconds: 1));
      return await backend.join();
    }
  }

  @override
  Future<VoipSession?> startCall() async {
    final wasEmpty = getCurrentParticipants().isEmpty;
    final session = await joinCall();
    if (session != null && wasEmpty) unawaited(_sendCallNotify());
    return session;
  }

  /// MSC4075 call notification, as Element Call sends it when it starts a
  /// call: "ring" in DMs, "notify" elsewhere. Best effort; the call itself
  /// works without it.
  Future<void> _sendCallNotify() async {
    try {
      await room.matrixRoom.sendEvent({
        "application": "m.call",
        "call_id": "",
        "m.mentions": {"user_ids": <String>[], "room": true},
        "notify_type": room.matrixRoom.isDirectChat ? "ring" : "notify",
      }, type: callNotifyEvent);
    } catch (e) {
      Log.w("Could not send the call notification: ${e.runtimeType}");
    }
  }

  static const callNotifyEvent = "org.matrix.msc4075.call.notify";

  static bool _isTransientNetworkError(Object e) =>
      e is SocketException ||
      e is WebSocketException ||
      e is HttpException ||
      e is http.ClientException;
}
