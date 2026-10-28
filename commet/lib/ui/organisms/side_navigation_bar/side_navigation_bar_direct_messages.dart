import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/rail_metrics.dart';
import 'package:commet/ui/atoms/space_icon.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';

class SideNavigationBarDirectMessages extends StatefulWidget {
  const SideNavigationBarDirectMessages(this.directMessages,
      {super.key, this.onRoomTapped, this.filterClient});
  final DirectMessagesInterface directMessages;
  final Client? filterClient;

  final void Function(Room room)? onRoomTapped;

  @override
  State<SideNavigationBarDirectMessages> createState() =>
      _SideNavigationBarDirectMessagesState();
}

class _SideNavigationBarDirectMessagesState
    extends State<SideNavigationBarDirectMessages> {
  late List<Room> rooms;
  Client? filterClient;

  late List<StreamSubscription> subscriptions;

  @override
  void initState() {
    super.initState();
    filterClient = widget.filterClient;

    rooms = widget.directMessages.highlightedRoomsList;
    subscriptions = [
      EventBus.setFilterClient.stream.listen(setFilterClient),
      widget.directMessages.highlightedRoomsList.onListUpdated
          .listen(onListUpdated),
    ];
  }

  @override
  void dispose() {
    for (var element in subscriptions) {
      element.cancel();
    }

    super.dispose();
  }

  void setFilterClient(Client? event) {
    setState(() {
      filterClient = event;
    });

    onListUpdated(null);
  }

  void onListUpdated(void event) {
    setState(() {
      rooms = widget.directMessages.highlightedRoomsList;

      if (filterClient != null) {
        rooms = rooms.where((i) => i.client == filterClient).toList();
      }
    });
  }

  // Vommet: pinned rooms have their own sidebar icon (#104), and the newest
  // unread DM goes on top like Discord (#105). Done at build time so a new
  // message in an already-unread DM re-sorts on the parent's rebuild.
  List<Room> get visibleRooms {
    var result = onePerPerson(rooms);

    if (preferences.experimentSidebarPinnedRooms.value) {
      result = result
          .where((room) =>
              room.client
                  .getComponent<SidebarEntriesComponent>()
                  ?.isRoomPinned(room) !=
              true)
          .toList();
    }

    if (preferences.experimentSidebarNewestUnreadDms.value) {
      result = result.toList()
        ..sort((a, b) => b.lastEventTimestamp.compareTo(a.lastEventTimestamp));
    }

    return result;
  }

  /// Vommet issue 99: one icon per person, standing for their newest room
  /// (it may have nothing unread when an older one does).
  static List<Room> onePerPerson(List<Room> rooms) {
    final seen = <Room>{};
    final result = <Room>[];
    for (final room in rooms) {
      final shown = groupOf(room).firstOrNull ?? room;
      if (seen.add(shown)) result.add(shown);
    }
    return result;
  }

  static List<Room> groupOf(Room room) {
    final dms = room.client.getComponent<DirectMessagesComponent>();
    final partner = dms?.getDirectMessagePartnerId(room);
    return partner == null ? const [] : dms!.directMessagesWith(partner);
  }

  /// Vommet issue 99: the person's unread messages, all rooms added up.
  static int unreadWith(Room room) {
    final group = groupOf(room);
    if (group.length < 2) return room.notificationCount;
    return group.fold(0, (sum, r) => sum + r.notificationCount);
  }

  @override
  Widget build(BuildContext context) {
    var rooms = visibleRooms;
    bool empty = rooms.isEmpty;
    final rail = RailMetrics.current;

    return Padding(
      padding: EdgeInsets.fromLTRB(0, empty ? 0 : 4, 0, 0),
      child: ImplicitlyAnimatedList(
        shrinkWrap: true,
        itemData: rooms,
        padding: const EdgeInsets.all(0),
        itemBuilder: (context, data) {
          // return tiamat.Text.labelLow(data.displayName);
          return Padding(
            padding: EdgeInsetsGeometry.fromLTRB(
                0, rail.rowPadding, 0, rail.rowPadding),
            child: SpaceIcon(
              displayName: data.displayName,
              placeholderColor: data.defaultColor,
              spaceId: data.identifier,
              clientId: data.client.identifier,
              avatar: data.avatar,
              width: rail.slot,
              highlightedNotificationCount: unreadWith(data),
              onTap: () => widget.onRoomTapped?.call(data),
            ),
          );
        },
      ),
    );
  }
}
