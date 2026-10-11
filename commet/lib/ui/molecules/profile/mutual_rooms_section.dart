import 'package:commet/client/client.dart';
import 'package:commet/client/components/mutual_rooms/mutual_rooms_component.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: "Mutual Spaces" and "Mutual Rooms" on a user's profile card, as
/// collapsible rows like Discord's profile popout. Shows nothing until loaded,
/// or when you share nothing.
class MutualRoomsSection extends StatefulWidget {
  const MutualRoomsSection(
      {super.key,
      required this.client,
      required this.userId,
      this.onOpenRoom,
      this.onOpenSpace});

  final Client client;
  final String userId;
  final void Function(Room room)? onOpenRoom;
  final void Function(Space space)? onOpenSpace;

  @override
  State<MutualRoomsSection> createState() => _MutualRoomsSectionState();
}

class _MutualRoomsSectionState extends State<MutualRoomsSection> {
  MutualRooms? mutual;
  bool spacesOpen = false;
  bool roomsOpen = false;

  String labelMutualSpaces(int count) => Intl.message("Mutual Spaces — $count",
      args: [count],
      name: "labelMutualSpaces",
      desc: "Heading on a user's profile for the spaces you both belong to");

  String labelMutualRooms(int count) => Intl.message("Mutual Rooms — $count",
      args: [count],
      name: "labelMutualRooms",
      desc: "Heading on a user's profile for the rooms you are both in");

  String labelMemberCount(int count) => Intl.plural(count,
      one: "$count member",
      other: "$count members",
      args: [count],
      name: "labelMemberCount",
      desc: "How many people have joined a space or room");

  String get labelNotInASpace => Intl.message("Not in a space",
      name: "labelNotInASpace",
      desc: "Shown under a room that doesn't belong to any of your spaces");

  @override
  void initState() {
    super.initState();
    widget.client
        .getComponent<MutualRoomsComponent>()
        ?.getMutualRooms(widget.userId)
        .then((value) {
      if (mounted) setState(() => mutual = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = mutual;
    if (m == null || m.isEmpty) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
          color: colors.surface, borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.spaces.isNotEmpty) ...[
            header(labelMutualSpaces(m.spaces.length), spacesOpen,
                () => setState(() => spacesOpen = !spacesOpen)),
            if (spacesOpen)
              for (final s in m.spaces) spaceRow(s, m),
          ],
          if (m.spaces.isNotEmpty && m.rooms.isNotEmpty)
            Divider(
                height: 1,
                indent: 8,
                endIndent: 8,
                color: colors.outlineVariant.withAlpha(80)),
          if (m.rooms.isNotEmpty) ...[
            header(labelMutualRooms(m.rooms.length), roomsOpen,
                () => setState(() => roomsOpen = !roomsOpen)),
            if (roomsOpen)
              for (final r in m.rooms) roomRow(r),
          ],
        ],
      ),
    );
  }

  Widget header(String text, bool open, VoidCallback onTap) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
        child: Row(children: [
          Expanded(
              child: Text(text,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600))),
          Icon(open ? Icons.expand_more : Icons.chevron_right,
              size: 20, color: theme.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  Widget spaceRow(Space space, MutualRooms m) {
    final count = m.memberCounts[space.identifier];
    return row(
      icon: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
            width: 32,
            height: 32,
            child: space.avatar != null
                ? Image(image: space.avatar!, fit: BoxFit.cover)
                : Container(
                    color: space.color,
                    alignment: Alignment.center,
                    child: Text(
                        space.displayName.characters.firstOrNull
                                ?.toUpperCase() ??
                            "",
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800)))),
      ),
      name: space.displayName,
      subtitle: count != null ? labelMemberCount(count) : null,
      onTap:
          widget.onOpenSpace == null ? null : () => widget.onOpenSpace!(space),
    );
  }

  Widget roomRow(Room room) {
    final parent = widget.client.spaces
        .where((s) => s.containsRoom(room.identifier))
        .firstOrNull;
    return row(
      icon: tiamat.Avatar(
          radius: 16,
          image: room.avatar,
          placeholderText: room.displayName,
          placeholderColor: room.defaultColor),
      name: room.displayName,
      subtitle: parent?.displayName ?? labelNotInASpace,
      onTap: widget.onOpenRoom == null ? null : () => widget.onOpenRoom!(room),
    );
  }

  Widget row(
      {required Widget icon,
      required String name,
      String? subtitle,
      VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(children: [
          icon,
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
              ])),
          if (onTap != null)
            Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }
}
