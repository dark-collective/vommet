import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:commet/client/matrix_background/matrix_background_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/custom_uri.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

/// Vommet issue 603: Reply and Mark as read on Android message
/// notifications.
///
/// Android runs these actions in a separate background isolate. When the app
/// is running, that isolate hands the action to the main isolate, whose
/// signed-in client sends the reply or read receipt. When it isn't, Mark as
/// read goes straight to the homeserver (a read receipt isn't encrypted),
/// while a reply can't be sent without the app's encryption, so a
/// notification shows the text and opens the chat to send it again.
class AndroidNotificationActions {
  static String get replyLabel => Intl.message("Reply",
      name: "androidNotificationReplyLabel",
      desc: "Button on an Android message notification to reply from there");

  static String get replyHint => Intl.message("Reply…",
      name: "androidNotificationReplyHint",
      desc:
          "Placeholder of the reply field on an Android message notification");

  static String get markAsReadLabel => Intl.message("Mark as read",
      name: "androidNotificationMarkAsReadLabel",
      desc:
          "Button on an Android message notification that marks the chat as read");

  static String get replyNotSentTitle => Intl.message("Reply not sent",
      name: "androidNotificationReplyNotSentTitle",
      desc:
          "Title of the notification shown when a reply typed into a notification couldn't be sent because the app wasn't running");

  static String replyNotSentBody(String text) => Intl.message(
      "Vommet wasn't running. Tap to open the chat and send it again: $text",
      args: [text],
      name: "androidNotificationReplyNotSentBody",
      desc:
          "Body of the notification shown when a reply typed into a notification couldn't be sent; the text is what was typed");

  static const String portName = "im.nether.chat.notification_actions";
  static const String _scheme = "vommet-notification-action";
  static const String reply = "reply";
  static const String markRead = "mark_read";

  static String actionId(String action,
          {required String clientId,
          required String roomId,
          required String eventId}) =>
      Uri(scheme: _scheme, host: action, queryParameters: {
        "client_id": clientId,
        "room_id": roomId,
        "event_id": eventId,
      }).toString();

  static NotificationAction? parse(String? actionId) {
    if (actionId == null) return null;
    final uri = Uri.tryParse(actionId);
    if (uri == null || uri.scheme != _scheme) return null;
    if (uri.host != reply && uri.host != markRead) return null;
    // A notification posted while the app wasn't running names the
    // background client (MatrixBackgroundClient.identifier), not the account.
    final clientId = uri.queryParameters["client_id"]
        ?.replaceFirst(RegExp("^background_matrix_client:"), "");
    final roomId = uri.queryParameters["room_id"];
    final eventId = uri.queryParameters["event_id"];
    if (clientId == null || roomId == null || eventId == null) return null;
    return NotificationAction(uri.host,
        clientId: clientId, roomId: roomId, eventId: eventId);
  }

  static List<AndroidNotificationAction> forMessage(
      {required String clientId,
      required String roomId,
      required String eventId}) {
    return [
      AndroidNotificationAction(
          actionId(reply, clientId: clientId, roomId: roomId, eventId: eventId),
          replyLabel,
          inputs: [AndroidNotificationActionInput(label: replyHint)],
          semanticAction: SemanticAction.reply),
      AndroidNotificationAction(
          actionId(markRead,
              clientId: clientId, roomId: roomId, eventId: eventId),
          markAsReadLabel,
          semanticAction: SemanticAction.markAsRead),
    ];
  }

  static ReceivePort? _port;

  /// Main isolate: take the actions the background isolate hands over.
  static void listenInMainIsolate() {
    if (_port != null) return;
    final port = ReceivePort();
    _port = port;
    IsolateNameServer.removePortNameMapping(portName);
    IsolateNameServer.registerPortWithName(port.sendPort, portName);
    port.listen((message) {
      if (message is! List || message.length != 3) return;
      final ack = message[2];
      if (ack is SendPort) ack.send(true);
      final action = parse(message[0] as String?);
      if (action == null) return;
      unawaited(handleInMainIsolate(action, message[1] as String?));
    });
  }

  static Future<void> handleInMainIsolate(
      NotificationAction action, String? input) async {
    final room =
        clientManager?.getClient(action.clientId)?.getRoom(action.roomId);
    if (room == null) {
      Log.w("Notification action for an unknown room: ${action.roomId}");
      return;
    }

    try {
      final text = input?.trim() ?? "";
      if (action.action == reply && text.isNotEmpty) {
        await room.sendMessage(message: text);
      }
      // A reply marks the chat read too, as answering it on desktop does.
      await room.markAsRead();
    } catch (e, s) {
      Log.onError(e, s, content: "Notification action failed");
    }
    await NotificationManager.clearNotifications(room);
  }

  /// Background isolate (onDidReceiveBackgroundNotificationResponse).
  static Future<void> handleInBackground(NotificationResponse details) async {
    final action = parse(details.actionId);
    if (action == null) return;

    if (await _forwardToMainIsolate(details)) return;

    isHeadless = true;
    WidgetsFlutterBinding.ensureInitialized();
    await preferences.init();

    if (action.action == markRead) {
      await _markReadFromBackground(action);
    } else {
      final text = details.input?.trim() ?? "";
      if (text.isNotEmpty) await _showReplyNotSent(action, text);
    }
  }

  static Future<bool> _forwardToMainIsolate(
      NotificationResponse details) async {
    final port = IsolateNameServer.lookupPortByName(portName);
    if (port == null) return false;

    // A port left behind by an isolate that has since stopped never answers.
    final ack = ReceivePort();
    port.send([details.actionId, details.input, ack.sendPort]);
    final answered = await ack.first
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    ack.close();
    return answered == true;
  }

  static Future<void> _markReadFromBackground(NotificationAction action) async {
    final clients = preferences.getRegisteredMatrixClients();
    if (clients?.contains(action.clientId) != true) return;

    try {
      final client = MatrixBackgroundClient(databaseId: action.clientId);
      await client.init(true, isBackgroundService: true);

      final public = await _usePublicReceipts(client, action.roomId);
      await client.api.setReadMarker(action.roomId,
          mFullyRead: action.eventId,
          mRead: public ? action.eventId : null,
          mReadPrivate: public ? null : action.eventId);
    } catch (e, s) {
      Log.onError(e, s, content: "Marking a chat read from a notification");
    }
  }

  /// The room's read receipt setting, else the account's (public unless
  /// turned off), as the running app decides it.
  static Future<bool> _usePublicReceipts(
      MatrixBackgroundClient client, String roomId) async {
    const key = MatrixReadReceiptComponent.publicReadReceiptsKey;

    bool? enabled(String content) {
      final value = (jsonDecode(content) as Map?)?["enabled"];
      return value is bool ? value : null;
    }

    final db = client.database.db;
    final roomRow = await (db.select(db.roomAccountData)
          ..where((t) => t.roomId.equals(roomId) & t.type.equals(key)))
        .getSingleOrNull();
    final forRoom = roomRow == null ? null : enabled(roomRow.content);
    if (forRoom != null) return forRoom;

    final accountRow =
        client.accountData.where((row) => row.type == key).firstOrNull;
    return (accountRow == null ? null : enabled(accountRow.content)) ?? true;
  }

  static Future<void> _showReplyNotSent(
      NotificationAction action, String text) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings("notification_icon")));

    final body = replyNotSentBody(text);
    await plugin.show(
        action.roomId.hashCode,
        replyNotSentTitle,
        body,
        NotificationDetails(
            android: AndroidNotificationDetails("errors", "Error Messages",
                importance: Importance.high,
                priority: Priority.high,
                icon: "notification_icon",
                groupKey: action.roomId,
                styleInformation: BigTextStyleInformation(body))),
        payload: OpenRoomURI(roomId: action.roomId, clientId: action.clientId)
            .toString());
  }
}

class NotificationAction {
  const NotificationAction(this.action,
      {required this.clientId, required this.roomId, required this.eventId});

  final String action;
  final String clientId;
  final String roomId;
  final String eventId;
}
