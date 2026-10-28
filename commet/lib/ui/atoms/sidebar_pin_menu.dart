import 'package:commet/client/client.dart';
import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:intl/intl.dart';

/// Vommet: "Pin to Sidebar" / "Unpin from Sidebar" for a room's context
/// menu (#104), while the pinned rooms experiment is on.
String get sidebarPinMenuUnpin => Intl.message("Unpin from sidebar",
    name: "sidebarPinMenuUnpin",
    desc: "Room context menu item that removes the room from the sidebar");

String get sidebarPinMenuPin => Intl.message("Pin to sidebar",
    name: "sidebarPinMenuPin",
    desc: "Room context menu item that pins the room to the sidebar");

String get sidebarPinMenuUnpinFromTop => Intl.message("Unpin from top",
    name: "sidebarPinMenuUnpinFromTop",
    desc:
        "Chat list context menu item (Telegram-style list) that unpins the chat from the top of the list");

String get sidebarPinMenuPinToTop => Intl.message("Pin to top",
    name: "sidebarPinMenuPinToTop",
    desc:
        "Chat list context menu item (Telegram-style list) that pins the chat to the top of the list");

List<ContextMenuItem> sidebarPinMenuItems(Room room) {
  var sidebar = room.client.getComponent<SidebarEntriesComponent>();
  // Vommet issue 542: the Telegram-style list has no sidebar; its own rows
  // get "Pin to top" instead (topPinMenuItems).
  if (sidebar == null ||
      !preferences.experimentSidebarPinnedRooms.value ||
      unifiedChatListEnabled) {
    return const [];
  }

  if (sidebar.isRoomPinned(room)) {
    return [
      ContextMenuItem(
          text: sidebarPinMenuUnpin,
          icon: Icons.push_pin_outlined,
          onPressed: () => sidebar.setRoomPinned(room, false)),
    ];
  }

  return [
    ContextMenuItem(
        text: sidebarPinMenuPin,
        icon: Icons.push_pin,
        onPressed: () => sidebar.setRoomPinned(room, true)),
  ];
}

/// Vommet issue 542: "Pin to top" / "Unpin from top" for a chat that has its
/// own row in the Telegram-style list. The list sorts by the same pins as
/// the sidebar, so this works with the sidebar pins experiment off too.
List<ContextMenuItem> topPinMenuItems(Room room) {
  var sidebar = room.client.getComponent<SidebarEntriesComponent>();
  if (sidebar == null) return const [];

  if (sidebar.isRoomPinned(room)) {
    return [
      ContextMenuItem(
          text: sidebarPinMenuUnpinFromTop,
          icon: Icons.push_pin_outlined,
          onPressed: () => sidebar.setRoomPinned(room, false)),
    ];
  }

  return [
    ContextMenuItem(
        text: sidebarPinMenuPinToTop,
        icon: Icons.push_pin,
        onPressed: () => sidebar.setRoomPinned(room, true)),
  ];
}
