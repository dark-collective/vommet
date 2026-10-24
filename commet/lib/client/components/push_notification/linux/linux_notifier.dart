import 'dart:async';
import 'dart:convert';
import 'package:commet/client/sounds/app_sounds.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/push_notification/linux/linux_notification_markup.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/push_notification/notifier.dart';
import 'package:commet/client/room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:commet/utils/image_utils.dart';
import 'package:commet/utils/notification_utils.dart';
import 'package:commet/utils/shortcuts_manager.dart';
import 'package:desktop_notifications/desktop_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_linux/src/model/hint.dart' as notif;
import 'package:launcher_entry/launcher_entry.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path/path.dart' as p;

class LinuxNotifier implements Notifier {
  @override
  bool get hasPermission => true;

  static NotificationsClient client = NotificationsClient();

  @override
  bool get enabled => true;

  @override
  Future<bool> requestPermission() async {
    return true;
  }

  static LinuxFlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;

  static void backgroundNotificationResponse(NotificationResponse details) {}

  static const callAccept = "call.accept";
  static const callDecline = "call.decline";
  static const openRoom = "room.open";
  static const openHome = "home.open";

  static int notificationId = 0;

  /// The daemon's capabilities, read once at startup. Null when the daemon
  /// could not be asked (Vommet).
  LinuxServerCapabilities? capabilities;

  /// Vommet: whether the daemon reads the body as markup. When its
  /// capabilities are unknown, assume it does, so other people's text is
  /// always escaped rather than rendered.
  bool get bodyMarkup => capabilities?.bodyMarkup ?? true;

  final service =
      LauncherEntryService(appUri: 'application://im.nether.chat.desktop');

  static void notificationResponse(NotificationResponse details) {
    final payload = jsonDecode(details.payload!) as Map<String, dynamic>;

    var action = details.actionId ?? payload["default_action_id"];

    if (action == "inline-reply") {
      var clientId = payload['client_id'];
      var roomId = payload['room_id'];
      var eventId = payload['event_id'];
      var message = details.input;

      if (clientId == null) return;
      if (roomId == null) return;
      if (eventId == null) return;
      if (message == null) return;

      var client = clientManager!.getClient(clientId);

      if (client == null) return;

      if (message.trim().isNotEmpty) {
        client.getRoom(roomId)?.sendMessage(message: message.trim());
      }
      return;
    }

    // Vommet issue 550: an invite opens Home, where the invite list is.
    if (action == openHome) {
      EventBus.openHomeScreen.add(null);
      windowManager.show();
      windowManager.focus();
      return;
    }

    if ([callAccept, openRoom].contains(action)) {
      final roomId = payload['room_id']!;

      var clientId = payload['client_id'] as String?;
      EventBus.doOpenRoom(roomId, clientId: clientId);
      windowManager.show();
      windowManager.focus();
    }

    if ([callAccept, callDecline].contains(action)) {
      final callId = payload['call_id'];
      final clientId = payload['client_id'];
      final session = clientManager?.callManager.currentSessions
          .where(
              (e) => e.sessionId == callId && e.client.identifier == clientId)
          .firstOrNull;

      if (action == callDecline) {
        clientManager?.callManager.stopRingtone();
      }

      if (session != null) {
        if (action == callAccept) {
          session.acceptCall(withMicrophone: true);
        }

        if (action == callDecline) {
          session.declineCall();
          clientManager?.callManager.stopRingtone();
        }
      } else {
        Log.d("Could not find call session");
      }
    }
  }

  @override
  Future<void> init() async {
    flutterLocalNotificationsPlugin = LinuxFlutterLocalNotificationsPlugin();

    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    await flutterLocalNotificationsPlugin?.initialize(
        initializationSettingsLinux,
        onDidReceiveNotificationResponse: notificationResponse);

    try {
      capabilities = await flutterLocalNotificationsPlugin!.getCapabilities();
    } catch (e, s) {
      Log.onError(e, s,
          content: "Could not read the notification daemon's capabilities");
    }

    await loadRoomNotificationIds();

    clientManager!.directMessages.highlightedRoomsList.onListUpdated
        .listen((_) => updateBadgeCount());
    clientManager!.onSpaceUpdated.stream.listen((_) => updateBadgeCount());

    // Vommet: the first count waits until the rooms have loaded and the app
    // is up. Counting while they load added up every space's unread counts
    // on each space update, on the startup path of slow devices.
    _badgeHeld = true;
    unawaited(clientManager!
        .waitForStartupLoads()
        .timeout(const Duration(seconds: 20), onTimeout: () {})
        .whenComplete(() {
      _badgeHeld = false;
      updateBadgeCount();
    }));
  }

  /// Vommet: until startup is done, counts wait (see [init]).
  bool _badgeHeld = false;
  Timer? _badgeTimer;

  /// Vommet: updates come in bursts (a space update per space each sync);
  /// counted once per burst.
  static const badgeCoalesce = Duration(milliseconds: 250);

  void updateBadgeCount() {
    if (_badgeHeld || _badgeTimer != null) return;
    _badgeTimer = Timer(badgeCoalesce, () {
      _badgeTimer = null;
      _updateBadgeCountNow();
    });
  }

  void _updateBadgeCountNow() {
    if (preferences.showNotificationBadgesInTaskbar.value == true) {
      var counts = NotificationUtils.getNotificationCounts();
      var count = counts.$2;
      service.update(countVisible: count > 0, count: count);
    }
  }

  @override
  Future<void> notify(NotificationContent notification) async {
    switch (notification) {
      case MessageNotificationContent _:
        return displayMessageNotification(notification);
      case CallNotificationContent _:
        return displayCallNotification(notification);
      case RoomInviteNotificationContent _:
        return displayInviteNotification(notification);
      default:
    }
  }

  /// Vommet issue 550: a room invite, with the room's picture.
  Future<void> displayInviteNotification(
      RoomInviteNotificationContent content) async {
    var image = await ShortcutsManager.createAvatarImage(
        placeholderColor: content.roomColor ?? const Color(0xFF8E6FD8),
        placeholderText:
            content.isDirect ? content.inviterName : content.roomName,
        imageProvider: content.isDirect ? null : content.roomImage,
        doCircleMask: true,
        shouldZoomOut: false);

    var bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = bytes!.buffer.asUint8List();

    var details = LinuxNotificationDetails(
      icon: ByteDataLinuxIcon(LinuxRawIconData(
          data: data,
          width: image.width,
          height: image.height,
          hasAlpha: true,
          channels: 4)),
      defaultActionName: openHome,
      customHints: [
        notif.LinuxNotificationCustomHint(
            'desktop-entry', notif.LinuxHintStringValue("im.nether.chat")),
      ],
      category: LinuxNotificationCategory.imReceived,
    );

    // The body names the inviter and the room: escaped like a message body.
    final body =
        LinuxNotificationMarkup.body(content.content, markup: bodyMarkup);

    var payload = {
      "default_action_id": openHome,
      "room_id": content.roomId,
      "client_id": content.clientId,
    };

    final sound = AppSounds.media(SoundEvent.message);
    if (sound != null) {
      NotificationManager.getSoundPlayer().open(sound);
    }

    flutterLocalNotificationsPlugin?.show(
        ++notificationId, content.withAccountLabel(content.title), body,
        notificationDetails: details, payload: jsonEncode(payload));
  }

  Future<void> displayMessageNotification(
      MessageNotificationContent content) async {
    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    var image = await ShortcutsManager.createAvatarImage(
        placeholderColor: room.getColorOfUser(content.senderId),
        placeholderText: content.senderName,
        imageProvider: content.senderImage,
        doCircleMask: true,
        shouldZoomOut: false);

    if (content.isDirectMessage == false) {
      var roomImage = await ShortcutsManager.createAvatarImage(
          placeholderColor: room.defaultColor,
          placeholderText: room.displayName,
          imageProvider: content.roomImage,
          doCircleMask: true,
          shouldZoomOut: false);

      image = await ShortcutsManager.combineRoomAndUserImages(roomImage, image);
    }

    var bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = bytes!.buffer.asUint8List();

    // Vommet: the Linux formatting modifier already builds escaped markup;
    // anything else is plain text from the sender and must not become markup.
    String notificationBody = content.contentIsMarkup
        ? content.content
        : LinuxNotificationMarkup.body(content.content, markup: bodyMarkup);

    var details = LinuxNotificationDetails(
      icon: ByteDataLinuxIcon(LinuxRawIconData(
          data: data,
          width: image.width,
          height: image.height,
          hasAlpha: true,
          channels: 4)),
      defaultActionName: openRoom,
      actions: [
        if (capabilities?.otherCapabilities.contains("inline-reply") == true)
          LinuxNotificationAction(key: "inline-reply", label: "Reply")
      ],
      customHints: [
        notif.LinuxNotificationCustomHint(
            'desktop-entry', notif.LinuxHintStringValue("im.nether.chat")),
      ],
      category: LinuxNotificationCategory.imReceived,
    );

    var title = "${content.senderName} (${content.roomName})";
    if (content.isDirectMessage) {
      title = content.senderName;
    }
    title = content.withAccountLabel(title);

    var payload = {
      // include default action here as well
      // in some cases it seems `defaultActionName` comes back as null
      // so we can use this as a fallback
      "default_action_id": openRoom,
      "room_id": content.roomId,
      "client_id": content.clientId,
      "event_id": content.eventId,
    };

    // Vommet: the chosen sound (AppSounds).
    final sound = AppSounds.media(
        content.playsMentionSound ? SoundEvent.mention : SoundEvent.message);
    if (sound != null) {
      NotificationManager.getSoundPlayer().open(sound);
    }

    flutterLocalNotificationsPlugin?.show(
        nextMessageNotificationId(content), title, notificationBody,
        notificationDetails: details, payload: jsonEncode(payload));
  }

  Future<void> displayCallNotification(CallNotificationContent content) async {
    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    var image = await ShortcutsManager.createAvatarImage(
        placeholderColor: room.getColorOfUser(content.senderId),
        placeholderText: content.roomName,
        imageProvider: content.senderImage,
        doCircleMask: true,
        shouldZoomOut: false);

    var bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = bytes!.buffer.asUint8List();

    var details = LinuxNotificationDetails(
        icon: ByteDataLinuxIcon(LinuxRawIconData(
            data: data,
            width: image.width,
            height: image.height,
            hasAlpha: true,
            channels: 4)),
        defaultActionName: openRoom,
        category: LinuxNotificationCategory.imReceived,
        timeout: const LinuxNotificationTimeout.expiresNever(),
        urgency: LinuxNotificationUrgency.critical,
        actions: [
          LinuxNotificationAction(
              key: callAccept, label: CommonStrings.promptAccept),
          LinuxNotificationAction(
              key: callDecline, label: CommonStrings.promptDecline),
        ]);

    // Vommet: the body names the caller, so it is escaped like a message body.
    content.content =
        LinuxNotificationMarkup.body(content.content, markup: bodyMarkup);

    var payload = {
      // include default action here as well
      // in some cases it seems `defaultActionName` comes back as null
      // so we can use this as a fallback
      "default_action_id": openRoom,
      "room_id": content.roomId,
      "client_id": content.clientId,
      "call_id": content.callId
    };

    flutterLocalNotificationsPlugin?.show(
        0, content.withAccountLabel(content.title), content.content,
        notificationDetails: details, payload: jsonEncode(payload));
  }

  Future<ui.Image> determineImage(ImageProvider provider) async {
    if (provider is LODImageProvider) {
      var data = await provider.loadThumbnail?.call();
      var mem = MemoryImage(data!);
      return await ImageUtils.imageProviderToImage(mem);
    }

    return await ImageUtils.imageProviderToImage(provider);
  }

  @override
  Map<String, dynamic>? extraRegistrationData() {
    return null;
  }

  @override
  Future<String?> getToken() async {
    return null;
  }

  @override
  bool get needsToken => false;

  /// Vommet issue 508: the ids of the message notifications shown for each
  /// room, so opening or focusing that chat can close them.
  final Map<String, List<int>> roomNotificationIds = {};

  static String roomNotificationKey(String clientId, String roomId) =>
      "$clientId|$roomId";

  int nextMessageNotificationId(MessageNotificationContent content) {
    // Starts at 1: id 0 belongs to the call notification.
    final id = ++notificationId;
    roomNotificationIds
        .putIfAbsent(
            roomNotificationKey(content.clientId, content.roomId), () => [])
        .add(id);
    saveRoomNotificationIds();
    NotificationManager.noteRoomNotified(content.clientId, content.roomId);
    return id;
  }

  @override
  Future<void> clearNotifications(Room room) async {
    final ids = roomNotificationIds
        .remove(roomNotificationKey(room.client.identifier, room.identifier));
    if (ids == null) return;
    saveRoomNotificationIds();

    for (final id in ids) {
      // One the daemon already dropped must not keep the rest open.
      try {
        await flutterLocalNotificationsPlugin?.cancel(id);
      } catch (e) {
        Log.d("Could not close notification $id: $e");
      }
    }
  }

  /// Vommet issue 508: the room ids are also kept in the session's runtime
  /// directory (where the plugin keeps its own id map), so the notifications
  /// an earlier run showed can still be closed after a restart.
  static File? get roomNotificationIdsFile {
    final dir = Platform.environment["XDG_RUNTIME_DIR"];
    if (dir == null || dir.isEmpty) return null;
    return File(p.join(dir, "im.nether.chat-notification-rooms.json"));
  }

  Future<void> loadRoomNotificationIds() async {
    try {
      // The plugin forgets a notification once the daemon reports it closed.
      final shown =
          await flutterLocalNotificationsPlugin?.getSystemIdMap() ?? {};
      // Carry on after the ids still known, so a new notification never
      // reuses (and replaces) one from an earlier run.
      for (final id in shown.keys) {
        if (id > notificationId) notificationId = id;
      }

      final file = roomNotificationIdsFile;
      if (file == null || !await file.exists()) return;
      final saved = jsonDecode(await file.readAsString());
      if (saved is! Map) return;
      for (final entry in saved.entries) {
        final ids = entry.value is List
            ? (entry.value as List)
                .whereType<int>()
                .where(shown.containsKey)
                .toList()
            : <int>[];
        if (ids.isNotEmpty && entry.key is String) {
          roomNotificationIds[entry.key as String] = ids;
        }
      }
    } catch (e, s) {
      Log.onError(e, s);
    }
  }

  Future<void> _saving = Future.value();

  void saveRoomNotificationIds() {
    final file = roomNotificationIdsFile;
    if (file == null) return;
    final json = jsonEncode(roomNotificationIds);
    _saving = _saving.then((_) => file.writeAsString(json)).then((_) {},
        onError: (Object e) {
      Log.d("Could not save notification ids: $e");
    });
  }

  @override
  Future<void> disableBadges() async {
    service.update(countVisible: false, count: 0);
  }

  @override
  Future<void> enableBadges() async {
    updateBadgeCount();
  }
}
