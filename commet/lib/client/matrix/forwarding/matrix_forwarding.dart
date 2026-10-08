import 'package:commet/client/matrix/forwarding/forward_content.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/main.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixForwarding {
  static bool canForward(TimelineEvent event) {
    if (!preferences.experimentForwardMessages.value) return false;
    if (event is! MatrixTimelineEvent) return false;
    if (event.status != TimelineEventStatus.synced) return false;

    var mx = event.event;
    if (mx.redacted) return false;

    return ForwardContent.canForward(mx.type, mx.content);
  }

  /// Rooms the event can be forwarded to: ordinary rooms of the same account
  /// that the user is allowed to post in.
  static bool canForwardTo(Room room) {
    return room is MatrixRoom &&
        !room.isSpecialRoomType &&
        room.permissions.canSendMessage;
  }

  /// Sends a copy of [event] to [target]. Edited messages are forwarded with
  /// their latest content, as shown in [timeline].
  static Future<void> forward(
      TimelineEvent event, Timeline? timeline, Room target) async {
    var source = event as MatrixTimelineEvent;
    var room = (target as MatrixRoom).matrixRoom;

    matrix.Event mx = source.event;
    if (source is MatrixTimelineEventMessage) {
      mx = source.getDisplayEvent(timeline);
    }

    await room.sendEvent(ForwardContent.build(mx.content), type: mx.type);
  }
}
