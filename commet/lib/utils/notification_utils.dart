import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/room.dart';
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
    return countNotifications([
      for (final client in manager.clients)
        for (final room in client.rooms)
          if (!isStickerRoom(room))
            (
              room,
              client
                      .getComponent<DirectMessagesComponent>()
                      ?.isRoomDirectMessage(room) ??
                  false
            ),
    ]);
  }

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
