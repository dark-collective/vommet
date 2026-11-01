import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/utils/room_unread.dart';
import 'package:commet/utils/vommet_unread.dart';

/// The only adapter from SDK room state to the pure unread model.
RoomUnread computeRoomUnread(Room room) {
  final rule = room.pushRule;
  if (rule == PushRule.dontNotify) return const RoomUnread(muted: true);
  return RoomUnread.compute(
      muted: false,
      notify: rule == PushRule.notify,
      notifications: room.notificationCount,
      highlights: room.highlightedNotificationCount,
      messagesAreNoisy: room.messagesAreNoisy,
      markedUnread: room is MatrixRoom && room.matrixRoom.markedUnread,
      unreadEvent: rule == PushRule.notify &&
          room is MatrixRoom &&
          roomHasUnreadActivity(room));
}
