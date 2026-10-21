import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/room_preview.dart';
import 'package:commet/client/space_child.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/room_preview_text_button.dart';
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/ui/atoms/subspace_section.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/room_list_navigation.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:flutter/material.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceList extends StatefulWidget {
  const SpaceList(this.space,
      {this.onRoomSelected,
      this.isTopLevel = true,
      this.currentDepth = 0,
      this.maxDepth = 5,
      super.key});
  final Function(Room room, {bool bypassSpecialRoomType})? onRoomSelected;

  final bool isTopLevel;

  final Space space;

  final int maxDepth;

  final int currentDepth;

  @override
  State<SpaceList> createState() => _SpaceListState();
}

class _SpaceListState extends State<SpaceList> {
  late List<RoomPreview> previews;

  late List<SpaceChild> children;

  late List<StreamSubscription> subs;

  // Vommet issue 457: start from the open room. Only later changes came
  // through the event, so a list built after the pick (switching back to a
  // space) marked no room as selected.
  Room? selectedRoom = EventBus.selectedRoom;
  String get labelRoomsList => Intl.message("Rooms",
      desc: "Header label for the list of rooms", name: "labelRoomsList");

  @override
  void initState() {
    children = widget.space.children;
    previews = widget.space.childPreviews;

    subs = [
      widget.space.onChildRoomPreviewAdded
          .listen((_) => onPreviewListChanged()),
      widget.space.onChildRoomPreviewsUpdated
          .listen((_) => onPreviewListChanged()),
      widget.space.onChildRoomPreviewRemoved
          .listen((_) => onPreviewListChanged()),
      EventBus.onSelectedRoomChanged.stream.listen(onRoomSelected),
      widget.space.onUpdate.listen(onSpaceUpdated),
      widget.space.onChildSpaceAdded.listen(onSpaceUpdated),
      widget.space.onChildSpaceRemoved.listen(onSpaceUpdated),
      widget.space.onRoomAdded.listen(onRoomUpdated),
      widget.space.onRoomRemoved.listen(onRoomUpdated),
      for (var room in widget.space.rooms) room.onUpdate.listen(onRoomUpdated),
      preferences.onSettingChanged.listen((_) => setState(() {})),
    ];

    // Vommet: load the rooms we haven't joined for subspaces too. Only the
    // space picked in the rail loaded them (main_page selectSpace), so a
    // subspace whose rooms you hadn't joined showed as an empty header.
    if (!widget.space.fullyLoaded) {
      widget.space.loadExtra().catchError(
          (e) => Log.w("Couldn't load ${widget.space.identifier}'s rooms: $e"));
    }

    // Vommet issues 290/499: Alt+Up/Down follow this list.
    if (widget.isTopLevel) {
      RoomListNavigation.register(this, () => visibleRooms(widget.space));
    } else {
      RoomListNavigation.subspaceShown(widget.space);
    }

    super.initState();
  }

  /// Vommet issues 290/499: the rooms in the order [build] shows them,
  /// including those of subspaces whose section is expanded.
  static List<Room> visibleRooms(Space space) {
    final children = space.children;
    return [
      for (var child in [
        ...children.where((c) => !_isBanned(c) && !_isSuperseded(c)),
        ...children.where(_isBanned),
      ])
        if (child case SpaceChildRoom c)
          c.child
        else if (child case SpaceChildSpace c
            when RoomListNavigation.isSubspaceShown(c.child))
          ...visibleRooms(c.child),
    ];
  }

  void onPreviewListChanged() {
    setState(() {
      previews = widget.space.childPreviews;
    });
  }

  void onSpaceUpdated(void event) {
    setState(() {
      children = widget.space.children;
      previews = widget.space.childPreviews;
    });
  }

  void onRoomUpdated(void event) {
    setState(() {
      children = widget.space.children;
    });
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    if (widget.isTopLevel) {
      RoomListNavigation.unregister(this);
    } else {
      RoomListNavigation.subspaceHidden(widget.space);
    }
    super.dispose();
  }

  void onRoomSelected(Room? event) {
    if (mounted)
      setState(() {
        selectedRoom = event;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Vommet: rooms we were banned from sink to the bottom; a replaced
        // room goes once you're in its replacement.
        for (var child
            in children.where((c) => !_isBanned(c) && !_isSuperseded(c)))
          buildChild(child),
        for (var child in children.where(_isBanned)) buildChild(child),
        if (preferences.showRoomPreviewsInSpaceSidebar.value)
          for (var preview in previews) buildPreviewChild(preview),
      ],
    );
  }

  static bool _isBanned(SpaceChild child) =>
      child is SpaceChildRoom && child.child.isBanned;

  static bool _isSuperseded(SpaceChild child) =>
      child is SpaceChildRoom && isSupersededRoom(child.child);

  Widget roomsList() {
    if (widget.isTopLevel) {
      return tiamat.TextButtonExpander(labelRoomsList,
          childrenPadding: const EdgeInsets.fromLTRB(2, 0, 0, 0),
          initiallyExpanded: true,
          iconColor: Theme.of(context).colorScheme.secondary,
          textColor: Theme.of(context).colorScheme.secondary,
          children: [buildRoomsList()]);
    } else {
      return buildRoomsList();
    }
  }

  Widget buildRoomsList() {
    return ImplicitlyAnimatedList(
      itemData: widget.space.rooms,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(0),
      initialAnimation: false,
      itemBuilder: (context, data) {
        return RoomTextButton(
          data,
          onTap: widget.onRoomSelected,
          highlight: selectedRoom == data,
          extraMenuItems: removeFromSpaceItems(SpaceChildRoom(data)),
        );
      },
    );
  }

  Widget buildPreviewChild(RoomPreview preview) {
    return RoomPreviewTextButton(
      preview,
      onTap: joinRoomWithConfirmation,
    );
  }

  Future<void> joinRoomWithConfirmation(RoomPreview preview) async {
    if (await AdaptiveDialog.confirmation(context,
            prompt:
                "Are you sure you want to join the room '${preview.displayName}' ?") ==
        true) {
      // Vommet: a join the server refuses shows its error.
      Room room;
      try {
        room = await widget.space.client.joinRoomFromPreview(preview);
      } catch (e, s) {
        Log.onError(e, s);
        if (mounted) AdaptiveDialog.showError(context, e, s);
        return;
      }
      await widget.onRoomSelected?.call(room);
      subs.add(room.onUpdate.listen(onRoomUpdated));
    }
  }

  /// "Remove from <space>" for a room, for people allowed to edit the space.
  List<tiamat.ContextMenuItem> removeFromSpaceItems(SpaceChildRoom child) {
    if (!widget.space.permissions.canEditChildren) return const [];
    return [
      tiamat.ContextMenuItem(
        icon: Icons.remove_circle,
        text: "Remove from ${widget.space.displayName}",
        onPressed: () async {
          final confirmed = await AdaptiveDialog.confirmation(
            context,
            title: "Remove from ${widget.space.displayName}",
            prompt:
                "Remove '${child.child.displayName}' from '${widget.space.displayName}'?\n\n"
                "The room isn't deleted and nobody is removed from it. It just "
                "won't be listed in this space any more, and you can add it "
                "back later.",
            confirmationText: "Remove",
            cancelText: "Cancel",
            dangerous: true,
          );
          if (confirmed == true) {
            await widget.space.removeChild(child);
          }
        },
      )
    ];
  }

  Widget buildChild(SpaceChild child) {
    if (child case SpaceChildSpace _) {
      if (widget.currentDepth < widget.maxDepth) {
        // Vommet: the subspace header's menu (ends in Leave Space).
        return SubspaceHeaderMenu(
          space: child.child,
          items: [
            if (widget.space.permissions.canEditChildren)
              tiamat.ContextMenuItem(
                icon: Icons.remove_circle,
                text: "Remove from ${widget.space.displayName}",
                onPressed: () async {
                  if (await AdaptiveDialog.confirmation(context) == true) {
                    widget.space.removeChild(child);
                  }
                },
              )
          ],
          child: preferences.experimentSidebarSubspaceGuides.value
              ? SubspaceSection(
                  child.child,
                  depth: widget.currentDepth,
                  child: SpaceList(
                    child.child,
                    isTopLevel: false,
                    currentDepth: widget.currentDepth + 1,
                    onRoomSelected: widget.onRoomSelected,
                  ),
                )
              : tiamat.TextButtonExpander(child.child.displayName,
                  initiallyExpanded: true,
                  childrenPadding: const EdgeInsets.fromLTRB(2, 0, 0, 0),
                  iconColor: Theme.of(context).colorScheme.secondary,
                  textColor: Theme.of(context).colorScheme.secondary,
                  children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                        child: SpaceList(
                          child.child,
                          isTopLevel: false,
                          currentDepth: widget.currentDepth + 1,
                          onRoomSelected: widget.onRoomSelected,
                        ),
                      )
                    ]),
        );
      } else {
        return tiamat.TextButton(widget.space.displayName);
      }
    }

    if (child case SpaceChildRoom _)
      return RoomTextButton(
        child.child,
        onTap: widget.onRoomSelected,
        highlight: selectedRoom == child.child,
        extraMenuItems: removeFromSpaceItems(child),
      );

    return Container();
  }
}
