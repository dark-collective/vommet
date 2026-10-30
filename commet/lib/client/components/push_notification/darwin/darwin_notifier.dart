import 'dart:convert';
import 'dart:io';

import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notifier.dart';
import 'package:commet/client/room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Vommet issue 531: local notifications on macOS and iOS, shown by the
/// running app through the system notification center. There is no APNs
/// push yet, so nothing arrives while the app is closed (or suspended, on iOS).
class DarwinNotifier implements Notifier {
  static bool get isSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isIOS);

  @override
  bool hasPermission = false;

  @override
  bool get enabled => true;

  @override
  bool get needsToken => false;

  FlutterLocalNotificationsPlugin? _plugin;

  /// Shown notification ids per room, so opening the room clears them.
  final Map<String, Set<int>> _shown = {};

  @override
  Future<void> init() async {
    _plugin = FlutterLocalNotificationsPlugin();

    // Asks for permission on first launch, like Element X does.
    const darwin = DarwinInitializationSettings();
    const settings = InitializationSettings(iOS: darwin, macOS: darwin);

    final granted = await _plugin!
        .initialize(settings, onDidReceiveNotificationResponse: _onResponse);
    hasPermission = granted ?? false;
    Log.i("Darwin notifications initialized, permission: $hasPermission");
  }

  @override
  Future<bool> requestPermission() async {
    final plugin = _plugin;
    if (plugin == null) return false;

    bool? granted;
    if (Platform.isIOS) {
      granted = await plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else {
      granted = await plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    hasPermission = granted ?? false;
    return hasPermission;
  }

  @override
  Future<void> notify(NotificationContent notification) async {
    final plan = DarwinNotificationPlan.of(notification);
    final plugin = _plugin;
    if (plan == null || plugin == null) return;

    final details = NotificationDetails(
        iOS: DarwinNotificationDetails(
            subtitle: plan.subtitle, threadIdentifier: plan.threadId),
        macOS: DarwinNotificationDetails(
            subtitle: plan.subtitle, threadIdentifier: plan.threadId));

    await plugin.show(plan.id, plan.title, plan.body, details,
        payload: plan.payload);

    final key = plan.threadId;
    if (key != null) {
      _shown.putIfAbsent(key, () => {}).add(plan.id);
    }
  }

  static void _onResponse(NotificationResponse response) {
    final target = DarwinNotificationPlan.openTarget(response.payload);
    if (target == null) return;
    EventBus.doOpenRoom(target.roomId, clientId: target.clientId);
  }

  @override
  Future<void> clearNotifications(Room room) async {
    final ids = _shown.remove(DarwinNotificationPlan.roomKey(
        room.client.identifier, room.identifier));
    if (ids == null) return;
    for (final id in ids) {
      await _plugin?.cancel(id);
    }
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

/// What a macOS/iOS notification shows and what tapping it opens.
class DarwinNotificationPlan {
  final int id;
  final String title;
  final String body;
  final String? subtitle;

  /// Groups a room's notifications (and keys clearing them).
  final String? threadId;
  final String? payload;

  const DarwinNotificationPlan(
      {required this.id,
      required this.title,
      required this.body,
      this.subtitle,
      this.threadId,
      this.payload});

  static String roomKey(String clientId, String roomId) => "$clientId|$roomId";

  static String _payload(String clientId, String roomId) =>
      jsonEncode({"client_id": clientId, "room_id": roomId});

  /// The room a tapped notification opens, or null.
  static ({String roomId, String clientId})? openTarget(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final data = jsonDecode(payload);
      if (data is! Map) return null;
      final roomId = data["room_id"];
      final clientId = data["client_id"];
      if (roomId is! String || clientId is! String) return null;
      return (roomId: roomId, clientId: clientId);
    } catch (_) {
      return null;
    }
  }

  /// Notification ids must fit in a 32-bit int on the native side.
  static int idFor(String key) => key.hashCode & 0x7fffffff;

  static DarwinNotificationPlan? of(NotificationContent content) {
    switch (content) {
      case MessageNotificationContent c:
        return DarwinNotificationPlan(
            id: idFor("${c.clientId}|${c.roomId}|${c.eventId}"),
            title: c.senderName,
            // Room messages say where they're from; DMs don't need to.
            subtitle: c.isDirectMessage ? null : c.roomName,
            body: c.content,
            threadId: roomKey(c.clientId, c.roomId),
            payload: _payload(c.clientId, c.roomId));
      case CallNotificationContent c:
        return DarwinNotificationPlan(
            id: idFor("${c.clientId}|${c.roomId}|call|${c.callId}"),
            title: c.roomName,
            body: c.content,
            threadId: roomKey(c.clientId, c.roomId),
            payload: _payload(c.clientId, c.roomId));
      case ErrorNotificationContent c:
        return DarwinNotificationPlan(
            id: idFor("error|${c.title}"), title: c.title, body: c.content);
      default:
        return DarwinNotificationPlan(
            id: idFor("${content.title}|${content.content}"),
            title: content.title,
            body: content.content);
    }
  }
}
