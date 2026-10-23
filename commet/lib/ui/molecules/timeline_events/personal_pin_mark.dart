import 'package:commet/client/components/personal_pins/personal_pins.dart';
import 'package:commet/client/room.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: a small outline pin next to the time on a message you pinned for
/// yourself. Room-wide pins use the filled pin.
class PersonalPinMark extends StatelessWidget {
  const PersonalPinMark({required this.room, required this.eventId, super.key});
  final Room room;
  final String eventId;

  static String get labelPinnedForYou => Intl.message("Pinned for you",
      name: "labelPinnedForYou",
      desc: "Tooltip of the mark on a message you pinned only for yourself");

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: PersonalPins.changed,
      builder: (context, _, __) {
        if (!PersonalPins.isPinned(room, eventId)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Tooltip(
            message: labelPinnedForYou,
            child: Icon(Icons.push_pin_outlined,
                key: const ValueKey("message-personal-pin-mark"),
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        );
      },
    );
  }
}
