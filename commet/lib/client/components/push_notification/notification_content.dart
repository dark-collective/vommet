import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix_background/matrix_background_client.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_per_message_profile.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:flutter/material.dart';
import 'package:commet/main.dart';
import 'package:intl/intl.dart';

enum NotificationPriority { normal, low }

class NotificationContent {
  String title;
  String content;
  NotificationPriority priority;

  /// Vommet: which signed-in account this notification is for. Only set when more
  /// than one account is signed in, so single-account notifications stay as
  /// they were.
  String? accountLabel;

  NotificationContent(
      {required this.title,
      required this.content,
      this.priority = NotificationPriority.normal,
      this.accountLabel});

  /// The account's Matrix ID, or null when only one account is signed in.
  /// Uses the Matrix ID rather than the display name: someone with several
  /// accounts usually gives them all the same name.
  static String? accountLabelFor(Client client) {
    final accounts = preferences.getRegisteredMatrixClients()?.length ?? 0;
    if (accounts < 2) return null;

    final String? userId = switch (client) {
      MatrixClient c => c.getMatrixClient().userID,
      MatrixBackgroundClient c => c.userId,
      _ => client.self?.identifier,
    };

    if (userId == null || userId.isEmpty) return null;
    return userId;
  }

  /// [text] followed by the account label, if there is one.
  String withAccountLabel(String text) =>
      accountLabel == null ? text : "$text · $accountLabel";
}

class ErrorNotificationContent extends NotificationContent {
  ErrorNotificationContent({required super.title, required super.content});
}

class GenericRoomInviteNotificationContent extends NotificationContent {
  GenericRoomInviteNotificationContent(
      {required super.title, required super.content, super.accountLabel});
}

class MessageNotificationContent extends NotificationContent {
  String get senderName => title;
  String senderId;
  String eventId;
  String roomId;
  String clientId;
  String roomName;
  String? formattedContent;
  String? formatType;
  bool isDirectMessage;
  ImageProvider? roomImage;
  String? roomImageId;
  ImageProvider? senderImage;
  String? senderImageId;
  ImageProvider? attachedImage;
  Room? room;

  MessageNotificationContent({
    required String senderName,
    required this.senderId,
    required this.roomName,
    required super.content,
    required this.eventId,
    required this.roomId,
    required this.clientId,
    required this.isDirectMessage,
    this.formattedContent,
    this.formatType,
    this.roomImage,
    this.roomImageId,
    this.senderImage,
    this.senderImageId,
    this.attachedImage,
    this.room,
    super.accountLabel,
  }) : super(title: senderName);

  static String notificationSenderViaProfile(
          String profileName, String sender) =>
      Intl.message("$profileName via $sender",
          name: "notificationSenderViaProfile",
          desc:
              "Sender of a notification for a message which was sent with a per message profile",
          args: [profileName, sender]);

  static Future<MessageNotificationContent?> fromEvent(
      TimelineEvent msg, Room room) async {
    var user = await room.fetchMember(msg.senderId);

    var senderName = user.displayName;
    var senderImage = user.avatar;

    if (msg is TimelineEventFeaturePerMessageProfile) {
      var profile =
          (msg as TimelineEventFeaturePerMessageProfile).getPerMessageProfile();

      if (profile != null) {
        if (profile.avatar != null || profile.clearAvatar) {
          senderImage = profile.avatar;
        }

        if (profile.hasDisplayName) {
          senderName =
              notificationSenderViaProfile(profile.displayName!, senderName);
        }
      }
    }

    if (msg is TimelineEventMessage) {
      return MessageNotificationContent(
        senderName: senderName,
        senderImage: senderImage,
        senderId: user.identifier,
        roomName: room.displayName,
        roomId: room.identifier,
        roomImage: await room.getShortcutImage(),
        content: msg.body ?? "Sent a message",
        clientId: room.client.identifier,
        accountLabel: NotificationContent.accountLabelFor(room.client),
        eventId: msg.eventId,
        attachedImage:
            msg.attachments?.whereType<ImageAttachment>().firstOrNull?.image ??
                msg.attachments
                    ?.whereType<VideoAttachment>()
                    .firstOrNull
                    ?.thumbnail,
        formatType: msg.bodyFormat,
        formattedContent: msg.formattedBody,
        room: room,
        isDirectMessage: room.client
                .getComponent<DirectMessagesComponent>()
                ?.isRoomDirectMessage(room) ??
            false,
      );
    }

    if (msg is TimelineEventSticker) {
      return MessageNotificationContent(
        senderName: senderName,
        senderImage: senderImage,
        senderId: user.identifier,
        roomName: room.displayName,
        roomId: room.identifier,
        roomImage: await room.getShortcutImage(),
        content: msg.stickerName,
        clientId: room.client.identifier,
        accountLabel: NotificationContent.accountLabelFor(room.client),
        eventId: msg.eventId,
        attachedImage: msg.stickerImage,
        formattedContent: "",
        room: room,
        formatType: "chat.commet.custom.matrix_plain",
        isDirectMessage: room.client
                .getComponent<DirectMessagesComponent>()
                ?.isRoomDirectMessage(room) ??
            false,
      );
    }

    return null;
  }
}

class CallNotificationContent extends NotificationContent {
  String roomId;
  String senderId;
  String senderName;
  String roomName;
  String clientId;
  String callId;

  bool isDirectMessage;

  ImageProvider? roomImage;
  String? roomImageId;

  ImageProvider? senderImage;
  String? senderImageId;
  Room? room;

  CallNotificationContent({
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.roomName,
    required this.clientId,
    required this.callId,
    required this.isDirectMessage,
    this.senderImage,
    this.senderImageId,
    required super.title,
    required super.content,
    this.roomImage,
    this.roomImageId,
    this.room,
    super.accountLabel,
  });
}
