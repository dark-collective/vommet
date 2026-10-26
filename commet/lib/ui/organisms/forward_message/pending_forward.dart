import 'dart:async';

import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/event_bus.dart';

/// A message waiting in a room's message box to be forwarded there, like
/// Telegram: it goes out when the user presses send. Several messages
/// ticked with Select wait together and go out oldest first.
///
/// The sender's name is hidden unless [showSender] says otherwise; by
/// default it follows the user's last choice ([rememberShowSender],
/// Vommet issue 657).
class PendingForward {
  PendingForward(
      {required TimelineEvent event,
      required Timeline? timeline,
      bool? showSender,
      bool hideCaption = false})
      : this.many(
            events: [event],
            timeline: timeline,
            showSender: showSender,
            hideCaption: hideCaption);

  PendingForward.many(
      {required List<TimelineEvent> events,
      required this.timeline,
      bool? showSender,
      this.hideCaption = false})
      : assert(events.isNotEmpty),
        events = List.unmodifiable(events),
        showSender = showSender ?? preferences.forwardShowSender.value;

  final List<TimelineEvent> events;
  final Timeline? timeline;
  final bool showSender;
  final bool hideCaption;

  TimelineEvent get event => events.first;

  PendingForward copyWith({bool? showSender, bool? hideCaption}) =>
      PendingForward.many(
          events: events,
          timeline: timeline,
          showSender: showSender ?? this.showSender,
          hideCaption: hideCaption ?? this.hideCaption);

  /// The rest of this forward after its first [sent] messages went out.
  PendingForward? withoutFirst(int sent) => sent >= events.length
      ? null
      : PendingForward.many(
          events: events.sublist(sent),
          timeline: timeline,
          showSender: showSender,
          hideCaption: hideCaption);

  /// Keeps the user's sender-name choice for the next forward.
  static void rememberShowSender(bool showSender) {
    if (preferences.forwardShowSender.value != showSender) {
      preferences.forwardShowSender.set(showSender);
    }
  }
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
