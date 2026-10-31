import 'package:commet/client/room.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:flutter/material.dart';

class RoomQuickAccessMenuViewMobile extends StatelessWidget {
  const RoomQuickAccessMenuViewMobile({required this.room, super.key});
  final Room room;

  @override
  Widget build(BuildContext context) {
    final menu = RoomQuickAccessMenu(room: room, context: context);

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 50,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: menu.actions
              .map((e) => AspectRatio(
                    aspectRatio: 1,
                    child: roomQuickAccessButton(context, e),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
