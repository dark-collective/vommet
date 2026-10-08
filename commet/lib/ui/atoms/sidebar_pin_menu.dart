import 'package:commet/client/client.dart';
import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/context_menu.dart';

/// Vommet: "Pin to Sidebar" / "Unpin from Sidebar" for a room's context
/// menu (#104), while the pinned rooms experiment is on.
List<ContextMenuItem> sidebarPinMenuItems(Room room) {
  var sidebar = room.client.getComponent<SidebarEntriesComponent>();
  if (sidebar == null || !preferences.experimentSidebarPinnedRooms.value) {
    return const [];
  }

  if (sidebar.isRoomPinned(room)) {
    return [
      ContextMenuItem(
          text: "Unpin from Sidebar",
          icon: Icons.push_pin_outlined,
          onPressed: () => sidebar.setRoomPinned(room, false)),
    ];
  }

  return [
    ContextMenuItem(
        text: "Pin to Sidebar",
        icon: Icons.push_pin,
        onPressed: () => sidebar.setRoomPinned(room, true)),
  ];
}
