import 'package:commet/client/room.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: sidebar row for a room we were banned from: greyed, ban icon,
/// no badges, and a context menu with only "Dismiss".
class BannedRoomTextButton extends StatelessWidget {
  const BannedRoomTextButton(this.room,
      {this.highlight = false, this.onTap, super.key});

  final Room room;
  final bool highlight;
  final Function(Room room, {bool bypassSpecialRoomType})? onTap;

  static const double height = 37;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = highlight ? scheme.onSurface : scheme.secondary;
    return Opacity(
      opacity: 0.5,
      child: AdaptiveContextMenu(
        items: [
          ContextMenuItem(
              text: "Dismiss",
              icon: Icons.close,
              onPressed: () => room.dismissBan()),
        ],
        child: SizedBox(
          height: height,
          child: tiamat.TextButton(
            room.displayName,
            highlighted: highlight,
            icon: Icons.block,
            iconColor: color,
            textColor: color,
            softwrap: false,
            onTap: () => onTap?.call(room),
          ),
        ),
      ),
    );
  }
}
