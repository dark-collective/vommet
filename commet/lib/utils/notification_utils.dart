import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/room_replacement.dart';
import 'package:commet/client/space.dart';
import 'package:commet/telemetry/main_spans.dart';
import 'package:commet/main.dart';

class NotificationUtils {
  /// Vommet: timed as a span (opt-in diagnostics); it folds over every
  /// room and runs on each badge update.
  ///
  /// Returns (highlighted, chats): the mentions to show (every message in a
  /// DM counts, Vommet's red-for-DMs rule), and how many chats have
  /// something to show. The tray, the taskbar and the room header use the
  /// chat count, as Element does (Vommet issue 654).
  static (int, int) getNotificationCounts() =>
      MainSpans.time("Notification_counts", _getNotificationCounts);

  static (int, int) _getNotificationCounts() {
    final manager = clientManager;
    if (manager == null) return (0, 0);
    final rooms = <(Room, bool)>[];
    for (final client in manager.clients) {
      final dms = client.getComponent<DirectMessagesComponent>();
      final shown = shownSpaceRooms(client.spaces);
      for (final room in client.rooms) {
        if (isStickerRoom(room)) continue;
        final isDirectMessage = dms?.isRoomDirectMessage(room) ?? false;
        if (!badgeShown(
            isDirectMessage: isDirectMessage,
            superseded: isSupersededRoom(room),
            inAnySpace: client.spaces
                .any((space) => space.containsRoom(room.identifier)),
            inShownSpace: shown.contains(room.localId))) {
          continue;
        }
        rooms.add((room, isDirectMessage));
      }
    }
    return countNotifications(rooms);
  }

  /// Vommet issue 812: the rooms whose badges the space rail shows: those
  /// in a top-level space that isn't muted (a muted space shows none).
  static Set<String> shownSpaceRooms(Iterable<Space> spaces) => {
        for (final space in spaces)
          if (space.isTopLevel && space.pushRule != PushRule.dontNotify)
            for (final room in space.roomsWithChildren) room.localId,
      };

  /// Vommet issue 812: whether the app shows a room's badge somewhere, so
  /// the tray counts it. A replaced room you've followed is hidden, a direct
  /// message shows under Home, a room outside every space shows in the room
  /// list, and a room in spaces shows when one of them does. The tray used
  /// to count every room, so it could show 2 with nothing unread in the app.
  static bool badgeShown(
          {required bool isDirectMessage,
          required bool superseded,
          required bool inAnySpace,
          required bool inShownSpace}) =>
      !superseded && (isDirectMessage || !inAnySpace || inShownSpace);

  /// Each room counts once, whichever spaces hold it, and rooms outside
  /// any space count too (Vommet issue 654: adding up each top-level
  /// space's messages counted a room once per space, missed rooms outside
  /// spaces, and showed 45 where Element showed 8 chats).
  static (int, int) countNotifications(
      Iterable<(Room, bool isDirectMessage)> rooms) {
    var highlighted = 0;
    var chats = 0;
    final seen = <String>{};
    for (final (room, isDirectMessage) in rooms) {
      if (!seen.add(room.localId)) continue;
      final mentions = room.displayHighlightedNotificationCount;
      final messages = room.displayNotificationCount;
      highlighted += isDirectMessage ? messages : mentions;
      if (mentions > 0 || messages > 0) chats += 1;
    }
    return (highlighted, chats);
  }
}
