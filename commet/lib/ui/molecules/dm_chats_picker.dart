import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 99: the other direct message rooms you have with a person.
/// The lists show one row per person (their newest room); these open the
/// rest: a "2 chats" chip in the room's header, a "×2" chip on the row, and
/// the picker both open.
class DmChats {
  /// Every room with [room]'s partner on its account, newest first; empty
  /// when it isn't a direct message.
  static List<Room> of(Room room) {
    final dms = room.client.getComponent<DirectMessagesComponent>();
    final partner = dms?.getDirectMessagePartnerId(room);
    if (dms == null || partner == null) return const [];
    return dms.directMessagesWith(partner);
  }

  /// A dialog (desktop) or sheet (phone) listing [room]'s person's rooms;
  /// picking one opens it.
  static Future<void> pick(BuildContext context, Room room) async {
    final rooms = of(room);
    if (rooms.length < 2) return;
    final picked = await AdaptiveDialog.pickOne<Room>(context,
        title: "Chats with ${rooms.first.displayName}",
        items: rooms,
        itemBuilder: (context, item, done) => DmChatTile(
              room: item,
              newest: identical(item, rooms.first),
              current: identical(item, room),
              onTap: done,
            ));
    if (picked == null) return;
    EventBus.doOpenRoom(picked.identifier,
        clientId: picked.client.identifier, openInSpace: false);
  }

  /// When the room was made, from its m.room.create event.
  static DateTime? createdAt(Room room) {
    if (room is! MatrixRoom) return null;
    final create = room.matrixRoom.getState(matrix.EventTypes.RoomCreate);
    return create is matrix.Event ? create.originServerTs : null;
  }
}

/// One room in [DmChats.pick]: encrypted or not, newest, when it began, its
/// last message and its own badge.
class DmChatTile extends StatelessWidget {
  const DmChatTile(
      {required this.room,
      required this.newest,
      this.current = false,
      this.onTap,
      super.key});

  final Room room;
  final bool newest;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final created = DmChats.createdAt(room);
    final last = room.lastEvent?.plainTextBody.trim() ?? "";
    final title = [
      room.isE2EE ? "Encrypted" : "Not encrypted",
      if (newest) "newest",
      if (current) "open now",
    ].join(" · ");
    final details = [
      if (created != null) "since ${DateFormat.yMMM().format(created)}",
      if (last.isNotEmpty) last,
    ].join(" · ");
    final badge = room.displayNotificationCount > 0 ||
            room.displayHighlightedNotificationCount > 0
        ? NotificationBadge(
            room.displayNotificationCount >
                    room.displayHighlightedNotificationCount
                ? room.displayNotificationCount
                : room.displayHighlightedNotificationCount,
            noisy: room.displayHighlightedNotificationCount > 0 ||
                room.messagesAreNoisy)
        : null;
    return Material(
      color: current ? scheme.surfaceContainerHighest : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Icon(room.isE2EE ? Icons.lock : Icons.lock_open,
                  size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: text.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (details.isNotEmpty)
                      Text(details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 8), badge],
            ],
          ),
        ),
      ),
    );
  }
}

/// Vommet issue 99: "2 chats" in a direct message's header when you have
/// more than one room with the person; a dot when another one is unread.
class DmChatsHeaderChip extends StatefulWidget {
  const DmChatsHeaderChip({required this.room, super.key});

  final Room room;

  @override
  State<DmChatsHeaderChip> createState() => _DmChatsHeaderChipState();
}

class _DmChatsHeaderChipState extends State<DmChatsHeaderChip> {
  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    sub = widget.room.client.onSync.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = DmChats.of(widget.room);
    if (rooms.length < 2) return const SizedBox.shrink();
    final otherUnread = rooms.any((r) =>
        !identical(r, widget.room) &&
        (r.displayNotificationCount > 0 ||
            r.displayHighlightedNotificationCount > 0));
    final scheme = Theme.of(context).colorScheme;
    final mobile = MediaQuery.of(context).mobile;
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: scheme.surfaceContainerHighest,
          shape: const StadiumBorder(),
          child: InkWell(
            key: const ValueKey("dm-chats-header-chip"),
            customBorder: const StadiumBorder(),
            onTap: () => DmChats.pick(context, widget.room),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (otherUnread) ...[
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: scheme.error, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                  ],
                  Text(
                      mobile
                          ? "${rooms.length} chats"
                          : "${rooms.length} chats with ${rooms.first.displayName}",
                      style: style),
                  Icon(Icons.arrow_drop_down, size: 18, color: scheme.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vommet issue 99: "×2" on a person's row in a list when you have more
/// than one room with them; tapping it lists them.
class DmChatsCountChip extends StatelessWidget {
  const DmChatsCountChip({required this.room, super.key});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final rooms = DmChats.of(room);
    if (rooms.length < 2 || !identical(rooms.first, room)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: "${rooms.length} chats with this person",
        child: Material(
          color: scheme.surfaceContainerHighest,
          shape: const StadiumBorder(),
          child: InkWell(
            key: ValueKey("dm-chats-count-${room.identifier}"),
            customBorder: const StadiumBorder(),
            onTap: () => DmChats.pick(context, room),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: Text("×${rooms.length}",
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600, color: scheme.onSurface)),
            ),
          ),
        ),
      ),
    );
  }
}
