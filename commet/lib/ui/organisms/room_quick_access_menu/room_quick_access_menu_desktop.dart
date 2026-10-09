import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
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

    return Row(
      spacing: 4,
      mainAxisSize: MainAxisSize.min,
      children: menu.actions
          .map((e) => SizedBox(
              width: 40,
              height: 40,
              child: KeyedSubtree(
                key: ValueKey("room-quick-access-menu-action-${e.name}"),
                child: roomQuickAccessButton(context, e, size: 15),
              )))
          .toList(),
    );
  }

  void onChanged(event) {
    if (mounted) setState(() {});
  }
}
