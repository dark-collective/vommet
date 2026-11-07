import 'dart:async';

import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

// Vommet issue 1127: preflight before the SDK's destructive missing-file retry.
class SelectedSends {
  static final _running = Expando<Set<String>>();
  static bool isOwnLocal(TimelineEvent event) =>
      event is MatrixTimelineEvent &&
      (event.status.isError || event.status.isSending) &&
      event.senderId == event.event.room.client.userID;

  static String get unavailable => Intl.message('Message unavailable',
      name: 'selectedSendUnavailable',
      desc: 'Selected send cannot be resolved');
  static String get fileUnavailable =>
      Intl.message('File unavailable; attach it again.',
          name: 'selectedSendFileUnavailable',
          desc: 'Selected retry has no cached file');
  static String get unsupported =>
      Intl.message('This message cannot be retried.',
          name: 'selectedSendUnsupported',
          desc: 'Selected retry has unsupported content');
  static String get alreadySending => Intl.message('Already sending or sent',
      name: 'selectedSendAlreadySending',
      desc: 'Selected retry is no longer failed');
  static String get cannotPost => Intl.message('You cannot send to this room.',
      name: 'selectedSendCannotPost',
      desc: 'Selected retry requires posting permission');
  static String get failed =>
      Intl.message('Retry failed; select Retry to try again.',
          name: 'selectedSendFailed',
          desc: 'Selected retry failed after submission');

  static String? retryReason(TimelineEvent event) {
    if (event is! MatrixTimelineEvent ||
        !isOwnLocal(event) ||
        !event.status.isError) {
      return alreadySending;
    }
    final mx = event.event;
    final room = mx.room;
    final id = mx.transactionId ?? mx.eventId;
    if (_running[room]?.contains(id) == true ||
        room.sendingQueueEventsByTxId.contains(id)) {
      return alreadySending;
    }
    if (room.membership != matrix.Membership.join ||
        !room.canSendDefaultMessages) return cannotPost;
    if (mx.type != matrix.EventTypes.Message) return unsupported;
    if ({
          matrix.MessageTypes.Image,
          matrix.MessageTypes.Video,
          matrix.MessageTypes.Audio,
          matrix.MessageTypes.File
        }.contains(mx.messageType) &&
        !room.sendingFilePlaceholders.containsKey(mx.eventId))
      return fileUnavailable;
    return null;
  }

  // Returns after handoff; delivery belongs to the SDK's queue/retry policy.
  // The lock spans the Future and covers simultaneous room/thread selections.
  static bool retry(TimelineEvent event, void Function(String?) finished) {
    if (retryReason(event) != null) return false;
    final mx = (event as MatrixTimelineEvent).event;
    final running = _running[mx.room] ??= <String>{};
    final id = mx.transactionId ?? mx.eventId;
    running.add(id);
    unawaited(() async {
      String? error;
      try {
        if (await mx.sendAgain(txid: id) == null) error = failed;
      } catch (_) {
        error = failed;
      } finally {
        running.remove(id);
      }
      finished(error);
    }());
    return true;
  }
}
