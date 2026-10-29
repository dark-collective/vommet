import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/room_replacement.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event_generic.dart';
import 'package:commet/client/timeline_events/timeline_event_redactable_body.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: an m.room.tombstone in the timeline ("<user> replaced this room").
class MatrixTimelineEventTombstone extends MatrixTimelineEvent
    implements TimelineEventGeneric, TimelineEventRedactableBody {
  MatrixTimelineEventTombstone(super.event, {required super.client});

  String messageUserReplacedRoom(String user) =>
      Intl.message("$user replaced this room",
          desc: "Timeline line for when a user replaced (upgraded or moved) "
              "the room",
          args: [user],
          name: "messageUserReplacedRoom");

  String messageUserReplacedRoomWithMessage(String user, String message) =>
      Intl.message("$user replaced this room: \"$message\"",
          desc: "Timeline line for when a user replaced the room, with the "
              "message they left",
          args: [user, message],
          name: "messageUserReplacedRoomWithMessage");

  @override
  IconData get icon => Icons.moving;

  @override
  String get plainTextBody => getBody();

  @override
  bool get showSenderAvatar => false;

  @override
  String getBody({Timeline? timeline}) => _bodyFor(_senderName, (m) => m);

  @override
  String redactedBody(String Function(String name, String userId) nameOf,
          String Function(String text) textOf) =>
      _bodyFor(nameOf(_senderName, event.senderId), textOf);

  String get _senderName =>
      event.senderFromMemoryOrFallback.displayName ?? event.senderId;

  String _bodyFor(String name, String Function(String text) textOf) {
    final message = parseTombstone(event.content)?.body;
    return message == null
        ? messageUserReplacedRoom(name)
        : messageUserReplacedRoomWithMessage(name, textOf(message));
  }
}
