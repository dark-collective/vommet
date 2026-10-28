import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/push_notification/notifier.dart';
import 'package:commet/client/components/push_notification/web/browser_notifications.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/sounds/app_sounds.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/event_bus.dart';

/// What a browser notification shows and what clicking it does.
class WebNotificationPlan {
  final String title;
  final String body;
  final String tag;

  /// Set: clicking opens this room. Null: clicking opens Home.
  final String? roomId;
  final String? clientId;
  final String? eventId;

  /// Plays the message sound (null: no sound).
  final SoundEvent? sound;

  const WebNotificationPlan(
      {required this.title,
      required this.body,
      required this.tag,
      this.roomId,
      this.clientId,
      this.eventId,
      this.sound});

  /// The tag prefix shared by a room's message notifications, so reading
  /// the chat closes them.
  static String roomTagPrefix(String clientId, String roomId) =>
      "vommet|$clientId|$roomId|";

  /// Null for notifications the web app doesn't show (error notices).
  static WebNotificationPlan? of(NotificationContent content) {
    switch (content) {
      case MessageNotificationContent c:
        // Room messages say where they're from, as desktop's header does.
        final title = c.isDirectMessage
            ? c.senderName
            : "${c.senderName} (${c.roomName})";
        final sound = c.playsSound
            ? (c.playsMentionSound ? SoundEvent.mention : SoundEvent.message)
            : null;
        return WebNotificationPlan(
            title: c.withAccountLabel(title),
            body: c.content,
            tag: "${roomTagPrefix(c.clientId, c.roomId)}${c.eventId}",
            roomId: c.roomId,
            clientId: c.clientId,
            eventId: c.eventId,
            sound: sound);
      case CallNotificationContent c:
        return WebNotificationPlan(
            title: c.withAccountLabel(c.roomName),
            body: c.content,
            tag: "vommet-call|${c.clientId}|${c.callId}",
            roomId: c.roomId,
            clientId: c.clientId);
      case RoomInviteNotificationContent c:
        return WebNotificationPlan(
            title: c.withAccountLabel(c.title),
            body: c.content,
            tag: "vommet-invite|${c.clientId}|${c.roomId}",
            sound: SoundEvent.message);
      default:
        return null;
    }
  }
}

/// Vommet issue 767: notifications in the web app through the browser's
/// Notification API, while the tab is open. The [NotificationManager]
/// pipeline decides what notifies (push rules, muted rooms, Do Not Disturb,
/// the open room in a focused tab, in-app banners) exactly as on desktop;
/// this only shows the result. No push while the tab is closed.
class WebNotifier implements Notifier {
  @override
  bool get hasPermission => browserNotificationPermission() == "granted";

  @override
  bool get enabled => hasPermission;

  @override
  bool get needsToken => false;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async {
    try {
      return await requestBrowserNotificationPermission() == "granted";
    } catch (e, s) {
      Log.onError(e, s, content: "Notification permission request failed");
      return false;
    }
  }

  @override
  Future<void> notify(NotificationContent notification) async {
    final plan = WebNotificationPlan.of(notification);
    if (plan == null) return;

    final shown = showBrowserNotification(
        title: plan.title,
        body: plan.body,
        tag: plan.tag,
        onClick: () => _open(plan));
    if (!shown) {
      Log.d("The browser didn't show the notification (permission: "
          "${browserNotificationPermission()})");
      return;
    }

    final sound = plan.sound;
    if (sound != null) {
      try {
        final media = AppSounds.media(sound);
        if (media != null) NotificationManager.getSoundPlayer().open(media);
      } catch (e, s) {
        Log.onError(e, s, content: "Couldn't play the notification sound");
      }
    }

    if (notification is MessageNotificationContent) {
      NotificationManager.noteRoomNotified(
          notification.clientId, notification.roomId);
    }
  }

  static void _open(WebNotificationPlan plan) {
    focusBrowserTab();
    final roomId = plan.roomId;
    if (roomId == null) {
      EventBus.openHomeScreen.add(null);
    } else {
      EventBus.doOpenRoom(roomId, clientId: plan.clientId);
    }
  }

  @override
  Future<void> clearNotifications(Room room) async {
    closeBrowserNotifications(WebNotificationPlan.roomTagPrefix(
        room.client.identifier, room.identifier));
  }

  @override
  Map<String, dynamic>? extraRegistrationData() => null;

  @override
  Future<String?> getToken() async => null;

  @override
  Future<void> enableBadges() async {}

  @override
  Future<void> disableBadges() async {}
}
