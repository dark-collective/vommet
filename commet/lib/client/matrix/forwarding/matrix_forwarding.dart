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
  static bool get enabled => preferences.experimentForwardMessages.value;

  static bool canForward(TimelineEvent event) {
    if (!enabled) return false;
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

  /// The content to forward: decrypted, with the latest edit as shown in
  /// [timeline].
  static matrix.Event _displayEvent(TimelineEvent event, Timeline? timeline) {
    var source = event as MatrixTimelineEvent;
    if (source is MatrixTimelineEventMessage) {
      return source.getDisplayEvent(timeline);
    }
    return source.event;
  }

  static bool canShowSender(TimelineEvent event) =>
      ForwardContent.canShowSender((event as MatrixTimelineEvent).event.type);

  static bool hasCaption(TimelineEvent event, Timeline? timeline) {
    var mx = _displayEvent(event, timeline);
    var original = ForwardContent.content(mx.content) ?? mx.content;
    return ForwardContent.hasCaption(original);
  }

  /// Sends [event] to [target]. With [showSender] the forward names the
  /// original sender and links to the original message (MSC4553); otherwise
  /// it is a plain copy.
  static Future<void> forward(
      TimelineEvent event, Timeline? timeline, Room target,
      {bool showSender = true, bool hideCaption = false}) async {
    var room = (target as MatrixRoom).matrixRoom;
    var mx = _displayEvent(event, timeline);
    var sourceRoom = mx.room;

    var via = <String>{
      if (sourceRoom.client.userID != null)
        sourceRoom.client.userID!.domain ?? "",
      mx.senderId.domain ?? "",
    }..remove("");

    var content = ForwardContent.build(
      mx.content,
      type: mx.type,
      origin: ForwardOrigin(
        sender: mx.senderId,
        roomId: sourceRoom.id,
        eventId: mx.eventId,
        originServerTs: mx.originServerTs.millisecondsSinceEpoch,
      ),
      showSender: showSender,
      hideCaption: hideCaption,
      via: via.toList(),
      displayName: (id) =>
          sourceRoom.unsafeGetUserFromMemoryOrFallback(id).calcDisplayname(),
    );

    await room.sendEvent(content, type: mx.type);
  }

  /// For received forwards: an event showing the original message in place
  /// of the "Forwarded from" fallback (MSC4553), or null if [event] is not a
  /// forward with a usable copy.
  static matrix.Event? displayEventOf(matrix.Event event) {
    if (!enabled) return null;
    var content = ForwardContent.displayContent(event.content,
        displayName: (id) =>
            event.room.unsafeGetUserFromMemoryOrFallback(id).calcDisplayname());
    if (content == null) return null;

    return matrix.Event(
      status: event.status,
      content: content,
      type: event.type,
      eventId: event.eventId,
      senderId: event.senderId,
      originServerTs: event.originServerTs,
      unsigned: event.unsigned,
      prevContent: event.prevContent,
      stateKey: event.stateKey,
      redacts: event.redacts,
      room: event.room,
      originalSource: event.originalSource,
    );
  }
}
