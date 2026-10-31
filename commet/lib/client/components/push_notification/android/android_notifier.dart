import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:commet/client/sounds/app_sounds.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/push_notification/android/android_notification_actions.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/push_notification/notifier.dart';
import 'package:commet/client/components/push_notification/push_client_routing.dart';
import 'package:commet/client/matrix_background/matrix_background_room.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_encrypted.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/custom_uri.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/image_utils.dart';
import 'package:commet/utils/shortcuts_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

class AndroidNotifier implements Notifier {
  static String get pushFallbackNewMessage => Intl.message("New message",
      name: "pushFallbackNewMessage",
      desc:
          "Notification text (and room name if unknown) for a pushed message that can't be read yet, e.g. still encrypted");

  @override
  bool hasPermission = false;

  @override
  bool get needsToken => false;

  static const bool bubblesEnabled = true;

  FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;

  @override
  bool get enabled => true;

  @override
  Future<void> init() async {
    Log.i("Initializing notifier! is headless: $isHeadless");

    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const settings = AndroidInitializationSettings("notification_icon");
    const initSettings = InitializationSettings(android: settings);

    await flutterLocalNotificationsPlugin?.initialize(initSettings,
        onDidReceiveBackgroundNotificationResponse:
            onBackgroundNotificationResponse,
        onDidReceiveNotificationResponse: onResponse);

    if (!isHeadless) {
      checkPermission();
      // Vommet issue 603: notification Reply / Mark as read run here.
      AndroidNotificationActions.listenInMainIsolate();
    }
  }

  static Future<void> onForegroundMessage(Map<String, dynamic> message) async {
    var roomId = message["room_id"] as String?;
    var eventId = message["event_id"] as String?;
    var counts = message["counts"];
    var localClientId = PushClientRouting.localClientId(message);

    Log.i("Received message: ${jsonEncode(message)}");

    if (roomId == null || eventId == null) {
      Log.w("TODO: Handle counts: $counts");
      return;
    }

    if (localClientId == null) {
      // Vommet: the app is running, so ask the accounts themselves before
      // the cache, which can miss rooms joined since it was written.
      localClientId = clientManager?.clients
          .firstWhereOrNull((c) => c.hasRoom(roomId))
          ?.identifier;
      localClientId ??= PushClientRouting.fromRoomsListCache(roomId);
      Log.i("Found client id from the accounts' rooms: $localClientId");
    }

    if (localClientId == null) {
      Log.w("Received notification did not contain a client id!");

      return;
    }

    var client = clientManager!.getClient(localClientId);

    if (client == null) return;

    final comp = client.getComponent<InvitationComponent>();

    // Vommet issue 734: a room invite may be listed inside its space's.
    var invite = comp?.invitations.firstWhereOrNull((i) =>
        i.roomId == roomId || i.groupedRooms.any((r) => r.roomId == roomId));

    if (invite != null) {
      var content = GenericRoomInviteNotificationContent(
        content: "You received an invitation to chat!",
        title: "Room Invite",
        accountLabel: NotificationContent.accountLabelFor(client),
      );

      await NotificationManager.notify(content);

      return;
    }

    // Vommet: nothing here may drop a notification silently. An encrypted
    // message whose key hasn't arrived yet (the push often beats the sync
    // that brings it) was skipped as "not a message", and a room the client
    // didn't know yet threw on room!. Wait briefly for decryption, then fall
    // back to "New message", as the background path does.
    var room = client.getRoom(roomId);
    try {
      if (room == null) {
        await NotificationManager.notify(_fallback(client, roomId, eventId));
        return;
      }

      var event = await room.getEvent(eventId);
      for (var i = 0; i < 8 && event is TimelineEventEncrypted; i++) {
        await Future.delayed(const Duration(seconds: 1));
        event = await room.getEvent(eventId);
      }

      if (event is TimelineEventEncrypted) {
        Log.w("Push for $eventId: still encrypted, showing a fallback");
        await NotificationManager.notify(
            _fallback(client, roomId, eventId, room: room));
        // Vommet issue 693: swap in the message once its key arrives.
        unawaited(_replaceFallbackWhenReadable(client, room, eventId));
        return;
      }

      if (event is TimelineEventMessage || event is TimelineEventSticker) {
        await NotificationManager.notify(
            await _messageContent(client, room, event!, eventId));
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't handle a push for $eventId");
      await NotificationManager.notify(
          _fallback(client, roomId, eventId, room: room));
    }
  }

  static Future<MessageNotificationContent> _messageContent(
      Client client, Room room, TimelineEvent event, String eventId) async {
    var user = await room.fetchMember(event.senderId);

    bool isDirectMessage = client
            .getComponent<DirectMessagesComponent>()
            ?.isRoomDirectMessage(room) ??
        false;

    return MessageNotificationContent(
        senderName: user.displayName,
        senderId: user.identifier,
        roomName: room.displayName,
        content: event.plainTextBody,
        eventId: eventId,
        senderImageId: user.avatarId,
        roomImageId: room.avatarId,
        roomId: room.identifier,
        clientId: client.identifier,
        accountLabel: NotificationContent.accountLabelFor(client),
        senderImage: user.avatar,
        roomImage: await room.getShortcutImage(),
        isDirectMessage: isDirectMessage);
  }

  /// Vommet issue 693: how long a "New message" placeholder waits for its
  /// message to decrypt (the key usually comes with the next syncs).
  static const fallbackReplaceWindow = Duration(minutes: 30);

  /// Vommet issue 693: after each sync, look at the event again; once it
  /// decrypts, put it in the room's notification in place of the
  /// placeholder (if that is still on screen).
  static Future<void> _replaceFallbackWhenReadable(
      Client client, Room room, String eventId) async {
    final deadline = DateTime.now().add(fallbackReplaceWindow);
    try {
      while (true) {
        final left = deadline.difference(DateTime.now());
        if (left.isNegative) return;
        await client.onSync.first.timeout(left);

        final event = await room.getEvent(eventId);
        if (event is TimelineEventEncrypted) continue;
        if (event is TimelineEventMessage || event is TimelineEventSticker) {
          final content = await _messageContent(client, room, event!, eventId);
          await NotificationManager.androidNotifier
              ?.displayMessageNotification(content, replacingFallback: true);
        }
        return;
      }
    } on TimeoutException {
      Log.i("Push for $eventId: never decrypted, placeholder kept");
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't replace the placeholder");
    }
  }

  /// Vommet issue 693: a "New message" line in a notification's messages.
  /// [_fallback] sends it as the room itself, never a user.
  static bool isFallbackMessage(Message message, String roomId) =>
      message.person?.key == roomId ||
      (message.person?.key == null && message.text == pushFallbackNewMessage);

  /// Vommet: "New message" in the room, for a push whose message can't be
  /// read (yet); same as the background notification path.
  static MessageNotificationContent _fallback(
      Client client, String roomId, String eventId,
      {Room? room}) {
    final name = room?.displayName ?? pushFallbackNewMessage;
    return MessageNotificationContent(
        senderName: name,
        senderId: room?.identifier ?? roomId,
        roomName: name,
        content: pushFallbackNewMessage,
        eventId: eventId,
        roomId: roomId,
        clientId: client.identifier,
        accountLabel: NotificationContent.accountLabelFor(client),
        roomImageId: room?.avatarId,
        isDirectMessage: room != null &&
            client
                    .getComponent<DirectMessagesComponent>()
                    ?.isRoomDirectMessage(room) ==
                true);
  }

  Future<bool> checkPermission() async {
    var android = flutterLocalNotificationsPlugin!
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()!;

    hasPermission = await android.requestNotificationsPermission() ?? false;

    return hasPermission;
  }

  @override
  Future<void> notify(NotificationContent notification, {Room? room}) async {
    switch (notification) {
      case MessageNotificationContent _:
        return displayMessageNotification(notification);
      case ErrorNotificationContent _:
        return displayErrorNotification(notification);
      case CallNotificationContent _:
        return displayCallNotification(notification);
      case GenericRoomInviteNotificationContent _:
        return displayGenericInviteNotification(notification);
      default:
    }
  }

  /// [replacingFallback] (Vommet issue 693): put [content] in place of the
  /// room notification's oldest "New message" placeholder, silently; does
  /// nothing if there's no such placeholder on screen any more.
  Future<void> displayMessageNotification(MessageNotificationContent content,
      {bool replacingFallback = false}) async {
    var room = content.room;

    if (room == null) {
      var client = clientManager?.getClient(content.clientId);
      room = client?.getRoom(content.roomId);
    }

    if (room == null) {
      Log.w("Could not get room for notification");
      return;
    }

    if (room is MatrixBackgroundRoom) {
      await room.init();
    }

    if (flutterLocalNotificationsPlugin == null) {
      Log.i(
          "Flutter local notifications plugin was null. Something went wrong");
      return;
    }

    if (shortcutsManager.loading != null) {
      await shortcutsManager.loading;
    }

    Log.i("Sender name: '${content.senderName}'");
    Log.i("Room Name: '${room.displayName}'");

    Uri? userAvatar = await ShortcutsManager.getCachedAvatarImage(
        placeholderColor: room.getColorOfUser(content.senderId),
        placeholderText: content.senderName,
        imageId: content.senderImageId,
        identifier: content.senderId,
        format: ShortcutIconFormat.png,
        shouldZoomOut: false,
        imageProvider: content.senderImage);

    Uri? roomAvatar = await ShortcutsManager.getCachedAvatarImage(
        placeholderColor: room.defaultColor,
        placeholderText: content.roomName,
        imageId: content.roomImageId,
        format: ShortcutIconFormat.png,
        identifier: room.identifier,
        imageProvider: await room.getShortcutImage());

    await Future.wait([
      shortcutsManager.createShortcutForRoom(room),
    ]);

    // Vommet: with several accounts in the same room, keep each account's messages in
    // its own notification instead of merging them.
    var id = content.accountLabel == null
        ? room.identifier.hashCode
        : "${content.accountLabel}|${room.identifier}".hashCode;
    var activeStyleInfo = await AndroidFlutterLocalNotificationsPlugin()
        .getActiveNotificationMessagingStyle(id);

    var person = Person(
        name: content.senderName,
        important: true,
        bot: false,
        key: content.senderId,
        icon: userAvatar == null
            ? null
            : BitmapFilePathAndroidIcon(userAvatar.toFilePath()));

    var message = Message(
      content.content,
      DateTime.now(),
      person,
    );

    var payload =
        OpenRoomURI(roomId: content.roomId, clientId: content.clientId)
            .toString();

    if (replacingFallback) {
      final messages = activeStyleInfo?.messages;
      final index =
          messages?.indexWhere((m) => isFallbackMessage(m, content.roomId)) ??
              -1;
      if (index < 0) return;
      messages![index] =
          Message(content.content, messages[index].timestamp, person);
    } else {
      activeStyleInfo?.messages?.add(message);
    }

    var style = activeStyleInfo ??
        MessagingStyleInformation(person,
            conversationTitle:
                content.isDirectMessage ? content.roomName : null,
            groupConversation: !content.isDirectMessage,
            messages: [message]);

    // Vommet: the channel carries the chosen sound (AppSounds).
    final soundEvent =
        content.playsMentionSound ? SoundEvent.mention : SoundEvent.message;
    final channel = AppSounds.androidChannel(soundEvent);
    var details = AndroidNotificationDetails(channel.id, channel.name,
        importance: Importance.high,
        priority: Priority.high,
        icon: "notification_icon",
        number: style.messages!.length,
        largeIcon: FilePathAndroidBitmap(roomAvatar.toString()),
        subText: content.withAccountLabel(content.roomName),
        groupKey: content.roomId,
        groupAlertBehavior: GroupAlertBehavior.all,
        styleInformation: style,
        playSound: channel.playSound,
        sound: channel.sound,
        shortcutId: content.roomId,
        // Vommet issue 603.
        actions: AndroidNotificationActions.forMessage(
            clientId: content.clientId,
            roomId: content.roomId,
            eventId: content.eventId),
        // Vommet issue 719: a push rule without the sound tweak (On, not
        // Noisy) notifies silently.
        silent: replacingFallback ||
            content.priority == NotificationPriority.low ||
            !content.playsSound,
        ticker: content.content,
        bubble: bubblesEnabled
            ? BubbleMetadata(
                "im.nether.chat.BubbleActivity",
                extra: payload,
                desiredHeight: 600,
              )
            : null,
        color: const Color.fromARGB(0xff, 0x53, 0x4c, 0xdd));

    await flutterLocalNotificationsPlugin?.show(
        id, null, content.content, NotificationDetails(android: details),
        payload: payload);
    NotificationManager.noteRoomNotified(content.clientId, content.roomId);
  }

  /// Vommet: the incoming call channel, with the chosen ringtone.
  AndroidNotificationChannel get _incomingCallChannel =>
      AppSounds.androidChannel(SoundEvent.ringIncoming);

  Future<void> displayCallNotification(CallNotificationContent content) async {
    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    if (room is MatrixBackgroundRoom) {
      await room.init();
    }

    if (flutterLocalNotificationsPlugin == null) {
      Log.i(
          "Flutter local notifications plugin was null. Something went wrong");
      return;
    }

    if (shortcutsManager.loading != null) {
      await shortcutsManager.loading;
    }

    Uri? roomAvatar = await ShortcutsManager.getCachedAvatarImage(
        placeholderColor: room.defaultColor,
        placeholderText: content.roomName,
        imageId: content.roomImageId,
        format: ShortcutIconFormat.png,
        identifier: room.identifier,
        imageProvider: await room.getShortcutImage());

    var id = room.identifier.hashCode;

    var payload =
        OpenRoomURI(roomId: content.roomId, clientId: content.clientId)
            .toString();

    var details =
        AndroidNotificationDetails(_incomingCallChannel.id, "Incoming Call",
            importance: Importance.high,
            priority: Priority.high,
            icon: "notification_icon",
            timeoutAfter: 60000,
            largeIcon: FilePathAndroidBitmap(roomAvatar.toString()),
            subText: content.withAccountLabel(content.roomName),
            fullScreenIntent: true,
            playSound: _incomingCallChannel.playSound,
            sound: _incomingCallChannel.sound,
            groupKey: content.roomId,
            actions: [
              AndroidNotificationAction(
                  AcceptCallUri(
                          roomId: content.roomId,
                          callId: content.callId,
                          clientId: content.clientId)
                      .toString(),
                  "Accept",
                  showsUserInterface: true,
                  semanticAction: SemanticAction.call,
                  titleColor: Colors.green),
              AndroidNotificationAction(
                  DeclineCallUri(
                          roomId: content.roomId,
                          callId: content.callId,
                          clientId: content.clientId)
                      .toString(),
                  "Decline",
                  showsUserInterface: true,
                  semanticAction: SemanticAction.delete,
                  titleColor: Colors.red)
            ],
            groupAlertBehavior: GroupAlertBehavior.all,
            shortcutId: content.roomId,
            silent: false,
            ticker: content.content,
            color: const Color.fromARGB(0xff, 0x53, 0x4c, 0xdd));

    await flutterLocalNotificationsPlugin?.show(
        id, null, content.content, NotificationDetails(android: details),
        payload: payload);
  }

  Future<Uint8List?> getImageBytes(ImageProvider? provider) async {
    if (provider != null) {
      var data = await ImageUtils.imageProviderToImage(provider);
      var bytes = await data.toByteData(format: ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    }
    return null;
  }

  @override
  Future<bool> requestPermission() async {
    return true;
  }

  static void onResponse(NotificationResponse details) {
    Log.i(
        "Got a notification response: $details (${details.actionId}) (${details.data}) (${details.payload})");

    if (details.actionId != null) {
      var uri = CustomURI.parse(details.actionId!);
      Log.d("Parsed action uri: $uri");
      if (uri case AcceptCallUri _) {
        final session = clientManager?.callManager.currentSessions
            .where((e) =>
                e.sessionId == uri.callId &&
                e.client.identifier == uri.clientId)
            .firstOrNull;

        session?.acceptCall(withMicrophone: true);

        EventBus.doOpenRoom(uri.roomId, clientId: uri.clientId);
      }

      if (uri case DeclineCallUri _) {
        final session = clientManager?.callManager.currentSessions
            .where((e) =>
                e.sessionId == uri.callId &&
                e.client.identifier == uri.clientId)
            .firstOrNull;

        session?.declineCall();
      }
    }

    if (details.payload == null) return;

    var uri = CustomURI.parse(details.payload!);

    if (details.notificationResponseType ==
        NotificationResponseType.selectedNotification) {
      if (uri is OpenRoomURI) {
        EventBus.doOpenRoom(uri.roomId, clientId: uri.clientId);
      }
    }
  }

  @override
  Future<String?> getToken() async {
    return null;
  }

  @override
  Map<String, dynamic>? extraRegistrationData() {
    return null;
  }

  @override
  Future<void> clearNotifications(Room room) async {
    // Vommet issue 508: also before init (e.g. push not set up), since the
    // notifications may come from another isolate.
    final plugin =
        flutterLocalNotificationsPlugin ?? FlutterLocalNotificationsPlugin();
    var notifications = await plugin.getActiveNotifications();

    for (var noti in notifications) {
      if (noti.groupKey == room.identifier && noti.id != null) {
        await plugin.cancel(noti.id!);
      }
    }
  }

  /// Vommet issue 508: the rooms with a message notification on screen,
  /// whichever isolate showed it.
  Future<Set<String>> activeMessageRoomIds() async {
    final plugin =
        flutterLocalNotificationsPlugin ?? FlutterLocalNotificationsPlugin();
    final notifications = await plugin.getActiveNotifications();
    return {
      for (final noti in notifications)
        if (noti.groupKey != null && isMessageChannel(noti.channelId))
          noti.groupKey!
    };
  }

  /// Message and mention channels ("messages", "messages_<sound>", ...);
  /// not calls, invites or errors.
  static bool isMessageChannel(String? channelId) =>
      channelId != null &&
      (channelId.startsWith("messages") || channelId.startsWith("mentions"));

  Future<void> displayErrorNotification(
      ErrorNotificationContent notification) async {
    var details = AndroidNotificationDetails(
      "errors",
      "Error Messages",
      importance: Importance.high,
      priority: Priority.high,
      icon: "notification_icon",
      styleInformation: BigTextStyleInformation(notification.content),
    );

    await flutterLocalNotificationsPlugin?.show(
      Random().nextInt(1000000),
      notification.title,
      notification.content,
      NotificationDetails(android: details),
    );
  }

  Future<void> displayGenericInviteNotification(
      GenericRoomInviteNotificationContent notification) async {
    var details = AndroidNotificationDetails(
      "chat_invites",
      "Chat Invitations",
      importance: Importance.high,
      priority: Priority.high,
      icon: "notification_icon",
      subText: notification.accountLabel,
    );

    await flutterLocalNotificationsPlugin?.show(
      Random().nextInt(1000000),
      notification.title,
      notification.content,
      NotificationDetails(android: details),
    );
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
