import 'package:commet/client/components/personal_pins/personal_pins.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_emote.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: "Pin for me" / "Unpin for me" in a message's menu. Works in any
/// room, including ones where you can't pin for everyone.
class PersonalPinMenu {
  static String get promptPinForMe => Intl.message("Pin for me",
      name: "promptPinForMe",
      desc: "Menu option to pin a message so that only you see the pin");

  static String get promptUnpinForMe => Intl.message("Unpin for me",
      name: "promptUnpinForMe",
      desc: "Menu option to remove a pin that only you see");

  static TimelineEventMenuEntry? entry(
      Room room, TimelineEvent event, void Function()? onActionFinished) {
    if (!PersonalPins.supported(room) ||
        event.status != TimelineEventStatus.synced ||
        !(event is TimelineEventMessage ||
            event is TimelineEventSticker ||
            event is TimelineEventEmote)) {
      return null;
    }
    final pinned = PersonalPins.isPinned(room, event.eventId);
    return TimelineEventMenuEntry(
      name: pinned ? promptUnpinForMe : promptPinForMe,
      icon: Icons.push_pin_outlined,
      action: (context) {
        if (pinned) {
          PersonalPins.unpin(room, event.eventId);
        } else {
          PersonalPins.pin(room, event.eventId);
        }
        onActionFinished?.call();
      },
    );
  }
}
