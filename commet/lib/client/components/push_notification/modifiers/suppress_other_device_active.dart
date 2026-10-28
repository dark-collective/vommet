import 'dart:convert';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/sent_here.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix_background/matrix_background_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:matrix/matrix.dart'
    show Device, Direction, MatrixApi, MatrixEvent;

class NotificationModifierSuppressOtherActiveDevice
    implements NotificationModifier {
  @override
  Future<NotificationContent?> process(NotificationContent content,
      {Function(String reason)? onNotificationRejected}) async {
    if (!preferences.silenceNotifications.value) {
      return content;
    }

    if (content is! MessageNotificationContent) {
      return content;
    }

    List<Client> clients = List.empty();

    if (clientManager == null) {
      if (content.room != null) {
        clients = [content.room!.client];
      } else {
        Log.w(
            "Suppressing notifications for background client is not currently supported");
        return content;
      }
    } else {
      clients = clientManager!.clients
          .where((element) => element.hasRoom(content.roomId))
          .toList();
    }

    for (var client in clients) {
      MatrixApi? api;
      String? thisDeviceId;
      String? userId;
      if (client is MatrixClient) {
        final mx = client.getMatrixClient();
        api = mx;
        thisDeviceId = mx.deviceID;
        userId = mx.userID;
      }

      if (client is MatrixBackgroundClient) {
        api = client.api;
        thisDeviceId = client.deviceId;
        userId = client.userId;
      }

      if (api == null) continue;

      if (await _activeHere(api, content.roomId, thisDeviceId, userId)) {
        content.priority = NotificationPriority.low;
        return content;
      }
    }
    return content;
  }

  /// Vommet: how recently another device must have been seen, and how
  /// recently you must have sent something in the chat, for its notification
  /// to be quieted. 5 minutes for both: servers only refresh a device's
  /// last-seen time every couple of minutes (Synapse: 2).
  static const otherDeviceWindow = Duration(minutes: 5);
  static const ownActivityWindow = Duration(minutes: 5);

  /// Give up (and notify normally) if the server is slower than this.
  static const checkTimeout = Duration(seconds: 3);

  /// The event types that mean you were chatting.
  static const chatTypes = [
    "m.room.message",
    "m.room.encrypted",
    "m.sticker",
    "m.reaction",
  ];

  /// Vommet: true only when you are chatting in [roomId] on another device
  /// right now: another of your devices was seen in the last
  /// [otherDeviceWindow], and your latest message (or reaction) in this room
  /// is from the last [ownActivityWindow] and was not sent from this device.
  /// Upstream quieted every notification while any other device had been
  /// seen in the last 10 minutes, and a desktop client or browser tab left
  /// open keeps updating that, so one account stayed silent for good.
  Future<bool> _activeHere(MatrixApi api, String roomId, String? thisDeviceId,
      String? userId) async {
    if (userId == null) return false;
    try {
      return await _check(api, roomId, thisDeviceId, userId)
          .timeout(checkTimeout);
    } catch (e) {
      // When in doubt (error or slow server), notify normally.
      Log.w("Couldn't check for activity on other devices: $e");
      return false;
    }
  }

  Future<bool> _check(
      MatrixApi api, String roomId, String? thisDeviceId, String userId) async {
    final devices = await api.getDevices() ?? const <Device>[];
    if (!otherDeviceOnline(devices, thisDeviceId, DateTime.now())) {
      return false;
    }
    final mine = await api.getRoomEvents(roomId, Direction.b,
        limit: 5,
        filter: jsonEncode({
          "senders": [userId],
          "types": chatTypes,
        }));
    final last = lastOwnEvent(mine.chunk, userId, DateTime.now());
    if (last == null) return false;
    if (!sentElsewhere(last, await SentHere.read())) return false;
    Log.i(
        "Quieting this notification: you sent something in this room from another device in the last ${ownActivityWindow.inMinutes} minutes, and it is online");
    return true;
  }

  /// Another device than [thisDeviceId] was seen within [otherDeviceWindow].
  static bool otherDeviceOnline(
      Iterable<Device> devices, String? thisDeviceId, DateTime now) {
    return devices.any((device) {
      if (device.deviceId == thisDeviceId) return false;
      final seen = device.lastSeenTs;
      if (seen == null) return false;
      return now.difference(DateTime.fromMillisecondsSinceEpoch(seen)) <
          otherDeviceWindow;
    });
  }

  /// [userId]'s latest chat event within [ownActivityWindow], or null;
  /// [events] are newest first.
  static MatrixEvent? lastOwnEvent(
      Iterable<MatrixEvent> events, String userId, DateTime now) {
    for (final event in events) {
      if (now.difference(event.originServerTs) > ownActivityWindow) break;
      if (event.senderId == userId &&
          event.stateKey == null &&
          chatTypes.contains(event.type)) {
        return event;
      }
    }
    return null;
  }

  /// [last] was sent from another device: this one didn't record sending it.
  static bool sentElsewhere(MatrixEvent last, Set<String> sentHere) =>
      !sentHere.contains(last.eventId);
}
