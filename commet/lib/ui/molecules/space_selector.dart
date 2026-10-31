import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/dot_indicator.dart';
import 'package:commet/ui/atoms/sidebar_draggable.dart';
import 'package:commet/ui/atoms/sidebar_room_icon.dart';
import 'package:commet/ui/molecules/expanding_drop_target.dart';
import 'package:commet/ui/molecules/rail_drop_target.dart';
import 'package:commet/ui/molecules/rail_menu.dart';
import 'package:commet/ui/molecules/space_group_widget.dart';
import 'package:commet/utils/scaled_app.dart';
import 'package:commet/ui/atoms/rail_metrics.dart';
import 'package:commet/ui/atoms/rail_pill.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';
import '../atoms/space_call_badge.dart';
import '../atoms/space_icon.dart';

class SpaceSelector extends StatefulWidget {
  const SpaceSelector(this.spaces,
      {super.key,
      this.onSelected,
      this.onRoomSelected,
      this.clearSelection,
      required this.width,
      this.shouldShowAvatarForSpace,
      this.header,
      this.footer});
  final List<SidebarEntry> spaces;
  final double width;
  final Widget? header;
  final Widget? footer;
  final void Function(Space space)? onSelected;
  // Vommet: a room pinned to the sidebar was tapped (#104).
  final void Function(Room room)? onRoomSelected;
  final void Function()? clearSelection;
  final bool Function(Space space)? shouldShowAvatarForSpace;

  // Vommet: from "Sidebar icon size" (Vommet issue 506).
  static EdgeInsets get padding => RailMetrics.current.padding;

  @override
  State<SpaceSelector> createState() => SpaceSelectorState();
}

class SidebarEntryDrag {
  SidebarEntry entry;
  int originalIndex;
  String? currentFolder;

  SidebarEntryDrag(this.entry, this.originalIndex, {this.currentFolder});
}

class SpaceSelectorState extends State<SpaceSelector> {
  late List<SidebarEntry> items;

  @override
  void initState() {
    items = widget.spaces;
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(SpaceSelector oldWidget) {
    super.didUpdateWidget(oldWidget);

    setState(() {
      items = widget.spaces;
    });
  }

  Offset? dragPosition = null;

  // Vommet issue 478: a long-press on an icon let go in place opens its menu
  // on touch.
  final press = RailPressTracker();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Flexible(
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              physics:
                  BuildConfig.ANDROID ? const BouncingScrollPhysics() : null,
              // Vommet: slots smaller than the rail sit in its middle,
              // inside the scroll view so the pill at the rail's edge isn't
              // clipped (Vommet issue 506).
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    RailMetrics.current.margin,
                    MediaQuery.of(context).scale().padding.top,
                    RailMetrics.current.margin,
                    0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.header != null)
                      Padding(
                        padding: SpaceSelector.padding,
                        child: widget.header!,
                      ),
                    if (widget.header != null) const Seperator(),
                    ListView.builder(
                      shrinkWrap: true,
                      // Vommet: lets the pills reach the rail's edge.
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.all(0),
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        var data = items[index];
                        return Column(
                          children: [
                            ExpandingDropTarget<SidebarEntryDrag>(
                              onWillAcceptWithDetails: (p0) {
                                return true;
                              },
                              onAcceptWithDetails: (p0) {
                                if (p0 is DragTargetDetails) {
                                  handleSpaceOrderDropped(p0, index);
                                }
                              },
                              position: dragPosition,
                            ),
                            buildItem(context, data, index),
                            if (index == widget.spaces.length - 1)
                              ExpandingDropTarget<SidebarEntryDrag>(
                                onWillAcceptWithDetails: (p0) {
                                  return true;
                                },
                                onAcceptWithDetails: (p0) {
                                  // Vommet: after the last item, not before it.
                                  handleSpaceOrderDropped(p0, index + 1);
                                },
                                position: dragPosition,
                              ),
                          ],
                        );
                      },
                    ),
                    if (widget.footer != null)
                      Padding(
                        padding: SpaceSelector.padding,
                        child: widget.footer!,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  int adjustIndex(int targetIndex, String id) {
    int currentIndex = items.indexWhere(
      (element) => element.id == id,
    );

    if (currentIndex == -1) return targetIndex;

    if (targetIndex > currentIndex) {
      return targetIndex - 1;
    }

    return targetIndex;
  }

  void handleSpaceOrderDropped(Object p0, int index) {
    if (p0 is DragTargetDetails) {
      if (p0.data case SidebarEntryDrag data) {
        moveEntry(data, index);
      }
    }
  }

  List<Client> get clients => clientManager?.clients ?? const <Client>[];

  /// Vommet: puts the dragged item just before the item at [index] on the
  /// sidebar (or last), taking it out of its folder if it was in one.
  void moveEntry(SidebarEntryDrag data, int index) {
    var folder = data.currentFolder;
    if (folder != null) {
      SidebarEntriesComponent.of(data.entry)
          ?.removeFromFolder(data.entry, folder);
    }

    var id = data.entry.id;
    var order = SidebarEntriesComponent.idToOrder;

    // setIndex counts every entry with an order, including ones the sidebar
    // doesn't show, so find the place by the item it should go before.
    var others = order.idToOrder.entries.where((e) => e.key != id).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    var before = index < items.length ? items[index].id : null;

    if (before != id) {
      var target = before == null
          ? others.length
          : others.indexWhere((e) => e.key == before);
      if (target == -1) target = adjustIndex(index, id);
      order.setIndex(id, target);
    }

    // Vommet: a plain reorder was never saved, so it was lost on
    // restart. setIndex re-keys every entry, so save every account.
    SidebarEntriesComponent.saveAll(clients);

    if (folder != null) SidebarEntriesComponent.tidyFolder(folder, clients);
  }

  /// Vommet: whether [entry] can go in a folder (spaces and pinned rooms).
  static bool canFolder(SidebarEntry entry) =>
      entry is SpaceSidebarEntry || entry is RoomSidebarEntry;

  /// Vommet: dropping [data] on [target] after holding over it.
  void makeFolder(SidebarEntry target, SidebarEntryDrag data) {
    var componentA = SidebarEntriesComponent.of(target);
    var componentB = SidebarEntriesComponent.of(data.entry);
    if (componentA == null || componentB == null) return;

    var folderId = componentA.createFolder(target);
    componentB.addToFolder(data.entry, folderId, 1);
    SidebarEntriesComponent.saveAll(clients);
  }

  /// Vommet: the drop target around a space or pinned room on the sidebar.
  Widget dropTarget(SidebarEntry entry, int index, Widget child) {
    return RailDropTarget(
      size: widget.width,
      accepts: (data) => data.entry.id != entry.id,
      canFolder: (data) => canFolder(data.entry),
      onReorder: (data, below) => moveEntry(data, below ? index + 1 : index),
      onFolder: (data) => makeFolder(entry, data),
      // A pinned room's icon has its own right-click menu.
      child: entry is SpaceSidebarEntry ? withMenu(entry, child) : child,
    );
  }

  Widget buildItem(context, data, int index) {
    if (data case SpaceSidebarEntry i) {
      return SidebarDraggable<SidebarEntryDrag>(
        data: SidebarEntryDrag(data, index),
        onDragStarted: onDragStarted,
        onDragUpdate: onDragUpdate,
        onDragEnd: (details) => onEntryDragEnd(data, details),
        childWhenDragging: Opacity(
          opacity: 0.1,
          child: buildSpaceIcon(
              width: widget.width,
              space: i.space,
              displayName: i.space.displayName,
              placeholderColor: i.space.color,
              onUpdate: i.space.onUpdate,
              avatar: i.space.avatar),
        ),
        feedback: SizedBox(
          width: widget.width,
          height: widget.width,
          child: Opacity(
            opacity: 0.5,
            child: buildSpaceIcon(
                width: widget.width,
                space: i.space,
                placeholderColor: i.space.color,
                displayName: i.space.displayName,
                onUpdate: i.space.onUpdate,
                avatar: i.space.avatar),
          ),
        ),
        hitTestBehavior: HitTestBehavior.opaque,
        // Vommet: dropping on a space moves next to it; only holding over
        // its middle makes a folder.
        child: dropTarget(
          data,
          index,
          tiamat.Tooltip(
            text: RedactionScope.of(context)
                .roomName(i.space.displayName, i.space.identifier),
            preferredDirection: AxisDirection.right,
            child: SizedBox(
              width: widget.width,
              child: buildSpaceIcon(
                space: i.space,
                displayName: i.space.displayName,
                onUpdate: i.space.onUpdate,
                avatar: i.space.avatar,
                notificationCount: i.space.displayNotificationCount,
                // Vommet issue 719: every counted message, grey or red.
                highlightedNotificationCount: i.space.badgeCount,
                notificationNoisy: i.space.badgeNoisy,
                showAvatarForSpace:
                    widget.shouldShowAvatarForSpace?.call(i.space) ?? false,
                userAvatar: i.space.client.self!.avatar,
                userColor: i.space.client.self!.defaultColor,
                userDisplayName: i.space.client.self!.displayName,
                width: widget.width,
                onSelected: widget.onSelected,
                placeholderColor: i.space.color,
                showCallBadge: true,
              ),
            ),
          ),
        ),
      );
    }

    // Vommet: a room pinned to the sidebar (#104). Reorders and goes in
    // folders like a space.
    if (data case RoomSidebarEntry i) {
      Widget icon(double opacity) => Opacity(
          opacity: opacity,
          child: SidebarRoomIcon(i.room, width: widget.width));

      return SidebarDraggable<SidebarEntryDrag>(
        data: SidebarEntryDrag(data, index),
        onDragStarted: onDragStarted,
        onDragUpdate: onDragUpdate,
        onDragEnd: (details) => onEntryDragEnd(data, details),
        childWhenDragging: icon(0.1),
        feedback: SizedBox(
            width: widget.width, height: widget.width, child: icon(0.5)),
        hitTestBehavior: HitTestBehavior.opaque,
        child: dropTarget(
            data,
            index,
            SidebarRoomIcon(i.room,
                width: widget.width,
                onTap: () => widget.onRoomSelected?.call(i.room))),
      );
    }

    if (data case SpaceGroupSidebarEntry i) {
      // Vommet: like a space, dropping on a closed folder moves next to it,
      // and only holding over its middle puts the item in it.
      return RailDropTarget(
          key: ValueKey("space-group-${i.groupId}"),
          size: widget.width,
          accepts: (data) =>
              data.entry.id != i.groupId &&
              data.currentFolder != i.groupId &&
              !preferences.expandedSpaceGroups.value.contains(i.groupId),
          canFolder: (data) => canFolder(data.entry),
          folderHint: "Release to add to folder",
          onReorder: (data, below) =>
              moveEntry(data, below ? index + 1 : index),
          onFolder: (data) {
            SidebarEntriesComponent.of(data.entry)
                ?.addToFolder(data.entry, i.groupId, i.members.length);
            SidebarEntriesComponent.saveAll(clients);
          },
          child: Builder(builder: (BuildContext context) {
            return SpaceGroupWidget(
              spaces: i.members,
              width: widget.width,
              folderId: i.groupId,
              initiallyOpen:
                  preferences.expandedSpaceGroups.value.contains(i.groupId),
              onExpansionStateChanged: (expanded) {
                if (expanded &&
                    !preferences.expandedSpaceGroups.value
                        .contains(i.groupId)) {
                  preferences.expandedSpaceGroups.add(i.groupId);
                } else {
                  preferences.expandedSpaceGroups.remove(i.groupId);
                }
              },
              onSelected: widget.onSelected,
              onRoomSelected: widget.onRoomSelected,
              onDragStarted: onDragStarted,
              onDragUpdate: onDragUpdate,
              dragPosition: dragPosition,
              onDragEnd: onDragEnd,
              shouldShowAvatarForSpace: (space) =>
                  widget.shouldShowAvatarForSpace?.call(space) ?? false,
            );
          }));
    }

    return SizedBox(
        width: widget.width, height: widget.width, child: Placeholder());
  }

  void onDragEnd(details) {
    setState(() {
      dragPosition = null;
    });
  }

  /// A space or pinned room outside a folder: its menu on a long-press let
  /// go in place (Vommet issue 478).
  void onEntryDragEnd(SidebarEntry entry, DraggableDetails details) {
    onDragEnd(details);
    if (!press.stayedPut) return;

    RailMenu.showEntry(context, entry,
        position: details.offset + Offset(widget.width, widget.width / 2));
  }

  /// A space's menu on right-click (Vommet issue 478).
  Widget withMenu(SidebarEntry entry, Widget child) => GestureDetector(
      onSecondaryTapUp: (details) =>
          RailMenu.showEntry(context, entry, position: details.globalPosition),
      child: child);

  void onDragUpdate(details) {
    press.update(details);
    details.globalPosition;
    setState(() {
      dragPosition = details.globalPosition;
    });
  }

  void onDragStarted() {
    press.start();
    setState(() {
      dragPosition = null;
    });
  }

  static Widget buildSpaceIcon(
      {required String displayName,
      Stream<void>? onUpdate,
      ImageProvider? avatar,
      ImageProvider? userAvatar,
      Color? userColor,
      String? userDisplayName,
      Color? placeholderColor,
      required double width,
      void Function(Space space)? onSelected,
      bool railPill = true,
      bool showAvatarForSpace = false,
      int highlightedNotificationCount = 0,
      bool notificationNoisy = true,
      int notificationCount = 0,
      bool showCallBadge = false,
      required Space space}) {
    // Vommet: Discord's pill on the rail's edge replaces the clipped dot and
    // the selected space's outline (not inside a collapsed folder).
    final icon = Stack(
      alignment: Alignment.centerLeft,
      children: [
        Padding(
            padding: SpaceSelector.padding,
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, RailMetrics.current.rowPadding, 0,
                  RailMetrics.current.rowPadding),
              child: SpaceIcon(
                displayName: displayName,
                onUpdate: onUpdate,
                avatar: avatar,
                userAvatar: userAvatar,
                spaceId: space.identifier,
                clientId: space.client.identifier,
                userColor: userColor,
                userDisplayName: userDisplayName,
                highlightedNotificationCount: highlightedNotificationCount,
                notificationNoisy: notificationNoisy,
                // Vommet: headphones while a call is on in the space, LIVE
                // while someone shares a screen in your call there.
                callBadge: showCallBadge ? SpaceCallBadge(space) : null,
                notificationCount: notificationCount,
                width: width,
                placeholderColor: placeholderColor,
                onTap: () {
                  onSelected?.call(space);
                },
                showUser: showAvatarForSpace,
                selectionBorder: !railPill,
              ),
            )),
        if (!railPill && notificationCount > 0) messageOverlay()
      ],
    );
    if (!railPill) return icon;
    return RailSlot(unread: spaceHasUnread(space), space: space, child: icon);
  }

  static Widget messageOverlay() {
    return const Positioned(left: -6, child: DotIndicator());
  }
}
