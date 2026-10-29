import 'package:commet/client/client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issue 719: marks every unread room of one or more accounts as
/// read, after asking. Offered in Settings › Notifications (per account)
/// and in the Home button's menu.
class MarkAllRead {
  /// How many rooms are marked at once, so a long list doesn't send a burst
  /// of requests.
  static const batch = 4;

  /// Whether [room] has anything to mark read: a count, a mention, or
  /// messages past the read position (muted rooms included).
  static bool isUnread(Room room) =>
      room.notificationCount > 0 ||
      room.highlightedNotificationCount > 0 ||
      roomHasUnread(room);

  /// The unread rooms of [clients], each once.
  static List<Room> unreadRooms(Iterable<Client> clients) => [
        for (final client in clients)
          for (final room in client.rooms)
            if (isUnread(room)) room,
      ];

  /// Marks [rooms] read, [batch] at a time; a room that fails is logged and
  /// skipped.
  static Future<void> mark(List<Room> rooms) async {
    for (var i = 0; i < rooms.length; i += batch) {
      await Future.wait(rooms.skip(i).take(batch).map((r) => r
          .markAsRead()
          .catchError((Object e, StackTrace s) =>
              Log.onError(e, s, content: "Couldn't mark a room as read"))));
    }
  }

  /// Asks, then marks the unread rooms of [clients] read. Returns whether
  /// it did.
  static Future<bool> confirmAndMark(
      BuildContext context, Iterable<Client> clients) async {
    final rooms = unreadRooms(clients);
    if (rooms.isEmpty) return false;
    if (await AdaptiveDialog.confirmation(context,
            title: markAllReadTitle,
            prompt: markAllReadPrompt(rooms.length),
            confirmationText: markAllReadConfirm,
            cancelText: CommonStrings.promptCancel) !=
        true) {
      return false;
    }
    await mark(rooms);
    return true;
  }

  static String get markAllReadLabel => Intl.message("Mark all as read",
      name: "markAllReadLabel",
      desc: "Menu item and button that mark every unread room as read");

  static String get markAllReadTitle => Intl.message("Mark all as read?",
      name: "markAllReadTitle",
      desc: "Title of the dialog confirming marking every room as read");

  static String markAllReadPrompt(int count) => Intl.plural(count,
      one: "Marks 1 unread room as read, on all your devices.",
      other: "Marks $count unread rooms as read, on all your devices.",
      args: [count],
      name: "markAllReadPrompt",
      desc: "Dialog confirming marking every unread room as read");

  static String get markAllReadConfirm => Intl.message("Mark as read",
      name: "markAllReadConfirm",
      desc: "Confirm button of the dialog that marks every room as read");

  static String get markAllReadNothing => Intl.message("Nothing unread",
      name: "markAllReadNothing",
      desc: "Shown next to the Mark all as read button when no room is unread");

  static String get markAllReadExplain => Intl.message(
      "Marks every unread room of the account as read, on all your devices.",
      name: "markAllReadExplain",
      desc: "Explanation of the Mark all as read button in the settings");
}
