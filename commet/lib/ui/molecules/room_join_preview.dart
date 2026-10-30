// Vommet: what the classic chat list's Join confirmation shows about a room
// you haven't joined yet (Vommet issue 672): avatar, name, member count, the
// space it's listed in, and the topic, so you can tell what you're joining.
import 'package:commet/client/room_preview.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomJoinPreview extends StatelessWidget {
  const RoomJoinPreview(this.room, {this.spaceName, super.key});

  final RoomPreview room;

  /// The space the room is listed in, shown after the member count.
  final String? spaceName;

  /// Taller topics scroll inside the dialog.
  static const double topicMaxHeight = 150;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dim = scheme.onSurfaceVariant;

    final members = room.numMembers;
    final meta = [
      if (members != null)
        roomJoinPreviewMembers(
            members, NumberFormat.decimalPattern().format(members)),
      if (spaceName != null && spaceName!.trim().isNotEmpty) spaceName!,
    ].join(" · ");

    final topic = room.topic?.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            tiamat.Avatar(
                radius: 20,
                image: room.avatar,
                placeholderText: room.displayName,
                placeholderColor: room.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (meta.isNotEmpty)
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            theme.textTheme.labelMedium?.copyWith(color: dim)),
                ],
              ),
            ),
          ]),
          if (topic != null && topic.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              key: const ValueKey("room-join-preview-topic"),
              constraints: const BoxConstraints(maxHeight: topicMaxHeight),
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: SingleChildScrollView(
                child: SelectableText(topic,
                    style: theme.textTheme.bodyMedium?.copyWith(color: dim)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String get roomJoinPreviewTitle => Intl.message("Join this room?",
    name: "roomJoinPreviewTitle",
    desc:
        "Title of the dialog that previews a space's room before joining it from the room list");

String roomJoinPreviewMembers(int count, String formatted) => Intl.plural(count,
    one: "1 member",
    other: "$formatted members",
    args: [count, formatted],
    name: "roomJoinPreviewMembers",
    desc:
        "Member count of a room in the dialog shown before joining it; formatted is the count with digit grouping");
