import 'dart:math';

import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/atoms/sidebar_draggable.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: menus for sidebar icons that keep their drag gestures. Desktop
/// opens them with a right-click; touch with a long-press let go without
/// moving (a long-press that moves is still a drag), tracked by
/// [RailPressTracker].
class RailMenu {
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
        text: expanded ? "Close Folder" : "Open Folder",
        icon: expanded ? Icons.unfold_less : Icons.unfold_more,
        onPressed: toggle,
      ),
      tiamat.ContextMenuItem(
        text: "Delete Folder",
        icon: Icons.folder_off_outlined,
        color: Theme.of(context).colorScheme.error,
        onPressed: () => SidebarEntriesComponent.deleteFolder(
            folderId, clientManager?.clients ?? const []),
        customBuilder: (context, onClicked, {closeMenu}) => _itemWithNote(
          context,
          onClicked,
          text: "Delete Folder",
          note: "Puts its ${_describe(members)} back on the sidebar",
          icon: Icons.folder_off_outlined,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    ];
  }

  /// The menu on a space or room inside a folder.
  static List<tiamat.ContextMenuItem> folderMemberItems(
      SidebarEntry entry, String folderId) {
    return [
      tiamat.ContextMenuItem(
        text: "Remove from Folder",
        icon: Icons.drive_file_move_outline,
        onPressed: () => SidebarEntriesComponent.moveOutBelowFolder(
            entry, folderId, clientManager?.clients ?? const []),
      ),
    ];
  }

  static String _describe(List<SidebarEntry> members) {
    var spaces = members.whereType<SpaceSidebarEntry>().length;
    var rooms = members.whereType<RoomSidebarEntry>().length;
    String count(int n, String word) => "$n $word${n == 1 ? "" : "s"}";

    return [
      if (spaces > 0) count(spaces, "space"),
      if (rooms > 0) count(rooms, "room"),
    ].join(" and ");
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
