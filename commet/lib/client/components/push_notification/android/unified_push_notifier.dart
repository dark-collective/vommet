import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/push_notification/android/android_notifier.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/push_notification/notifier.dart';
import 'package:commet/client/components/push_notification/push_notification_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/service/background_service_notifications/background_service_task_notification2.dart';
import 'package:commet/ui/pages/setup/menus/unified_push_setup.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/first_time_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:unifiedpush/unifiedpush.dart';

class UnifiedPushNotifier implements Notifier {
  late AndroidNotifier notifier;

  @override
  bool get needsToken => true;

  List<String> notifiedEvents = List.empty(growable: true);

  bool isInit = false;

  UnifiedPushNotifier() {
    notifier = AndroidNotifier();

    if (preferences.unifiedPushEnabled.value == null) {
      FirstTimeSetup.registerPostLoginSetup(UnifiedPushSetup());
    }
  }

  StreamController<String> onEndpointChanged = StreamController.broadcast();

  String? get endpoint => preferences.unifiedPushEndpoint.value;

  @override
  bool get enabled => preferences.unifiedPushEnabled.value == true;

  @override
  bool get hasPermission => notifier.hasPermission;

  String get instance => isHeadless ? "background_task" : "default";

  @override
  Future<void> init() async {
    if (isInit) return;
    if (preferences.unifiedPushEnabled.value != true) return;

    await notifier.init();

    Log.i("Initializing unified push");
    UnifiedPush.initialize(
        onMessage: onMessage,
        onNewEndpoint: onNewEndpoint,
        onRegistrationFailed: onRegistrationFailed,
        onUnregistered: onUnregistered);

    isInit = true;

    if (!isHeadless) {
      startupCheck = ensureRegistered();
      unawaited(startupCheck);
    }
  }

  /// Vommet: the startup check ([ensureRegistered]); null in the background
  /// task or while UnifiedPush is off.
  Future<void>? startupCheck;

  /// Vommet: the distributors to choose from when the startup check found
  /// several installed but none it could use (none saved, or the saved one
  /// uninstalled). The main page then asks the user (Vommet issue 168);
  /// null when nothing needs choosing.
  List<String>? distributorChoice;

  /// Vommet: whether the user has to choose a distributor: none can be
  /// picked automatically, but several are installed. With none installed
  /// the notification settings already say so.
  static bool needsChoice(List<String> found, String? saved) =>
      startupDistributor(found, saved) == null && found.length > 1;

  /// Vommet: the distributor to register with at startup: the saved one if
  /// it's still installed, else the only one installed, else none (the user
  /// picks in Settings › Notifications).
  static String? startupDistributor(List<String> found, String? saved) {
    if (saved != null && saved.isNotEmpty && found.contains(saved)) {
      return saved;
    }
    if (found.length == 1) return found.single;
    return null;
  }

  /// Vommet: register with the distributor again on every start, as
  /// UnifiedPush recommends. Before, nothing checked at startup that a
  /// distributor was still saved and installed: a setup from an older build
  /// (or a since-uninstalled distributor) stayed silently broken until the
  /// user turned UnifiedPush off and on again. Re-registering with the same
  /// distributor keeps the same endpoint.
  Future<void> ensureRegistered() async {
    try {
      final found = await UnifiedPush.getDistributors([]);
      final saved = await UnifiedPush.getDistributor();
      final pick = startupDistributor(found, saved);
      Log.i("UnifiedPush at startup: found ${found.join(", ")}; "
          "saved: $saved; using: $pick");
      if (needsChoice(found, saved)) distributorChoice = found;
      if (pick == null) return;
      if (pick != saved) await UnifiedPush.saveDistributor(pick);
      await UnifiedPush.registerApp(instance);
    } catch (e, s) {
      Log.onError(e, s, content: "UnifiedPush startup registration failed");
    }
  }

  @override
  Future<String?> getToken() async {
    if (preferences.unifiedPushEnabled.value != true) {
      return null;
    }

    return preferences.unifiedPushEndpoint.value;
  }

  @override
  Future<void> notify(NotificationContent notification) {
    return notifier.notify(notification);
  }

  @override
  Future<bool> requestPermission() {
    return notifier.requestPermission();
  }

  /// Vommet issue 509: how a new endpoint compares to the saved one, for the
  /// log (the endpoint itself is a secret). "changed" after a re-registration
  /// at startup means the distributor made a new registration.
  static String endpointChange(String? saved, String endpoint) {
    if (saved == null || saved.isEmpty) return "first";
    return saved == endpoint ? "unchanged" : "changed";
  }

  void onNewEndpoint(String endpoint, String instance) async {
    // Vommet issue 509: was a print(), so it never reached the app log.
    Log.i("UnifiedPush endpoint for $instance: "
        "${endpointChange(preferences.unifiedPushEndpoint.value, endpoint)}");
    await preferences.unifiedPushEndpoint.set(endpoint);
    await PushNotificationComponent.updateAllPushers();
    onEndpointChanged.add(endpoint);
  }

  Future<void> onBackgroundMessage(Map<String, dynamic> message) async {
    try {
      var notificationManager = BackgroundNotificationsManager2(null);

      await notificationManager.init();

      if (!message.containsKey("room_id") || !message.containsKey("event_id")) {
        // Vommet: homeservers also push when only your unread total changes
        // (e.g. {"counts": {"unread": 0}, "devices": [...]} after reading
        // elsewhere). Expected; developer mode showed them as "Unknown
        // Notification Data", with the push key.
        if (isCountOnlyPush(message)) {
          Log.i("UnifiedPush: unread count update "
              "(${(message["counts"] as Map?)?["unread"]})");
          return;
        }
        if (preferences.developerMode.value) {
          // ignore {"prio": "high"} notifications
          if (message.length == 2 && message.containsKey("prio")) {
            return;
          }

          NotificationManager.notify(ErrorNotificationContent(
            title: "Unknown Notification Data",
            content: jsonEncode(message),
          ));
        }

        return;
      }

      notificationManager.handleMessage(message);
    } catch (e, s) {
      Log.e(
          "An error occured while processing unified push background message");
      Log.onError(e, s);
      NotificationManager.notify(ErrorNotificationContent(
          title: "An error occurred while processing notifications",
          content: "${e} \n\n ${s}"));
    }
  }

  /// Vommet: a push that only carries unread counts, no room or event.
  static bool isCountOnlyPush(Map<String, dynamic> message) =>
      message["counts"] is Map &&
      message["event_id"] == null &&
      message["room_id"] == null;

  /// Vommet issue 508: a count-only push saying nothing is unread.
  static bool isAllReadPush(Map<String, dynamic> message) =>
      isCountOnlyPush(message) && (message["counts"] as Map)["unread"] == 0;

  /// Vommet issue 508: once everything is read, the message notifications
  /// on screen are stale. Only with one account signed in, since the push
  /// doesn't say whose count it is.
  static Future<void> closeMessageNotificationsWhenAllRead() async {
    if (preferences.getRegisteredMatrixClients()?.length != 1) return;
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      for (final noti in await plugin.getActiveNotifications()) {
        final channel = noti.channelId ?? "";
        // "messages", "messages_<sound>", "mentions_<sound>": not calls,
        // invites or errors.
        if (noti.id != null &&
            (channel.startsWith("messages") ||
                channel.startsWith("mentions"))) {
          await plugin.cancel(noti.id!);
        }
      }
    } catch (e, s) {
      Log.onError(e, s);
    }
  }

  void onMessage(Uint8List message, String instance) async {
    Log.i("Received unified push message! $instance");
    var data = utf8.decode(message);

    EventBus.onReceivedPushNotificationData.add(data);

    var json = jsonDecode(data) as Map<String, dynamic>;

    var notifData = json['notification'] as Map<String, dynamic>;
    MessageNotificationContent.notePush(notifData);
    Log.i("Received message from unified push: $json");

    // Workaround for notifications being displayed twice sometimes. Not sure where its coming from...
    if (notifData.containsKey("event_id")) {
      var eventId = notifData['event_id'] as String;

      if (notifiedEvents.contains(eventId)) {
        return;
      }
      notifiedEvents.add(eventId);

      Timer(Duration(seconds: 5), () {
        notifiedEvents.removeWhere((e) => e == eventId);
      });
    }

    // Vommet issue 508: nothing left unread, e.g. read on another device.
    if (isAllReadPush(notifData)) {
      await closeMessageNotificationsWhenAllRead();
    }

    if (isHeadless) {
      onBackgroundMessage(notifData);
    } else {
      AndroidNotifier.onForegroundMessage(notifData);
    }

    Log.i("${WidgetsBinding.instance.lifecycleState}");
  }

  // Vommet issue 509: both were never passed to UnifiedPush.initialize, so
  // they didn't log. Either one makes the UnifiedPush connector forget its
  // registration token, and the next registration then shows up in the
  // distributor as a new one.
  void onUnregistered(String instance) {
    Log.i("Unified push unregistered: $instance");
  }

  void onRegistrationFailed(String instance) {
    Log.w("UnifiedPush registration failed: $instance");
  }

  Future<void> unregister() async {
    await UnifiedPush.unregister();
    await preferences.unifiedPushEnabled.set(false);
    await preferences.unifiedPushEndpoint.set(null);
    await PushNotificationComponent.updateAllPushers();
  }

  @override
  Map<String, dynamic>? extraRegistrationData() {
    return null;
  }

  @override
  Future<void> clearNotifications(Room room) {
    return notifier.clearNotifications(room);
  }

  @override
  Future<void> disableBadges() {
    // TODO: implement disableBadges
    throw UnimplementedError();
  }

  @override
  Future<void> enableBadges() {
    // TODO: implement enableBadges
    throw UnimplementedError();
  }
}
