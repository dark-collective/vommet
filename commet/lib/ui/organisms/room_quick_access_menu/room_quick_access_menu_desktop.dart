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
    // The panel toggle goes last, right before the panel it shows or hides.
    final toggle =
        discord ? menu.actions.where(_isPanelToggle).firstOrNull : null;
    final actions = discord
        ? menu.actions
            .where((e) =>
                RoomActionsBar.placeOf(e) == RoomActionPlace.row &&
                !_isPanelToggle(e))
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
      spacing: 4,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        _roomMenuButton(menu.actions),
        if (toggle != null) _toggleButton(toggle),
      ],
    );
  }

  static bool _isPanelToggle(RoomQuickAccessMenuEntry e) =>
      e.icon == Icons.chevron_left || e.icon == Icons.chevron_right;

  /// Sized like the actions' buttons (15 px icons in a 40 px box), so the
  /// header's icons all look the same size.
  Widget _headerIconButton(
      {required Key key,
      required String tooltip,
      required IconData icon,
      required void Function(BuildContext buttonContext) onPressed}) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Builder(
        builder: (buttonContext) => IconButton(
          key: key,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: 15,
          color: Theme.of(context).colorScheme.secondary,
          icon: Icon(icon),
          onPressed: () => onPressed(buttonContext),
        ),
      ),
    );
  }

  Widget _toggleButton(RoomQuickAccessMenuEntry toggle) => _headerIconButton(
      key: ValueKey("room-quick-access-menu-action-${toggle.name}"),
      tooltip: toggle.name,
      icon: toggle.icon,
      onPressed: (_) => toggle.action?.call(context));

  /// The ▾ room menu (as on the room banner and the phone's row), with the
  /// actions that left the header: Widgets, Calendar, Classic call.
  Widget _roomMenuButton(List<RoomQuickAccessMenuEntry> actions) {
    return _headerIconButton(
      key: const ValueKey("room-quick-access-menu-room-menu"),
      tooltip: "Room menu",
      icon: Icons.expand_more,
      onPressed: (buttonContext) {
        final box = buttonContext.findRenderObject() as RenderBox;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        // The menu is as wide as its anchor; open it under the button,
        // right-aligned, at a usable width.
        RoomMenu.show(context, widget.room,
            anchor: Rect.fromLTRB(
                rect.right - 276, rect.top, rect.right, rect.bottom),
            extra: RoomActionsBar.menuEntries(context, actions));
      },
    );
  }

  void onChanged(event) {
    if (mounted) setState(() {});
  }
}
