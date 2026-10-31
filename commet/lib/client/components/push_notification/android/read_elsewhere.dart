import 'package:commet/client/components/push_notification/android/android_notifier.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 808: close the message notifications of rooms read on
/// another device, when a push only says the unread total changed.
///
/// Issue 508 only closes everything once that total is 0, and the per-room
/// check (NotificationManager.closeReadRooms) needs a sync, which a sleeping
/// app doesn't get. The server's /notifications list says per message
/// whether a read receipt covers it, so one request tells which of the rooms
/// on screen were read elsewhere.
class ReadElsewhere {
  /// How many recent notifications to look at.
  static const lookBack = 50;

  /// The rooms in [shown] whose notifications in [notifications] are all
  /// read. A room that isn't in the list at all is left alone: its
  /// notifications are older than the list, or another account's.
  static Set<String> readRooms(
      Iterable<matrix.Notification> notifications, Set<String> shown) {
    final listed = <String>{};
    final unread = <String>{};
    for (final n in notifications) {
      if (!shown.contains(n.roomId)) continue;
      listed.add(n.roomId);
      if (!n.read) unread.add(n.roomId);
    }
    return listed.difference(unread);
  }

  /// The rooms with a message notification on screen.
  static Future<Set<String>> shownRooms() async {
    final active =
        await FlutterLocalNotificationsPlugin().getActiveNotifications();
    return {
      for (final noti in active)
        if (noti.groupKey != null &&
            AndroidNotifier.isMessageChannel(noti.channelId))
          noti.groupKey!
    };
  }

  /// Asks [api]'s server which of [shown] were read and closes those rooms'
  /// message notifications.
  static Future<void> closeReadRooms(
      matrix.MatrixApi api, Set<String> shown) async {
    if (shown.isEmpty) return;
    try {
      final response = await api
          .getNotifications(limit: lookBack)
          .timeout(const Duration(seconds: 10));
      final read = readRooms(response.notifications, shown);
      Log.i("Push: ${read.length} of ${shown.length} notified rooms "
          "read elsewhere");
      if (read.isEmpty) return;

      final plugin = FlutterLocalNotificationsPlugin();
      for (final noti in await plugin.getActiveNotifications()) {
        if (noti.id != null &&
            read.contains(noti.groupKey) &&
            AndroidNotifier.isMessageChannel(noti.channelId)) {
          await plugin.cancel(noti.id!);
        }
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't check rooms read elsewhere");
    }
  }
}
