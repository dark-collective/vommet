import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_leave.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: clearing the call membership a previous run of this app left
/// behind.
///
/// Quitting the app (or having it killed from the recents list) during a call
/// can't always hang up first. The `m.call.member` event then stays until it
/// expires, hours later, and everyone sees us "in the call" while we're in it
/// nowhere. Homeservers with delayed events (MSC4140) clean this up
/// themselves; on the others we do it at the next start. Only OUR OWN device's
/// membership is touched, and only while no call is running in that room.
class MatrixRtcStaleMembership {
  /// The state keys of [states] (state key -> sender and content) that are
  /// this device's own live-looking memberships: sent by [userId], for
  /// [deviceId], not already cleared.
  static List<String> staleKeys(
    Map<String, ({String? sender, Map<String, dynamic> content})> states, {
    required String userId,
    required String deviceId,
  }) {
    final keys = <String>[];
    for (final entry in states.entries) {
      final content = entry.value.content;
      if (content.isEmpty) continue;
      if (entry.value.sender != userId) continue;
      if (content["device_id"] != deviceId) continue;
      keys.add(entry.key);
    }
    return keys;
  }

  /// Clears this device's leftover memberships in every room of [client].
  static Future<void> sweep(MatrixClient client) async {
    final matrixClient = client.getMatrixClient();
    final userId = matrixClient.userID;
    final deviceId = matrixClient.deviceID;
    if (userId == null || deviceId == null) return;

    for (final room in matrixClient.rooms) {
      final state = room.states[MatrixVoipRoomComponent.callMemberStateEvent];
      if (state == null || state.isEmpty) continue;

      final call = clientManager?.callManager.getCallInRoom(client, room.id);
      if (call != null && call.state != VoipState.ended) continue;

      final keys = staleKeys({
        for (final e in state.entries)
          if (e.value is matrix.Event)
            e.key: (
              sender: (e.value as matrix.Event).senderId,
              content: (e.value as matrix.Event).content
            )
      }, userId: userId, deviceId: deviceId);

      for (final key in keys) {
        Log.i("Clearing a call membership left over from the last run "
            "in ${room.id}");
        unawaited(MatrixRtcLeave.clear(
            room.id,
            key,
            () => matrixClient.setRoomStateWithKey(room.id,
                MatrixVoipRoomComponent.callMemberStateEvent, key, {})));
      }
    }
  }
}
