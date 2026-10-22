import 'dart:async';

import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/utils/event_bus.dart';

/// A message waiting in a room's message box to be forwarded there, like
/// Telegram: it goes out when the user presses send.
class PendingForward {
  PendingForward(
      {required this.event,
      required this.timeline,
      this.showSender = true,
      this.hideCaption = false});

  final TimelineEvent event;
  final Timeline? timeline;
  final bool showSender;
  final bool hideCaption;

  PendingForward copyWith({bool? showSender, bool? hideCaption}) =>
      PendingForward(
          event: event,
          timeline: timeline,
          showSender: showSender ?? this.showSender,
          hideCaption: hideCaption ?? this.hideCaption);
}

/// Pending forwards per room, kept in memory while the app runs.
class PendingForwards {
  static final Map<String, PendingForward> _pending = {};
  static final StreamController<String> _changed =
      StreamController<String>.broadcast();

  /// Emits [keyFor] of a room whose pending forward changed.
  static Stream<String> get onChanged => _changed.stream;

  static String keyFor(Room room) =>
      "${room.client.identifier}\u0000${room.identifier}";

  static PendingForward? get(Room room) => _pending[keyFor(room)];

  static void set(Room room, PendingForward forward) {
    _pending[keyFor(room)] = forward;
    _changed.add(keyFor(room));
  }

  static void clear(Room room) {
    if (_pending.remove(keyFor(room)) != null) {
      _changed.add(keyFor(room));
    }
  }

  /// Puts [forward] in [room]'s message box and opens the room.
  static void startIn(Room room, PendingForward forward) {
    set(room, forward);
    EventBus.doOpenRoom(room.identifier, clientId: room.client.identifier);
  }
}
