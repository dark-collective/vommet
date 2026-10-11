import 'dart:math';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
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
    return matrixRoom.markedUnread || _hasNewMessages(matrixRoom);
  }
  return false;
}

/// The SDK's hasNewMessages, but a read receipt for the main thread counts
/// too: with per-thread read state on, Vommet only sends those, and the SDK
/// reads only unthreaded receipts, so the room never looked read.
bool _hasNewMessages(matrix.Room room) {
  final last = room.lastEvent;
  if (last == null || !room.client.roomPreviewLastEvents.contains(last.type)) {
    return false;
  }
  if (last.senderId == room.client.userID) return false;
  final own = [
    room.receiptState.global.latestOwnReceipt,
    room.receiptState.mainThread?.latestOwnReceipt,
  ].nonNulls;
  if (own.any((receipt) => receipt.eventId == last.eventId)) return false;
  final readAt = own.fold(0, (latest, receipt) => max(latest, receipt.ts));
  return readAt < last.originServerTs.millisecondsSinceEpoch;
}

/// Whether any room in [space] or its subspaces is unread (false while the
/// space is muted).
bool spaceHasUnread(Space space) =>
    space.pushRule != PushRule.dontNotify &&
    space.roomsWithChildren.any(roomHasUnread);
