import 'package:commet/client/room.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/widgets.dart';

/// Vommet issue 894: Reply in the media viewer's ⋮ menu. Starts a reply to
/// that one picture or video (its own event, so other clients show a normal
/// reply to it) in the chat on screen. Null when no chat of [room] is on
/// screen to take it. The viewer closes first (whoever opened it does
/// that); [jump] (opened from the Media tab) also scrolls the chat to the
/// message, which closes the room info.
VoidCallback? replyFromViewer(Room room, TimelineEvent? event,
    {bool jump = false}) {
  if (event == null || ChatState.replyTarget(room, event.eventId) == null) {
    return null;
  }
  return () {
    if (jump) {
      EventBus.jumpToEvent.add(event.eventId);
      EventBus.focusTimeline.add(null);
    }
    ChatState.replyTarget(room, event.eventId)
        ?.setInteractingEvent(event, type: EventInteractionType.reply);
  };
}
