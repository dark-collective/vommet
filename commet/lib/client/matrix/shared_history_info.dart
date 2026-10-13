// Vommet: who shared a room's earlier messages with us (MSC4268). Keys from
// an invite's history bundle only have the inviter's word for who sent each
// message, so the spec requires showing who shared them.

import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:matrix/encryption/history_sharing.dart';
import 'package:matrix/matrix.dart' as matrix;

class SharedHistoryInfo {
  /// The display name of whoever shared the key that decrypted [event], or
  /// null if it came some other way (or the event isn't encrypted).
  static String? sharedBy(TimelineEvent event) {
    if (event is! MatrixTimelineEvent) return null;
    final ev = event.event;
    final original = ev.originalSource;
    if (original == null || original.type != matrix.EventTypes.Encrypted) {
      return null;
    }
    final sessionId = original.content.tryGet<String>("session_id");
    final roomId = ev.roomId;
    if (sessionId == null || roomId == null) return null;
    final session = ev.room.client.encryption?.keyManager
        .getInboundGroupSession(roomId, sessionId);
    if (session == null) return null;
    final userId = HistorySharing.sharedBy(session);
    if (userId == null) return null;
    return ev.room.unsafeGetUserFromMemoryOrFallback(userId).calcDisplayname();
  }

  /// Who shared [room]'s earlier messages when we joined, as a display name,
  /// or null if nobody did.
  static Future<String?> sharerOf(Room room) async {
    if (room is! MatrixRoom) return null;
    final mx = room.matrixRoom;
    final record =
        await mx.client.encryption?.historySharing.importedHistory(mx.id);
    if (record == null || record.keyCount == 0) return null;
    return mx
        .unsafeGetUserFromMemoryOrFallback(record.sender)
        .calcDisplayname();
  }
}
