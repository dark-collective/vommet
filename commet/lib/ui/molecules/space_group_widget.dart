import 'dart:async';

import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/client/space.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/rail_metrics.dart';
import 'package:commet/ui/atoms/rail_pill.dart';
import 'package:commet/ui/atoms/sidebar_draggable.dart';
import 'package:commet/ui/molecules/expanding_drop_target.dart';
import 'package:commet/ui/molecules/rail_menu.dart';
import 'package:commet/ui/atoms/sidebar_room_icon.dart';
import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/space_selector.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceGroupWidget extends StatefulWidget {
  const SpaceGroupWidget(
      {required this.spaces,
      this.onSelected,
      this.onRoomSelected,
      required this.folderId,
      this.width = 44,
      this.onDragEnd,
      this.onDragCompleted,
      this.onDragStarted,
      this.onDragUpdate,
      this.dragPosition,
      this.initiallyOpen = false,
      this.onExpansionStateChanged,
      this.shouldShowAvatarForSpace,
      super.key});
  // Vommet: the folder's spaces and pinned rooms.
  final List<SidebarEntry> spaces;
  final double width;
  final String folderId;
  final bool initiallyOpen;
  final Offset? dragPosition;
  final VoidCallback? onDragStarted;
  final DragUpdateCallback? onDragUpdate;
  final DragEndCallback? onDragEnd;
  final VoidCallback? onDragCompleted;
  final void Function(bool expanded)? onExpansionStateChanged;
  final bool Function(Space space)? shouldShowAvatarForSpace;

  final void Function(Space space)? onSelected;
  // Vommet: a pinned room in the folder was tapped.
  final void Function(Room room)? onRoomSelected;
  @override
  State<SpaceGroupWidget> createState() => _SpaceGroupWidgetState();
}

class _SpaceGroupWidgetState extends State<SpaceGroupWidget> {
  late bool expanded;

  double get shrink => 9;

  double get dragDropAreaSize => 40;

  double get expandedHeight =>
      (widget.spaces.length + 1) * (widget.width - shrink) +
      shrink +
      (dragPosition == null ? 0 : widget.spaces.length * dragDropAreaSize);

  double get unexpandedHeight => widget.width;

  Offset? dragPosition;

  late List<SidebarEntry> entries;

  // Vommet: a long-press let go in place opens a menu on touch.
  final press = RailPressTracker();

  (int, int) indexToCoordinate(int index) {
    var row = (index / 2).toInt();
    var column = index % 2;

    return (row, column);
  }

  int notificationCount = 0;
  int highlightNotificationCount = 0;

  void updateNotificationCounts() {
    notificationCount = 0;
    highlightNotificationCount = 0;

    for (var entry in entries) {
      switch (entry) {
        case SpaceSidebarEntry e:
          notificationCount += e.space.notificationCount;
          highlightNotificationCount += e.space.highlightedNotificationCount;
        case RoomSidebarEntry e:
          notificationCount += e.room.displayNotificationCount;
          highlightNotificationCount +=
              e.room.displayHighlightedNotificationCount;
      }
    }
  }

  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    expanded = widget.initiallyOpen;

    sub = clientManager?.onSpaceUpdated.stream.listen(onSpaceUpdated);

    updateEntries();
  }

  void onSpaceUpdated(Space event) {
    setState(() {
      updateNotificationCounts();
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  void updateEntries() {
    entries = widget.spaces.toList();
    entries.sort((a, b) => a.order.compareTo(b.order));

    dragPosition = widget.dragPosition;

    setState(() {
      updateNotificationCounts();
    });
  }

  @override
  void didUpdateWidget(covariant SpaceGroupWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    setState(() {
      dragPosition = widget.dragPosition;
      updateEntries();
    });
  }

  Duration get animationDuration => Duration(milliseconds: 300);
  Curve get curve => Curves.easeInOut;
  GlobalKey key = GlobalKey();

  BorderRadiusGeometry get radius => BorderRadiusGeometry.circular(12);

  void toggleExpansion() {
    setState(() {
      expanded = !expanded;
    });

    widget.onExpansionStateChanged?.call(expanded);
  }

  double height = 30;

  // Vommet: like Discord, a closed folder carries the rail's unread pill when
  // anything inside it is unread (the badge only counted mentions).
  bool get hasUnread => entries.any((entry) => switch (entry) {
        SpaceSidebarEntry e => spaceHasUnread(e.space),
        RoomSidebarEntry e => roomHasUnread(e.room),
        _ => false,
      });

  @override
  Widget build(BuildContext context) {
    // The open folder's spaces carry their own pills. The GlobalKey on the
    // folder's container keeps its animation across the switch.
    if (expanded) return buildFolder(context);
    // The folder spans the rail's full width from its left edge (unlike a
    // space icon, it has no SpaceSelector.padding around it), so the pill
    // sits at inset 0. An inset of the padding put it 7 px left of the
    // rail, where the scroll view clipped it away.
    return RailSlot(unread: hasUnread, child: buildFolder(context));
  }

  // Vommet: the folder's rounded clip, widened to the rail's edge so its
  // spaces' pills show when the icons are smaller (Vommet issue 506).
  Widget buildFolder(BuildContext context) => ClipPath(
      clipBehavior: Clip.hardEdge,
      clipper: _FolderClipper(radius.resolve(Directionality.of(context)),
          RailMetrics.current.margin),
      child: buildFolderBox(context));

  Widget buildFolderBox(BuildContext context) {
    return GestureDetector(
      onTap: toggleExpansion,
      onSecondaryTapUp: onSecondaryTapUp,
      child: AnimatedContainer(
        key: key,
        alignment: AlignmentGeometry.topLeft,
        decoration: BoxDecoration(borderRadius: radius),
        height: expanded ? expandedHeight : unexpandedHeight,
        duration: animationDuration,
        curve: curve,
        child: SizedBox(
          width: widget.width,
          height: expandedHeight,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: AnimatedContainer(
                  alignment: AlignmentGeometry.topLeft,
                  decoration: BoxDecoration(
                      color: ColorScheme.of(context).surfaceContainerHigh,
                      borderRadius: radius),
                  height: expanded ? expandedHeight : unexpandedHeight,
                  clipBehavior: Clip.hardEdge,
                  duration: animationDuration,
                  curve: curve,
                  child: AnimatedOpacity(
                    opacity: expanded ? 1.0 : 0,
                    duration: animationDuration,
                    child: ClipRRect(
                        borderRadius: radius,
                        child: Material(
                          color: Colors.transparent,
                          child: GestureDetector(
                            onTap: toggleExpansion,
                            onLongPress: () => showFolderMenu(null),
                            child: SizedBox(
                              width: widget.width,
                              height: widget.width - shrink,
                              child: Icon(Icons.folder),
                            ),
                          ),
                        )),
                  ),
                ),
              ),
              for (int i = 0; i < entries.length; i++) buildChild(i),
              if (expanded == false)
                SidebarDraggable<SidebarEntryDrag>(
                  data: SidebarEntryDrag(SidebarEntry(widget.folderId, ""), 0),
                  onDragCompleted: widget.onDragCompleted,
                  onDragEnd: (details) {
                    widget.onDragEnd?.call(details);
                    if (press.stayedPut) showFolderMenu(null);
                  },
                  onDragUpdate: (details) {
                    press.update(details);
                    widget.onDragUpdate?.call(details);
                  },
                  onDragStarted: () {
                    press.start();
                    widget.onDragStarted?.call();
                  },
                  feedback: SizedBox(
                    width: widget.width,
                    height: widget.width - shrink,
                    child: Icon(Icons.folder),
                  ),
                  child: MouseRegion(
                    onEnter: (event) {},
                    onExit: (event) {},
                    child: GestureDetector(
                      onTap: toggleExpansion,
                      child: Opacity(
                        opacity: 0,
                        child: SizedBox(
                          width: widget.width,
                          height: widget.width,
                        ),
                      ),
                    ),
                  ),
                ),
              Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: AnimatedScale(
                      scale: (expanded || highlightNotificationCount == 0)
                          ? 0.0
                          : 1.0,
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeOutExpo,
                      child: NotificationBadge(highlightNotificationCount),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildChild(int i) {
    var coordinates = indexToCoordinate(i);

    var size = widget.width;
    var entry = entries[i];
    Widget icon() => buildEntryIcon(entry);

    var scale = 0.4;
    var left = (coordinates.$2 * size / 2) - (size / 4);
    var top = coordinates.$1 * size / 2 - (size / 4);

    double sidePadding = 3;
    if (coordinates.$2 == 0) {
      left += sidePadding;
    } else {
      left -= sidePadding;
    }

    if (coordinates.$1 == 0) {
      top += sidePadding;
    } else {
      top -= sidePadding;
    }

    if (expanded) {
      size = widget.width;
      left = 0;
      scale = 0.999;
      top = (i + 1) * (size - shrink);
      if (dragPosition != null) {
        top += dragDropAreaSize * i;
      }
    }

    // Vommet: a pinned room in the folder.
    if (entry case RoomSidebarEntry room) {
      var draggable = memberDraggable(entry, i);
      return AnimatedPositioned(
          duration: animationDuration,
          curve: curve,
          top: top,
          left: left,
          child: AnimatedScale(
              scale: scale,
              alignment: Alignment.center,
              duration: animationDuration,
              curve: curve,
              child: draggable(Column(children: [
                if (dragPosition != null && expanded) dropGap(i),
                SizedBox(
                    width: size,
                    height: size,
                    child: SidebarRoomIcon(room.room,
                        width: widget.width,
                        extraMenuItems:
                            RailMenu.folderMemberItems(room, widget.folderId),
                        onTap: () => widget.onRoomSelected?.call(room.room))),
              ]))));
    }

    var space = entry as SpaceSidebarEntry;

    return AnimatedPositioned(
        duration: animationDuration,
        curve: curve,
        top: top,
        left: left,
        child: AnimatedScale(
          scale: scale,
          alignment: Alignment.center,
          duration: animationDuration,
          curve: curve,
          child: SidebarDraggable<SidebarEntryDrag>(
            onDragCompleted: widget.onDragCompleted,
            onDragEnd: (details) {
              widget.onDragEnd?.call(details);
              onChildDragEnd(entry, details);
            },
            onDragUpdate: (details) {
              press.update(details);
              widget.onDragUpdate?.call(details);
            },
            onDragStarted: () {
              press.start();
              widget.onDragStarted?.call();
            },
            data: SidebarEntryDrag(entry, i, currentFolder: widget.folderId),
            feedback: Opacity(
              opacity: 0.5,
              child: SizedBox(
                width: widget.width,
                height: widget.width,
                child: icon(),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.2,
              child: SizedBox(
                width: widget.width,
                height: widget.width,
                child: icon(),
              ),
            ),
            child: Column(
              children: [
                if (dragPosition != null && expanded) dropGap(i),
                tiamat.Tooltip(
                  text: space.space.displayName,
                  preferredDirection: AxisDirection.right,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: SpaceSelectorState.buildSpaceIcon(
                        displayName: space.space.displayName,
                        width: widget.width,
                        space: space.space,
                        placeholderColor: space.space.color,
                        notificationCount: space.space.notificationCount,
                        onUpdate: space.space.onUpdate,
                        highlightedNotificationCount:
                            space.space.highlightedNotificationCount,
                        onSelected: widget.onSelected,
                        railPill: expanded,
                        userAvatar: space.space.client.self?.avatar,
                        userColor: space.space.client.self?.defaultColor,
                        userDisplayName: space.space.client.self?.displayName,
                        showAvatarForSpace: widget.shouldShowAvatarForSpace
                                ?.call(space.space) ??
                            false,
                        avatar: space.space.avatar),
                  ),
                ),
              ],
            ),
          ),
        ));
  }

  /// The drop spot above the item at [i] while something is dragged.
  Widget dropGap(int i) {
    return SizedBox(
      height: dragDropAreaSize,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, 8, 0, 0),
        child: ExpandingDropTarget<SidebarEntryDrag>(
          height: dragDropAreaSize,
          distanceBasedHeight: false,
          onWillAcceptWithDetails: (p0) {
            if (p0 case SidebarEntryDrag data) {
              return SpaceSelectorState.canFolder(data.entry);
            }

            return false;
          },
          onAcceptWithDetails: (p0) {
            if (p0 is DragTargetDetails) {
              if (p0.data case SidebarEntryDrag data) {
                var entry = data.entry;
                var component = SidebarEntriesComponent.of(entry);
                if (component == null) return;

                component.addToFolder(
                    entry, widget.folderId, adjustIndex(i, entry.id));
                SidebarEntriesComponent.saveAll(clients);
              }
            }
          },
          position: dragPosition,
        ),
      ),
    );
  }

  /// A drag handle for a folder member, wired like the space ones.
  Widget Function(Widget child) memberDraggable(SidebarEntry entry, int i) {
    Widget icon() => SizedBox(
        width: widget.width,
        height: widget.width,
        child: buildEntryIcon(entry));

    return (child) => SidebarDraggable<SidebarEntryDrag>(
          onDragCompleted: widget.onDragCompleted,
          onDragEnd: (details) {
            widget.onDragEnd?.call(details);
            onChildDragEnd(entry, details);
          },
          onDragUpdate: (details) {
            press.update(details);
            widget.onDragUpdate?.call(details);
          },
          onDragStarted: () {
            press.start();
            widget.onDragStarted?.call();
          },
          data: SidebarEntryDrag(entry, i, currentFolder: widget.folderId),
          feedback: Opacity(opacity: 0.5, child: icon()),
          childWhenDragging: Opacity(opacity: 0.2, child: icon()),
          child: child,
        );
  }

  List<Client> get clients => clientManager?.clients ?? const <Client>[];

  /// Right-click: the folder's menu, or a member's when open.
  void onSecondaryTapUp(TapUpDetails details) {
    var step = widget.width - shrink;
    var row = (details.localPosition.dy / step).floor() - 1;
    if (!expanded || row < 0 || row >= entries.length) {
      showFolderMenu(details.globalPosition);
      return;
    }

    RailMenu.showEntry(context, entries[row],
        folderId: widget.folderId, position: details.globalPosition);
  }

  void showFolderMenu(Offset? position) {
    RailMenu.show(
        context,
        RailMenu.folderItems(context,
            folderId: widget.folderId,
            members: entries,
            expanded: expanded,
            toggle: toggleExpansion),
        position: position);
  }

  /// Vommet: a space or room dropped outside its folder (anywhere that
  /// isn't a drop spot) comes out and lands just below the folder; a
  /// long-press let go in place opens its menu (Vommet issue 478: the
  /// space or room menu, with "Remove from folder").
  void onChildDragEnd(SidebarEntry entry, DraggableDetails details) {
    // Before wasAccepted: the drop spot that opens above a pressed item
    // slides under the finger, so a press let go in place lands on it.
    if (press.stayedPut) {
      RailMenu.showEntry(context, entry,
          folderId: widget.folderId,
          position: details.offset + Offset(widget.width, widget.width / 2));
      return;
    }

    if (details.wasAccepted) return;

    var box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    var centre = details.offset + Offset(widget.width / 2, widget.width / 2);
    if (box.paintBounds.contains(box.globalToLocal(centre))) return;

    SidebarEntriesComponent.moveOutBelowFolder(entry, widget.folderId, clients);
  }

  /// A folder member's icon while it's dragged.
  Widget buildEntryIcon(SidebarEntry entry) {
    if (entry case RoomSidebarEntry e) {
      return SidebarRoomIcon(e.room, width: widget.width);
    }

    var space = (entry as SpaceSidebarEntry).space;
    return SpaceSelectorState.buildSpaceIcon(
        displayName: space.displayName,
        width: widget.width,
        space: space,
        placeholderColor: space.color,
        showAvatarForSpace: false,
        avatar: space.avatar);
  }

  int adjustIndex(int targetIndex, String id) {
    int currentIndex = entries.indexWhere(
      (element) => element.id == id,
    );

    if (currentIndex == -1) return targetIndex;

    if (targetIndex > currentIndex) {
      return targetIndex - 1;
    }

    return targetIndex;
  }
}

/// Vommet: clips like the folder's rounded box, [margin] further left.
class _FolderClipper extends CustomClipper<Path> {
  _FolderClipper(this.radius, this.margin);

  final BorderRadius radius;
  final double margin;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(
        radius.toRRect(Rect.fromLTRB(-margin, 0, size.width, size.height)));

  @override
  bool shouldReclip(_FolderClipper oldClipper) =>
      oldClipper.radius != radius || oldClipper.margin != margin;
}
