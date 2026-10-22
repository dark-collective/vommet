import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/calendar_room/calendar_room_component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_model.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter/material.dart';

/// The Rooms page's chip; the rail's # button picks Standalone.
final ValueNotifier<RoomsChip> newHomeRoomsChip = ValueNotifier(RoomsChip.all);

/// Vommet (New Home): the Rooms page. "All rooms & spaces" (the default)
/// lists the standalone rooms (outside any space) first, then each space
/// with its rooms and collapsible subspaces. The other chips filter by room
/// type or unread. The search filters everything live, nested subspaces
/// included, and shows where each hit lives.
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

class _Note extends _Item {
  _Note(this.text);
  final String text;
}

class _Header extends _Item {
  _Header(this.section, {required this.collapsed, required this.unread});
  final RoomsSection<Space, Room> section;
  final bool collapsed;
  final int unread;
}

class _RoomRow extends _Item {
  _RoomRow(this.room, this.depth,
      {required this.first, required this.last, required this.standalone});
  final Room room;
  final int depth;
  final bool first;
  final bool last;
  final bool standalone;
}

class _More extends _Item {
  _More(this.key, this.hidden, this.depth);
  final String key;
  final int hidden;
  final int depth;
}

class _Hit extends _Item {
  _Hit(this.hit);
  final RoomsHit<Space, Room> hit;
}

/// How many rooms a section shows before "Show N more".
const int _showMoreLimit = 5;

class _NewHomeRoomsState extends State<NewHomeRooms> {
  final List<StreamSubscription> subs = [];
  final TextEditingController search = TextEditingController();
  Client? filterClient;
  String query = "";
  Timer? pending;

  /// Collapsed sections per chip, by section key; kept while the app runs.
  static final Map<RoomsChip, Set<String>> collapsed = {};

  /// Sections showing all their rooms ("Show N more" pressed).
  static final Set<String> expanded = {};

  ClientManager get manager => widget.clientManager;
  RoomsChip get chip => newHomeRoomsChip.value;
  Set<String> get collapsedHere => collapsed.putIfAbsent(chip, () => {});

  static final RoomFacts<Room> facts = RoomFacts(
    name: (room) => room.displayName,
    kind: kindOf,
    unread: roomHasUnread,
    lastActivity: (room) => room.lastEventTimestamp,
  );

  /// Vommet's room types, as [Room.icon] tells them apart.
  static RoomKind kindOf(Room room) {
    if (room.getComponent<VoipRoomComponent>() != null) return RoomKind.voice;
    if (room.getComponent<PhotoAlbumRoom>() != null) return RoomKind.photos;
    if (room.getComponent<CalendarRoom>()?.isCalendarRoom == true) {
      return RoomKind.calendar;
    }
    return RoomKind.chat;
  }

  @override
  void initState() {
    super.initState();
    filterClient = widget.filterClient;
    newHomeRoomsChip.addListener(onChip);
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
    newHomeRoomsChip.removeListener(onChip);
    pending?.cancel();
    search.dispose();
    super.dispose();
  }

  void onChip() {
    if (mounted) setState(() {});
  }

  void refreshSoon() {
    pending ??= Timer(const Duration(seconds: 1), () {
      pending = null;
      if (mounted) setState(() {});
    });
  }

  static bool isDm(Room room) =>
      room.client
          .getComponent<DirectMessagesComponent>()
          ?.isRoomDirectMessage(room) ==
      true;

  bool shown(Room room) =>
      (filterClient == null || room.client == filterClient) &&
      !hiddenFromNewHome(room) &&
      !isDm(room);

  List<Room> standaloneRooms() =>
      manager.singleRooms(filterClient: filterClient).where(shown).toList();

  static String spaceKey(Space space) => "space:${space.localId}";

  /// [space] with its rooms and subspaces; a subspace already on the way
  /// down (a loop in the space graph) isn't followed again.
  SpaceNode<Space, Room> node(Space space, Set<String> path) {
    final key = spaceKey(space);
    final inside = {...path, key};
    return SpaceNode(
      space,
      space.displayName,
      key,
      rooms: space.rooms.where(shown).toList(),
      subspaces: [
        for (final sub in space.subspaces)
          if (!inside.contains(spaceKey(sub))) node(sub, inside)
      ],
    );
  }

  List<SpaceNode<Space, Room>> spaceNodes() => [
        for (final space in manager.spaces)
          if (space.isTopLevel &&
              (filterClient == null || space.client == filterClient))
            node(space, const {})
      ];

  static Object identity(Room room) => room.localId;

  List<_Item> items(
      List<Room> standalone, List<SpaceNode<Space, Room>> spaces) {
    final items = <_Item>[_Controls()];
    final q = query.trim();

    if (q.isNotEmpty) {
      final hits = RoomsModel.search(
          query: q,
          standalone: standalone,
          spaces: spaces,
          chip: chip,
          facts: facts,
          identity: identity);
      final under = chip == RoomsChip.all ? "" : " under ${chip.label}";
      items.add(_Note(hits.isEmpty
          ? "Nothing matches \"$q\"$under."
          : "${hits.length} ${hits.length == 1 ? "result" : "results"}"));
      items.addAll(hits.map(_Hit.new));
      return items;
    }

    final tree = RoomsModel.tree(
        standalone: standalone, spaces: spaces, chip: chip, facts: facts);
    if (chip == RoomsChip.standalone) {
      final n = tree.sections.firstOrNull?.count ?? 0;
      items.add(_Note("Rooms you're in that aren't part of any space — $n"));
    }
    if (tree.isEmpty) {
      items.add(_Note(switch (chip) {
        RoomsChip.all => "You haven't joined any rooms yet.",
        RoomsChip.standalone =>
          "None yet: every room you're in belongs to a space.",
        RoomsChip.voice => "No voice rooms.",
        RoomsChip.photos => "No photo albums.",
        RoomsChip.calendars => "No calendars.",
        RoomsChip.unread => "You're all caught up.",
      }));
    }

    final typeChip = chip != RoomsChip.all && chip != RoomsChip.standalone;
    void addSection(RoomsSection<Space, Room> section) {
      final isCollapsed = collapsedHere.contains(section.key);
      if (chip != RoomsChip.standalone) {
        items.add(_Header(section,
            collapsed: isCollapsed,
            unread: RoomsModel.unreadIn(section, facts)));
      }
      if (isCollapsed) return;
      final rooms = section.rooms;
      final visible = typeChip
          ? rooms.length
          : RoomsModel.visibleRooms(rooms.length, _showMoreLimit,
              expanded: expanded.contains(section.key));
      for (var i = 0; i < visible; i++) {
        items.add(_RoomRow(rooms[i], section.depth,
            first: i == 0,
            last: i == visible - 1,
            standalone: section.node == null));
      }
      if (visible < rooms.length) {
        items.add(_More(section.key, rooms.length - visible, section.depth));
      }
      for (final sub in section.subsections) {
        addSection(sub);
      }
    }

    for (final section in tree.sections) {
      addSection(section);
    }
    if (typeChip && tree.without.isNotEmpty && !tree.isEmpty) {
      items.add(_Note(RoomsModel.withoutNote(tree.without, chip)));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final standalone = standaloneRooms();
    final spaces = spaceNodes();
    final q = query.trim();
    final counts = q.isEmpty
        ? null
        : RoomsModel.searchCounts(
            query: q,
            standalone: standalone,
            spaces: spaces,
            facts: facts,
            identity: identity);
    final list = items(standalone, spaces);
    final pad = widget.phone ? 8.0 : 20.0;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(pad, 14, pad, 20),
      itemCount: list.length,
      itemBuilder: (context, i) => Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: buildItem(context, list[i], counts, spaces),
        ),
      ),
    );
  }

  Widget buildItem(BuildContext context, _Item item,
      Map<RoomsChip, int>? counts, List<SpaceNode<Space, Room>> spaces) {
    final scheme = Theme.of(context).colorScheme;
    final sub = TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant);
    switch (item) {
      case _Controls():
        return controls(context, counts, spaces);
      case _Note(:final text):
        return Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(text, style: sub));
      case _Header():
        return header(context, item);
      case _More(:final key, :final hidden, :final depth):
        return Padding(
          padding: EdgeInsets.fromLTRB(4.0 + 16 * depth, 2, 4, 4),
          child: TextButton(
            key: ValueKey("NewHomeRoomsMore-$key"),
            onPressed: () => setState(() => expanded.add(key)),
            child: Text("Show $hidden more"),
          ),
        );
      case _Hit(:final hit):
        return hitRow(context, hit);
      case _RoomRow(
          :final room,
          :final depth,
          :final first,
          :final last,
          :final standalone
        ):
        const r = Radius.circular(10);
        return Padding(
          padding: EdgeInsets.only(left: 16.0 * depth),
          child: Container(
            key: ValueKey("NewHomeRooms-${room.localId}"),
            padding: EdgeInsets.fromLTRB(8, first ? 10 : 2, 8, last ? 10 : 2),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.vertical(
                  top: first ? r : Radius.zero, bottom: last ? r : Radius.zero),
            ),
            child: RoomPanel(room,
                onTap: standalone
                    ? () => EventBus.doOpenRoom(room.identifier,
                        clientId: room.client.identifier, openInSpace: false)
                    : null),
          ),
        );
    }
  }

  Widget header(BuildContext context, _Header item) {
    final scheme = Theme.of(context).colorScheme;
    final section = item.section;
    final sub = TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant);
    final summary = RoomsModel.collapsedSummary(section, item.unread);
    final space = section.node?.space;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16.0 * section.depth, section.depth == 0 ? 14 : 6, 0, 6),
      child: InkWell(
        key: ValueKey("NewHomeRoomsSection-${section.key}"),
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() {
          if (!collapsedHere.remove(section.key)) {
            collapsedHere.add(section.key);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(spacing: 8, children: [
            Icon(
                item.collapsed
                    ? Icons.chevron_right_rounded
                    : Icons.expand_more_rounded,
                size: 18,
                color: scheme.onSurfaceVariant),
            groupIcon(context, space, small: section.depth > 0),
            Flexible(
              child: Text(section.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: section.depth == 0 ? 14 : 13,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface)),
            ),
            Text("${section.count}", style: sub),
            if (item.collapsed && summary.isNotEmpty)
              Flexible(
                child: Text(summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sub.copyWith(fontWeight: FontWeight.w500)),
              ),
            const Spacer(),
            if (space != null)
              IconButton(
                tooltip: "Open space",
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.open_in_new_rounded,
                    size: 16, color: scheme.onSurfaceVariant),
                onPressed: () => EventBus.openSpace
                    .add((space.identifier, space.client.identifier)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget hitRow(BuildContext context, RoomsHit<Space, Room> hit) {
    final scheme = Theme.of(context).colorScheme;
    final room = hit.room;
    final space = hit.space;
    final unread = room != null && roomHasUnread(room);
    final base = TextStyle(
        fontSize: 14,
        fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
        color: scheme.onSurface);
    final m = hit.match;
    final name = hit.name;
    final start = m.start.clamp(0, name.length);
    final end = m.end.clamp(start, name.length);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey(
            "NewHomeRoomsHit-${room?.localId ?? space?.localId ?? name}"),
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (room != null) {
            EventBus.doOpenRoom(room.identifier,
                clientId: room.client.identifier,
                openInSpace: hit.path.isNotEmpty);
          } else if (space != null) {
            EventBus.openSpace.add((space.identifier, space.client.identifier));
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(spacing: 10, children: [
            room != null
                ? Icon(room.icon, size: 20, color: scheme.onSurfaceVariant)
                : groupIcon(context, space, small: false),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text.rich(
                      TextSpan(style: base, children: [
                        TextSpan(text: name.substring(0, start)),
                        TextSpan(
                            text: name.substring(start, end),
                            style: TextStyle(
                                backgroundColor: scheme.primary.withAlpha(70),
                                color: scheme.onSurface)),
                        TextSpan(text: name.substring(end)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(hit.breadcrumb,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ]),
            ),
            if (unread)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: scheme.onSurface, shape: BoxShape.circle),
              ),
          ]),
        ),
      ),
    );
  }

  Widget groupIcon(BuildContext context, Space? space, {required bool small}) {
    final scheme = Theme.of(context).colorScheme;
    final size = small ? 18.0 : 22.0;
    if (space == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh, shape: BoxShape.circle),
        child:
            Icon(Icons.tag_rounded, size: size * 0.64, color: scheme.onSurface),
      );
    }
    final avatar = space.avatar;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: space.color,
      backgroundImage: avatar,
      child: avatar != null
          ? null
          : Text(
              space.displayName.isEmpty
                  ? "#"
                  : space.displayName.characters.first.toUpperCase(),
              style: TextStyle(
                  fontSize: size * 0.45,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
    );
  }

  Widget controls(BuildContext context, Map<RoomsChip, int>? counts,
      List<SpaceNode<Space, Room>> spaces) {
    final scheme = Theme.of(context).colorScheme;
    final phone = widget.phone;
    final chips = Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
      for (final c in RoomsChip.values)
        ChoiceChip(
            key: ValueKey("NewHomeRoomsChip-${c.name}"),
            label: Text(RoomsModel.chipLabel(c, counts?[c], phone: phone)),
            selected: chip == c,
            showCheckmark: false,
            onSelected: (_) => newHomeRoomsChip.value = c),
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
          hintText: "Search rooms & spaces",
          hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerLowest,
          prefixIcon: Icon(Icons.search_rounded,
              size: 18, color: scheme.onSurfaceVariant),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: "Clear search",
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    search.clear();
                    setState(() => query = "");
                  }),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
        ),
      ),
    );

    // "Collapse all" / "Expand all" for the tree (not while searching).
    Widget? collapseAll;
    if (query.trim().isEmpty && chip != RoomsChip.standalone) {
      final keys = ["standalone", for (final s in spaces) s.key];
      final allCollapsed = keys.every(collapsedHere.contains);
      collapseAll = TextButton.icon(
        key: const ValueKey("NewHomeRoomsCollapseAll"),
        onPressed: () => setState(() {
          if (allCollapsed) {
            collapsedHere.clear();
          } else {
            collapsedHere.addAll(keys);
          }
        }),
        icon: Icon(
            allCollapsed
                ? Icons.unfold_more_rounded
                : Icons.unfold_less_rounded,
            size: 18),
        label: Text(allCollapsed ? "Expand all" : "Collapse all"),
      );
    }

    final chipRow =
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: chips);
    if (phone) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            field,
            chipRow,
            if (collapseAll != null)
              Align(alignment: Alignment.centerRight, child: collapseAll),
          ]);
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(children: [
            Expanded(child: chipRow),
            const SizedBox(width: 12),
            SizedBox(width: 260, child: field),
          ]),
          if (collapseAll != null)
            Align(alignment: Alignment.centerRight, child: collapseAll),
        ]);
  }
}
