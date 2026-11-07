import 'package:commet/client/client.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: at the top of a room that continues an older one (m.room.create
/// `predecessor`), a note with a link back to the older messages.
class RoomPredecessorBanner extends StatelessWidget {
  const RoomPredecessorBanner(this.room, {super.key});

  final Room room;

  String get roomContinuesOlderOne =>
      Intl.message("This room continues an older one.",
          name: "roomContinuesOlderOne",
          desc: "Banner at the start of a room that replaced an older room");

  String roomUpgradedByOn(String user, String room, String date) =>
      Intl.message("$user upgraded $room on $date.",
          args: [user, room, date],
          name: "roomUpgradedByOn",
          desc: "Under 'This room continues an older one.': who upgraded the "
              "old room, and when");

  String get seeOlderMessages => Intl.message("See older messages",
      name: "seeOlderMessages", desc: "Opens the older room this one replaced");

  @override
  Widget build(BuildContext context) {
    final predecessor = room.replacement?.predecessor;
    if (predecessor == null) return const SizedBox.shrink();

    final oldRoom = room.replacement?.predecessorRoom;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final by = predecessor.upgradedBy;
    final at = predecessor.upgradedAt;
    final subtitle = by != null && at != null
        ? roomUpgradedByOn(by, oldRoom?.displayName ?? room.displayName,
            DateFormat.MMMd().format(at))
        : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(Icons.history, color: scheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(roomContinuesOlderOne,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (subtitle != null)
                  Text(subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
        ),
        if (oldRoom != null)
          TextButton(
              onPressed: () => EventBus.doOpenRoom(oldRoom.identifier,
                  clientId: oldRoom.client.identifier),
              child: Text(seeOlderMessages)),
      ]),
    );
  }
}
