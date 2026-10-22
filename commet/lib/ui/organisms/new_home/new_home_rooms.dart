import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';

/// Vommet (New Home): the Rooms page. "Other rooms" (the default) lists the
/// rooms you're in outside any space; "All rooms" lists every joined room
/// that isn't a DM, grouped by space, with Other rooms last.
class NewHomeRooms extends StatefulWidget {
  const NewHomeRooms({
    super.key,
    required this.clientManager,
    required this.filterClient,
    required this.phone,
  });

  final ClientManager clientManager;
  final Client? filterClient;
  final bool phone;

  @override
  State<NewHomeRooms> createState() => _NewHomeRoomsState();
}

/// A row of the flat, lazily built list.
sealed class _Item {}

class _Controls extends _Item {}

class _Caption extends _Item {
  _Caption(this.text);
  final String text;
}

class _Group extends _Item {
  _Group(this.space, this.name, this.count);
  final Space? space;
  final String name;
  final int count;
}

class _RoomRow extends _Item {
  _RoomRow(this.room, {required this.first, required this.last});
  final Room room;
  final bool first;
  final bool last;
}

class _Empty extends _Item {
  _Empty(this.text);
  final String text;
}

class _NewHomeRoomsState extends State<NewHomeRooms> {
  final List<StreamSubscription> subs = [];
  final TextEditingController search = TextEditingController();
  Client? filterClient;
  bool all = false;
  String query = "";
  Timer? pending;

  ClientManager get manager => widget.clientManager;

  @override
  void initState() {
    super.initState();
    filterClient = widget.filterClient;
    subs.addAll([
      manager.onSync.stream.listen((_) => refreshSoon()),
      manager.onSpaceUpdated.stream.listen((_) => refreshSoon()),
      manager.onClientRemoved.stream.listen((_) => refreshSoon()),
      EventBus.setFilterClient.stream.listen((client) {
        filterClient = client;
        refreshSoon();
      }),
    ]);
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    pending?.cancel();
    search.dispose();
    super.dispose();
  }

  void refreshSoon() {
    pending ??= Timer(const Duration(seconds: 1), () {
      pending = null;
      if (mounted) setState(() {});
    });
  }

  bool matches(Room room) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || room.displayName.toLowerCase().contains(q);
  }

  bool shown(Room room) =>
      (filterClient == null || room.client == filterClient) &&
      !hiddenFromNewHome(room) &&
      matches(room);

  static int newestFirst(Room a, Room b) =>
      b.lastEventTimestamp.compareTo(a.lastEventTimestamp);

  List<Room> otherRooms() =>
      manager.singleRooms(filterClient: filterClient).where(shown).toList()
        ..sort(newestFirst);

  List<_Item> items() {
    final items = <_Item>[_Controls()];
    void addRooms(List<Room> rooms) {
      for (var i = 0; i < rooms.length; i++) {
        items.add(
            _RoomRow(rooms[i], first: i == 0, last: i == rooms.length - 1));
      }
    }

    final other = otherRooms();
    if (!all) {
      items.add(_Caption(
          "Rooms you're in that aren't part of any space — ${other.length}"));
      if (other.isEmpty) {
        items.add(_Empty(query.trim().isEmpty
            ? "None yet: every room you're in belongs to a space."
            : "No rooms match \"${query.trim()}\"."));
      }
      addRooms(other);
      return items;
    }

    var any = other.isNotEmpty;
    for (final space in manager.spaces) {
      if (!space.isTopLevel) continue;
      if (filterClient != null && space.client != filterClient) continue;
      final seen = <String>{};
      final rooms = [
        for (final room in space.roomsWithChildren)
          if (seen.add(room.identifier) && shown(room) && !isDm(room)) room
      ]..sort(newestFirst);
      if (rooms.isEmpty) continue;
      any = true;
      items.add(_Group(space, space.displayName, rooms.length));
      addRooms(rooms);
    }
    if (other.isNotEmpty) {
      items.add(_Group(null, "Other rooms", other.length));
      addRooms(other);
    }
    if (!any) {
      items.add(_Empty(query.trim().isEmpty
          ? "You haven't joined any rooms yet."
          : "No rooms match \"${query.trim()}\"."));
    }
    return items;
  }

  static bool isDm(Room room) =>
      room.client
          .getComponent<DirectMessagesComponent>()
          ?.isRoomDirectMessage(room) ==
      true;

  @override
  Widget build(BuildContext context) {
    final list = items();
    final pad = widget.phone ? 8.0 : 20.0;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(pad, 14, pad, 20),
      itemCount: list.length,
      itemBuilder: (context, i) => Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: buildItem(context, list[i]),
        ),
      ),
    );
  }

  Widget buildItem(BuildContext context, _Item item) {
    final scheme = Theme.of(context).colorScheme;
    final sub = TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant);
    switch (item) {
      case _Controls():
        return controls(context);
      case _Caption(:final text):
        return Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(text, style: sub));
      case _Empty(:final text):
        return Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(text, style: sub));
      case _Group(:final space, :final name, :final count):
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Row(spacing: 8, children: [
            groupIcon(context, space),
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface)),
            ),
            Text("$count", style: sub.copyWith(fontWeight: FontWeight.w600)),
          ]),
        );
      case _RoomRow(:final room, :final first, :final last):
        const r = Radius.circular(10);
        return Container(
          key: ValueKey("NewHomeRooms-${room.localId}"),
          padding: EdgeInsets.fromLTRB(8, first ? 10 : 2, 8, last ? 10 : 2),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.vertical(
                top: first ? r : Radius.zero, bottom: last ? r : Radius.zero),
          ),
          child: RoomPanel(room,
              onTap: all
                  ? null
                  : () => EventBus.doOpenRoom(room.identifier,
                      clientId: room.client.identifier, openInSpace: false)),
        );
    }
  }

  Widget groupIcon(BuildContext context, Space? space) {
    final scheme = Theme.of(context).colorScheme;
    if (space == null) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh, shape: BoxShape.circle),
        child: Icon(Icons.tag_rounded, size: 14, color: scheme.onSurface),
      );
    }
    final avatar = space.avatar;
    return CircleAvatar(
      radius: 11,
      backgroundColor: space.color,
      backgroundImage: avatar,
      child: avatar != null
          ? null
          : Text(
              space.displayName.isEmpty
                  ? "#"
                  : space.displayName.characters.first.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
    );
  }

  Widget controls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chips = Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
      ChoiceChip(
          key: const ValueKey("NewHomeRoomsOther"),
          label: const Text("Other rooms"),
          selected: !all,
          showCheckmark: false,
          onSelected: (_) => setState(() => all = false)),
      ChoiceChip(
          key: const ValueKey("NewHomeRoomsAll"),
          label: const Text("All rooms"),
          selected: all,
          showCheckmark: false,
          onSelected: (_) => setState(() => all = true)),
    ]);
    final field = SizedBox(
      height: 38,
      child: TextField(
        key: const ValueKey("NewHomeRoomsSearch"),
        controller: search,
        onChanged: (text) => setState(() => query = text),
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: "Search rooms",
          hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerLowest,
          prefixIcon: Icon(Icons.search_rounded,
              size: 18, color: scheme.onSurfaceVariant),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
        ),
      ),
    );
    if (widget.phone) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [chips, field]);
    }
    return Row(children: [
      chips,
      const Spacer(),
      SizedBox(width: 240, child: field),
    ]);
  }
}
