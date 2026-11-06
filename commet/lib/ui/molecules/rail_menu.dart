import 'dart:math';

import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/atoms/sidebar_draggable.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

/// Vommet: menus for sidebar icons that keep their drag gestures. Desktop
/// opens them with a right-click; touch with a long-press let go without
/// moving (a long-press that moves is still a drag), tracked by
/// [RailPressTracker].
class RailMenu {
  static String get railFolderClose => Intl.message("Close folder",
      name: "railFolderClose",
      desc: "Sidebar folder context menu: collapses the folder");

  static String get railFolderOpen => Intl.message("Open folder",
      name: "railFolderOpen",
      desc: "Sidebar folder context menu: expands the folder");

  static String get railFolderDelete => Intl.message("Delete folder",
      name: "railFolderDelete",
      desc: "Sidebar folder context menu: deletes the folder");

  static String railFolderDeleteNoteSpaces(int count) => Intl.plural(count,
      one: "Puts its 1 space back on the sidebar.",
      other: "Puts its $count spaces back on the sidebar.",
      args: [count],
      name: "railFolderDeleteNoteSpaces",
      desc:
          "Sidebar folder context menu: note under Delete Folder when the folder holds only spaces");

  static String railFolderDeleteNoteRooms(int count) => Intl.plural(count,
      one: "Puts its 1 room back on the sidebar.",
      other: "Puts its $count rooms back on the sidebar.",
      args: [count],
      name: "railFolderDeleteNoteRooms",
      desc:
          "Sidebar folder context menu: note under Delete Folder when the folder holds only rooms");

  static String railFolderDeleteNoteBoth(String spaces, String rooms) =>
      Intl.message("Puts its $spaces and $rooms back on the sidebar.",
          args: [spaces, rooms],
          name: "railFolderDeleteNoteBoth",
          desc:
              "Sidebar folder context menu: note under Delete Folder when the folder holds spaces and rooms; spaces is e.g. '2 spaces', rooms is e.g. '1 room'");

  static String railFolderSpaceCount(int count) => Intl.plural(count,
      one: "1 space",
      other: "$count spaces",
      args: [count],
      name: "railFolderSpaceCount",
      desc:
          "Sidebar folder context menu: number of spaces, used inside the Delete Folder note");

  static String railFolderRoomCount(int count) => Intl.plural(count,
      one: "1 room",
      other: "$count rooms",
      args: [count],
      name: "railFolderRoomCount",
      desc:
          "Sidebar folder context menu: number of rooms, used inside the Delete Folder note");

  static String get railFolderRemoveMember => Intl.message("Remove from folder",
      name: "railFolderRemoveMember",
      desc:
          "Sidebar folder context menu: on a space or room inside a folder, moves it out of the folder");

  static void show(BuildContext context, List<tiamat.ContextMenuItem> items,
      {Offset? position}) {
    if (items.isEmpty) return;

    if (position != null && MediaQuery.of(context).desktop) {
      showAt(context, items, position);
    } else {
      showSheet(context, items);
    }
  }

  static void showAt(BuildContext context, List<tiamat.ContextMenuItem> items,
      Offset position) {
    OverlayEntry? entry;
    void close() {
      entry?.remove();
      entry = null;
    }

    var theme = Theme.of(context);
    entry = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: close,
        onSecondaryTap: close,
        child: Stack(
          children: [
            Theme(
              data: theme,
              child: tiamat.ContextMenuOverlay(
                  globalOffset: position, items: items, close: close),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(entry!);
  }

  static void showSheet(
      BuildContext context, List<tiamat.ContextMenuItem> items) {
    showModalBottomSheet(
      isDismissible: true,
      showDragHandle: true,
      context: context,
      builder: (modalContext) => SingleChildScrollView(
        child: ScaledSafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              spacing: 4,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var item in items)
                  if (item.customBuilder != null)
                    item.customBuilder!.call(context, () {
                      Navigator.of(modalContext).pop();
                      item.onPressed?.call();
                    }, closeMenu: () => Navigator.of(modalContext).pop())
                  else
                    SizedBox(
                      height: 50,
                      child: tiamat.TextButton(
                        item.text,
                        textColor: item.color ??
                            Theme.of(context).colorScheme.onSurface,
                        icon: item.icon,
                        onTap: () {
                          Navigator.of(modalContext).pop();
                          item.onPressed?.call();
                        },
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The folder menu: open or close it, or delete it.
  static List<tiamat.ContextMenuItem> folderItems(
    BuildContext context, {
    required String folderId,
    required List<SidebarEntry> members,
    required bool expanded,
    required VoidCallback toggle,
  }) {
    return [
      tiamat.ContextMenuItem(
        text: expanded ? railFolderClose : railFolderOpen,
        icon: expanded ? Icons.unfold_less : Icons.unfold_more,
        onPressed: toggle,
      ),
      tiamat.ContextMenuItem(
        text: railFolderDelete,
        icon: Icons.folder_off_outlined,
        color: Theme.of(context).colorScheme.error,
        onPressed: () => SidebarEntriesComponent.deleteFolder(
            folderId, clientManager?.clients ?? const []),
        customBuilder: (context, onClicked, {closeMenu}) => _itemWithNote(
          context,
          onClicked,
          text: railFolderDelete,
          note: _describe(members),
          icon: Icons.folder_off_outlined,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    ];
  }

  /// Vommet issue 478: the menu of a space or pinned room icon at
  /// [position]: a space's is the space header's menu, a room's the room
  /// list's, plus "Remove from folder" when it's in folder [folderId].
  static void showEntry(BuildContext context, SidebarEntry entry,
      {String? folderId, required Offset position}) {
    if (entry case SpaceSidebarEntry e) {
      var space = e.space;
      var items = SpaceMenu.entries(context, space);
      if (folderId != null) {
        // After "Leave space", above the guide question, which stays last.
        final leave = items.indexWhere((e) => e.dangerous);
        items.insert(
            leave + 1,
            SpaceMenuEntry(
                railFolderRemoveMember,
                Icons.drive_file_move_outline,
                () => _removeFromFolder(entry, folderId)));
      }
      showEntryMenu(context, items,
          // The popup opens just below and right of the pointer, 264 px
          // wide.
          anchor: Rect.fromLTWH(position.dx - 8, position.dy - 4, 280, 0),
          title: MediaQuery.of(context).mobile
              ? RedactionScope.of(context)
                  .roomName(space.displayName, space.identifier)
              : null);
      return;
    }

    if (entry case RoomSidebarEntry e) {
      show(
          context,
          [
            if (folderId != null) ...folderMemberItems(entry, folderId),
            ...RoomTextButton.createRoomContextMenuItems(context, e.room),
          ],
          position: position);
    }
  }

  static void _removeFromFolder(SidebarEntry entry, String folderId) =>
      SidebarEntriesComponent.moveOutBelowFolder(
          entry, folderId, clientManager?.clients ?? const []);

  /// The menu on a space or room inside a folder.
  static List<tiamat.ContextMenuItem> folderMemberItems(
      SidebarEntry entry, String folderId) {
    return [
      tiamat.ContextMenuItem(
        text: railFolderRemoveMember,
        icon: Icons.drive_file_move_outline,
        onPressed: () => _removeFromFolder(entry, folderId),
      ),
    ];
  }

  static String _describe(List<SidebarEntry> members) {
    var spaces = members.whereType<SpaceSidebarEntry>().length;
    var rooms = members.whereType<RoomSidebarEntry>().length;
    if (spaces > 0 && rooms > 0) {
      return railFolderDeleteNoteBoth(
          railFolderSpaceCount(spaces), railFolderRoomCount(rooms));
    }
    if (spaces > 0) return railFolderDeleteNoteSpaces(spaces);
    return railFolderDeleteNoteRooms(rooms);
  }

  static Widget _itemWithNote(BuildContext context, VoidCallback onClicked,
      {required String text,
      required String note,
      required IconData icon,
      required Color color}) {
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onClicked,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      tiamat.Text(text,
                          type: tiamat.TextType.body,
                          maxLines: 1,
                          color: color),
                      tiamat.Text.labelLow(note),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vommet: tells a long-press let go in place (open the menu) from a drag,
/// on touch where [SidebarDraggable] uses long-press.
class RailPressTracker {
  Offset? _start;
  double _travel = 0;

  void start() {
    _start = null;
    _travel = 0;
  }

  void update(DragUpdateDetails details) {
    _start ??= details.globalPosition;
    _travel = max(_travel, (details.globalPosition - _start!).distance);
  }

  /// Whether the press that just ended should open the menu.
  bool get stayedPut => SidebarDraggable.useLongPress && _travel < 12;
}
