import 'dart:math';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:matrix/matrix.dart' as matrix;

// Vommet: Discord's rule for the unread mark. A room is unread when it has
// messages you haven't read and you haven't muted it, whatever its
// notification setting. The server's notification count only counts
// messages that notify you, so a mentions-only room never had a mark; the
// SDK's read position (hasNewMessages) and "mark as unread" fill that gap.
// This file is shared, byte for byte, by feat/rail-unread-pill and
// fix/space-room-unread-dot; keep the copies identical.

/// Whether [room] has messages you haven't read (false while it's muted).
bool roomHasUnread(Room room) {
  if (room.pushRule == PushRule.dontNotify) return false;
  if (room.notificationCount > 0) return true;
  if (room is MatrixRoom) {
    final matrixRoom = room.matrixRoom;
    return matrixRoom.markedUnread || _hasNewMessages(room);
  }
  return false;
}

/// Event types that make a room unread. Call membership and the call
/// signalling events are left out: in a voice room they're the newest
/// event every time someone joins, leaves or refreshes their membership
/// (bridged voice users do this often), which kept the mark lit with
/// nothing new to read. Discord doesn't mark a channel unread when
/// someone joins voice either. A call invite still counts.
const _unreadTypes = {
  matrix.EventTypes.Message,
  matrix.EventTypes.Encrypted,
  matrix.EventTypes.Sticker,
  matrix.EventTypes.CallInvite,
};

/// The SDK's hasNewMessages, but a read receipt for the main thread counts
/// too: with per-thread read state on, Vommet only sends those, and the SDK
/// reads only unthreaded receipts, so the room never looked read. When the
/// newest event is a call event, the newest message is judged instead.
bool _hasNewMessages(MatrixRoom matrixRoom) {
  final room = matrixRoom.matrixRoom;
  final message = matrixRoom.lastMessage;
  final newest = room.lastEvent;
  final last = newest != null && _unreadTypes.contains(newest.type)
      ? newest
      : message is MatrixTimelineEvent
          ? message.event
          : null;
  if (last == null || !_unreadTypes.contains(last.type)) return false;
  if (last.senderId == room.client.userID) return false;
  return !readByOwnReceipts(room, last);
}

/// Whether the account's own read receipts cover [event]: one is on it or
/// came later. A thread reply is also covered by its thread's receipt.
bool readByOwnReceipts(matrix.Room room, matrix.Event event) {
  final own = _ownReceipts(room, event).toList();
  if (own.any((receipt) => receipt.eventId == event.eventId)) return true;
  final readAt = own.fold(0, (latest, receipt) => max(latest, receipt.ts));
  return readAt >= event.originServerTs.millisecondsSinceEpoch;
}

/// The account's own read receipts for [room]; with [event] a thread
/// reply, its thread's receipt too (Vommet issue 843: when the newest event
/// was a thread reply, reading the thread never cleared the room's mark,
/// only sending a message did).
Iterable<matrix.LatestReceiptStateData> _ownReceipts(matrix.Room room,
    [matrix.Event? event]) {
  final root = event?.relationshipType == matrix.RelationshipTypes.thread
      ? event?.relationshipEventId
      : null;
  return [
    room.receiptState.global.latestOwnReceipt,
    room.receiptState.mainThread?.latestOwnReceipt,
    if (root != null) room.receiptState.byThread[root]?.latestOwnReceipt,
  ].nonNulls;
}

/// When the account last read [room] (milliseconds since the epoch, 0 if
/// never): its newest own read receipt, main thread receipts included (see
/// [_hasNewMessages]).
int ownReadAt(matrix.Room room) =>
    _ownReceipts(room).fold(0, (latest, receipt) => max(latest, receipt.ts));

/// Whether any room in [space] or its subspaces is unread (false while the
/// space is muted).
bool spaceHasUnread(Space space) =>
    space.pushRule != PushRule.dontNotify &&
    space.roomsWithChildren.any(roomHasUnread);
