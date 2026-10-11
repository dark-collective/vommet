import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/dot_indicator.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: a room pinned to the sidebar (#104). Round, like a Discord DM,
/// so it reads differently from the rounded-square spaces.
class SidebarRoomIcon extends StatefulWidget {
  const SidebarRoomIcon(this.room,
      {required this.width, this.onTap, super.key});

  final Room room;
  final double width;
  final void Function()? onTap;

  @override
  State<SidebarRoomIcon> createState() => _SidebarRoomIconState();
}

class _SidebarRoomIconState extends State<SidebarRoomIcon> {
  late List<StreamSubscription> subs;
  bool selected = false;

  @override
  void initState() {
    super.initState();
    subs = [
      widget.room.onUpdate.listen((_) => setState(() {})),
      EventBus.onSelectedRoomChanged.stream.listen((room) => setState(() {
            selected = room?.identifier == widget.room.identifier &&
                room?.client.identifier == widget.room.client.identifier;
          })),
    ];
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var room = widget.room;
    var highlights = room.displayHighlightedNotificationCount;

    Widget icon = Stack(
      alignment: Alignment.centerLeft,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(7, 2, 7, 2),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipOval(
                    child: tiamat.ImageButton(
                      image: room.avatar,
                      onTap: widget.onTap,
                      size: widget.width,
                      placeholderColor: room.defaultColor,
                      placeholderText: room.displayName,
                    ),
                  ),
                ),
                if (selected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: ColorScheme.of(context).inverseSurface,
                              width: 3),
                        ),
                      ),
                    ),
                  ),
                if (highlights > 0)
                  Positioned(
                      right: 0, top: 0, child: NotificationBadge(highlights)),
              ],
            ),
          ),
        ),
        if (room.displayNotificationCount > 0)
          const Positioned(left: -6, child: DotIndicator()),
      ],
    );

    icon = tiamat.Tooltip(
      text: room.displayName,
      preferredDirection: AxisDirection.right,
      child: SizedBox(width: widget.width, child: icon),
    );

    // On touch, long-press drags the icon; the room list still has the menu.
    if (!MediaQuery.of(context).desktop) return icon;

    return AdaptiveContextMenu(
      items: RoomTextButton.createRoomContextMenuItems(context, room),
      child: icon,
    );
  }
}
