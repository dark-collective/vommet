import 'package:commet/config/preferences/bool_preference.dart';
import 'package:flutter/foundation.dart';

/// Vommet: how much of the desktop side column shows (Vommet issue 456).
enum DesktopSideColumn {
  /// The space bar and the room list with names.
  full,

  /// The space bar and the room list drawn as room pictures only.
  compact,

  /// Neither; the room header's menu button opens them over the chat.
  hidden,
}

/// Vommet: the desktop layout gives the chat room as the window narrows.
/// The member list goes first (RoomChatLayout), then the room list shrinks to
/// room pictures, then the whole side column hides.
class ResponsiveDesktop {
  /// Narrower than this, the chat starts giving up its neighbours.
  static const minChatWidth = 400.0;

  /// The space bar's width beside the room list.
  static const spaceBarWidth = 70.0;

  /// The room list's width when it only shows room pictures.
  static const compactListWidth = 64.0;

  /// The room list collapsed to room pictures by hand, at any width. Kept
  /// here rather than in preferences.dart so no other topic's edits there
  /// can conflict with it.
  static final BoolPreference listCollapsed =
      BoolPreference("vommet_room_list_collapsed", defaultValue: false);

  /// [listCollapsed] as a listenable.
  static final collapsed = ValueNotifier<bool>(listCollapsed.value);

  static Future<void> setCollapsed(bool value) {
    collapsed.value = value;
    return listCollapsed.set(value);
  }

  /// Whether the side column is open over the chat while it's hidden.
  static final drawerOpen = ValueNotifier<bool>(false);

  /// How much of the side column fits in a window [windowWidth] wide, with
  /// the room list [listWidth] wide when it shows names.
  static DesktopSideColumn sideColumnFor(double windowWidth, double listWidth,
      {bool collapsedByHand = false}) {
    if (!collapsedByHand &&
        windowWidth - spaceBarWidth - listWidth >= minChatWidth) {
      return DesktopSideColumn.full;
    }
    if (windowWidth - spaceBarWidth - compactListWidth >= minChatWidth) {
      return DesktopSideColumn.compact;
    }
    return DesktopSideColumn.hidden;
  }
}
