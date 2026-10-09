import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_actions_bar.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:flutter/material.dart';

class RoomQuickAccessMenuViewDesktop extends StatefulWidget {
  const RoomQuickAccessMenuViewDesktop({required this.room, super.key});
  final Room room;

  @override
  State<RoomQuickAccessMenuViewDesktop> createState() =>
      _RoomQuickAccessMenuViewDesktopState();
}

class _RoomQuickAccessMenuViewDesktopState
    extends State<RoomQuickAccessMenuViewDesktop> {
  StreamSubscription? sub;

  @override
  void initState() {
    preferences.onSettingChanged.listen(onChanged);

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final menu = RoomQuickAccessMenu(room: widget.room, context: context);
    // Vommet: with the Discord-style layout the header keeps the top-row
    // actions (Invite, Call, Search) like the phone's row; the member
    // panel's tabs cover Pins and Threads, and the rest is in the ▾ menu.
    final discord = preferences.experimentBannerLayout.value;
    final actions = discord
        ? menu.actions
            .where((e) => RoomActionsBar.placeOf(e) == RoomActionPlace.row)
            .toList()
        : menu.actions;

    final row = Row(
      spacing: 4,
      mainAxisSize: MainAxisSize.min,
      children: actions
          .map((e) => SizedBox(
              width: 40,
              height: 40,
              child: KeyedSubtree(
                key: ValueKey("room-quick-access-menu-action-${e.name}"),
                child: roomQuickAccessButton(context, e, size: 15),
              )))
          .toList(),
    );
    if (!discord) return row;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [row, _roomMenuButton(menu.actions)],
    );
  }

  /// The ▾ room menu (as on the room banner and the phone's row), with the
  /// actions that left the header: Widgets, Calendar, Classic call.
  Widget _roomMenuButton(List<RoomQuickAccessMenuEntry> actions) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Builder(
        // Material's IconButton: this file's tiamat import goes away with
        // feat/call-button-states.
        builder: (buttonContext) => IconButton(
          key: const ValueKey("room-quick-access-menu-room-menu"),
          tooltip: "Room menu",
          padding: EdgeInsets.zero,
          iconSize: 20,
          color: Theme.of(context).colorScheme.secondary,
          icon: const Icon(Icons.expand_more),
          onPressed: () {
            final box = buttonContext.findRenderObject() as RenderBox;
            final rect = box.localToGlobal(Offset.zero) & box.size;
            // The menu is as wide as its anchor; open it under the button,
            // right-aligned, at a usable width.
            RoomMenu.show(context, widget.room,
                anchor: Rect.fromLTRB(
                    rect.right - 276, rect.top, rect.right, rect.bottom),
                extra: RoomActionsBar.menuEntries(context, actions));
          },
        ),
      ),
    );
  }

  void onChanged(event) {
    if (mounted) setState(() {});
  }
}
