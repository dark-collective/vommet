import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/calendar_room/calendar_room_component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:commet/ui/atoms/room_avatar_badge.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_page_preview.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_model.dart';
import 'package:commet/ui/organisms/new_home/rooms_hit_row.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter/material.dart';

/// The Rooms page's chip; the rail's # button picks Standalone.
final ValueNotifier<RoomsChip> newHomeRoomsChip = ValueNotifier(RoomsChip.all);

/// The Rooms page's collapsed sections, per chip, remembered on this device
/// (not synced): entries from [RoomsModel.withCollapsed].
final StringListPreference newHomeRoomsCollapsed = StringListPreference(
    "vommet_new_home_rooms_collapsed",
    defaultValue: const []);

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
    this.preview,
    this.onSeeAll,
  });

  final ClientManager clientManager;
  final Client? filterClient;
  final bool phone;

  /// As a card beside other cards (Vommet issue 782): only this many room
  /// rows (with their section headers), no search or chips, and "See all"
  /// calls [onSeeAll].
  final int? preview;
  final VoidCallback? onSeeAll;

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

class _Hit extends _Item {
  _Hit(this.hit);
  final RoomsHit<Space, Room> hit;
}

class _NewHomeRoomsState extends State<NewHomeRooms> {
  final List<StreamSubscription> subs = [];
  final TextEditingController search = TextEditingController();
  Client? filterClient;
  String query = "";
  Timer? pending;

  ClientManager get manager => widget.clientManager;
  RoomsChip get chip => newHomeRoomsChip.value;

  /// This chip's collapsed sections, as remembered on this device.
  Set<String> get collapsedHere =>
      RoomsModel.collapsedFor(newHomeRoomsCollapsed.value, chip);

  void setCollapsed(Iterable<String> keys, bool collapse) {
    newHomeRoomsCollapsed.set(RoomsModel.withCollapsed(
        newHomeRoomsCollapsed.value, chip, keys,
        collapsed: collapse));
    setState(() {});
  }

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
    final collapsedSections = collapsedHere;
    void addSection(RoomsSection<Space, Room> section) {
      final isCollapsed = collapsedSections.contains(section.key);
      if (chip != RoomsChip.standalone) {
        items.add(_Header(section,
            collapsed: isCollapsed,
            unread: RoomsModel.unreadIn(section, facts)));
      }
      if (isCollapsed) return;
      final rooms = section.rooms;
      // Every room: the list builds rows only as they scroll into view.
      for (var i = 0; i < rooms.length; i++) {
        items.add(_RoomRow(rooms[i], section.depth,
            first: i == 0,
            last: i == rooms.length - 1,
            standalone: section.node == null));
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
    final preview = widget.preview;
    if (preview != null) {
      final total = list.whereType<_RoomRow>().length;
      final shown = <_Item>[];
      var rows = 0;
      for (final item in list) {
        if (item is _Controls) continue;
        if (item is _RoomRow && rows++ >= preview) break;
        shown.add(item);
      }
      // A header with none of its rows shown.
      if (shown.lastOrNull is _Header && rows > preview) shown.removeLast();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in shown) buildItem(context, item, counts, spaces),
          if (total > preview)
            NewHomeSeeAll(total: total, onTap: widget.onSeeAll ?? () {}),
        ],
      );
    }
    final pad = widget.phone ? 8.0 : 20.0;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(pad, 14, pad, 20),
      itemCount: list.length,
      // The page's full width (like Overview), minus the padding.
      itemBuilder: (context, i) => buildItem(context, list[i], counts, spaces),
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
        mouseCursor: WidgetStateMouseCursor.clickable,
        key: ValueKey("NewHomeRoomsSection-${section.key}"),
        borderRadius: BorderRadius.circular(8),
        onTap: () => setCollapsed([section.key], !item.collapsed),
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
    final room = hit.room;
    final space = hit.space;
    final name = hit.name;
    return RoomsHitRow(
      key: ValueKey(
          "NewHomeRoomsHit-${room?.localId ?? space?.localId ?? name}"),
      leading: room != null
          ? RoomsHitAvatar(
              name: room.displayName,
              color: room.defaultColor,
              avatar: room.avatar,
              typeIcon: room.icon,
              badge: hitBadge(room))
          : groupIcon(context, space, size: RoomsHitAvatar.size),
      name: name,
      matchStart: hit.match.start,
      matchEnd: hit.match.end,
      breadcrumb: hit.breadcrumb,
      unread: room != null && roomHasUnread(room),
      onTap: () {
        if (room != null) {
          EventBus.doOpenRoom(room.identifier,
              clientId: room.client.identifier,
              openInSpace: hit.path.isNotEmpty);
        } else if (space != null) {
          EventBus.openSpace.add((space.identifier, space.client.identifier));
        }
      },
    );
  }

  /// The type mark on a search hit's room avatar: the room lists' badge
  /// (voice), else the photos / calendar icon; none for a text room.
  static IconData? hitBadge(Room room) =>
      roomAvatarBadge(room) ??
      switch (kindOf(room)) {
        RoomKind.photos || RoomKind.calendar => room.icon,
        _ => null,
      };

  Widget groupIcon(BuildContext context, Space? space,
      {bool small = false, double? size}) {
    final scheme = Theme.of(context).colorScheme;
    size ??= small ? 18.0 : 22.0;
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
    final chips = [
      for (final c in RoomsChip.values)
        ChoiceChip(
            mouseCursor: WidgetStateMouseCursor.clickable,
            key: ValueKey("NewHomeRoomsChip-${c.name}"),
            label: Text(RoomsModel.chipLabel(c, counts?[c], phone: phone)),
            selected: chip == c,
            showCheckmark: false,
            onSelected: (_) => newHomeRoomsChip.value = c),
    ];
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
      final collapsedNow = collapsedHere;
      final allCollapsed = keys.every(collapsedNow.contains);
      collapseAll = TextButton.icon(
        key: const ValueKey("NewHomeRoomsCollapseAll"),
        // Expand all also opens subspaces collapsed one by one.
        onPressed: () => allCollapsed
            ? setCollapsed(collapsedNow, false)
            : setCollapsed(keys, true),
        icon: Icon(
            allCollapsed
                ? Icons.unfold_more_rounded
                : Icons.unfold_less_rounded,
            size: 18),
        label: Text(allCollapsed ? "Expand all" : "Collapse all"),
      );
    }

    return RoomsControlsLayout(
        phone: phone, chips: chips, field: field, collapseAll: collapseAll);
  }
}

/// The Rooms page's filter chips, search field and "Collapse all". On a
/// phone the chips scroll sideways under the search field; on desktop they
/// wrap onto as many lines as they need (none scroll out of sight), with the
/// search field on its own line underneath, like the People page.
class RoomsControlsLayout extends StatelessWidget {
  const RoomsControlsLayout(
      {super.key,
      required this.phone,
      required this.chips,
      required this.field,
      this.collapseAll});

  final bool phone;
  final List<Widget> chips;
  final Widget field;
  final Widget? collapseAll;

  @override
  Widget build(BuildContext context) {
    final collapse = collapseAll;
    if (phone) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            field,
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: chips)),
            if (collapse != null)
              Align(alignment: Alignment.centerRight, child: collapse),
          ]);
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: chips),
          field,
          if (collapse != null)
            Align(alignment: Alignment.centerRight, child: collapse),
        ]);
  }
}
