import 'dart:async';

import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet experiment "Send while offline" (Telegram-style). The SDK already
/// retries a send every second on network errors, in order per room, until
/// Client.sendTimelineEventTimeout (1 minute by default; 7 days with the
/// experiment, see MatrixClient). That covers going offline while the app
/// runs. This covers a restart: messages still unsent when the app closed
/// are found in each room's "sending" timeline fragment and sent again with
/// their original transaction id, so the same bubble turns into the sent
/// message.
class OfflineSending {
  static const window = Duration(days: 7);

  // Files can't be resent after a restart: the SDK no longer has the file.
  static const _fileTypes = {
    matrix.MessageTypes.Image,
    matrix.MessageTypes.Video,
    matrix.MessageTypes.Audio,
    matrix.MessageTypes.File,
  };

  static bool _running = false;

  static Future<void> resume(matrix.Client client) async {
    if (_running) return;
    _running = true;
    var resent = 0;
    try {
      final oldest = DateTime.now().subtract(window);
      for (final room in client.rooms.toList()) {
        if (room.membership != matrix.Membership.join) continue;
        final List<matrix.Event> pending;
        try {
          pending = await client.database.getEventList(room, onlySending: true);
        } catch (e, s) {
          Log.onError(e, s, content: "Offline sending: could not read pending");
          continue;
        }
        for (final event in pending) {
          if (!(event.status.isSending || event.status.isError)) continue;
          if (event.originServerTs.isBefore(oldest)) continue;
          if (event.type == matrix.EventTypes.Message &&
              _fileTypes.contains(event.messageType)) {
            continue;
          }
          final txid = event.transactionId ?? event.eventId;
          if (room.sendingQueueEventsByTxId.contains(txid)) continue;
          resent += 1;
          // Not awaited: each waits in the room's own sending queue (in
          // order) and retries until it goes out or the window ends.
          unawaited(room
              .sendEvent(event.content, type: event.type, txid: txid)
              .catchError((Object e, StackTrace s) {
            Log.onError(e, s, content: "Offline sending: resend failed");
            return null;
          }));
        }
        // Give the UI a turn between rooms.
        await Future.delayed(Duration.zero);
      }
    } finally {
      _running = false;
      if (resent > 0) Log.i("Offline sending: resending $resent messages");
    }
  }
}
