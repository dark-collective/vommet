import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_section.dart';

/// Vommet (New Home): where each room sits among your spaces, for the
/// Rooms section (its order, the space after a room's name, its space
/// rows) and search. Built once per space update (or account, filter or
/// rail order change), not per refresh.
class NewHomeSpaceIndex {
  NewHomeSpaceIndex._(
      this.tops, this.paths, this.spaceRail, this.subspacePaths);

  /// The top-level spaces in rail order (the rail's folders flattened),
  /// then any top-level space the rail doesn't list.
  final List<Space> tops;

  /// Each room's space path, by [Room.localId]: the first space holding
  /// it in rail order (Vommet's one path per room).
  final Map<Object, SpacePath<Space>> paths;

  /// Each space's outermost space's place in the rail, by [Space.localId].
  final Map<String, int> spaceRail;

  /// Each subspace's path (outermost first, down to its parent), by
  /// [Space.localId]; top-level spaces have none.
  final Map<Object, SpacePath<Space>> subspacePaths;

  /// [space]'s path, outermost first, itself last.
  List<Space> pathOfSpace(Space space) =>
      [...?subspacePaths[space.localId]?.spaces, space];

  final Map<SpaceRef, Set<String>> _refRooms = {};

  static NewHomeSpaceIndex? _cached;
  static Object? _cachedKey;
  static int _generation = 0;
  static ClientManager? _attached;
  static final List<StreamSubscription> _subs = [];

  /// The index for [manager]'s spaces, of [filter]'s account when set.
  static NewHomeSpaceIndex of(ClientManager manager, Client? filter) {
    _attach(manager);
    final key = (
      _generation,
      filter?.identifier,
      manager.clients.length,
      manager.spaces.length,
      manager.rooms.length,
    );
    final cached = _cached;
    if (cached != null && key == _cachedKey) return cached;
    _cachedKey = key;
    return _cached = _build(manager, filter);
  }

  static void _attach(ClientManager manager) {
    if (identical(_attached, manager)) return;
    for (final s in _subs) {
      s.cancel();
    }
    _subs
      ..clear()
      ..addAll([
        manager.onSpaceUpdated.stream.listen((_) => _generation++),
        manager.onClientAdded.stream.listen((_) => _generation++),
        manager.onClientRemoved.stream.listen((_) => _generation++),
        SidebarEntriesComponent.onOrderChanged.listen((_) => _generation++),
      ]);
    _attached = manager;
    _generation++;
  }

  static NewHomeSpaceIndex _build(ClientManager manager, Client? filter) {
    final clients = filter == null ? manager.clients : [filter];
    final entries = <SidebarEntry>[
      for (final client in clients)
        ...?client.getComponent<SidebarEntriesComponent>()?.getEntries()
    ]..sort((a, b) => a.order.compareTo(b.order));
    final tops = <Space>[];
    final seen = <String>{};
    void add(Space space) {
      if (seen.add(space.localId)) tops.add(space);
    }

    for (final entry in entries) {
      if (entry is SpaceSidebarEntry) add(entry.space);
      if (entry is SpaceGroupSidebarEntry) {
        for (final member in entry.members) {
          if (member is SpaceSidebarEntry) add(member.space);
        }
      }
    }
    for (final space in manager.spaces) {
      if (space.isTopLevel && (filter == null || space.client == filter)) {
        add(space);
      }
    }

    final paths = spacePaths<Space, Room>(tops,
        rooms: (s) => s.rooms,
        subspaces: (s) => s.subspaces,
        key: (r) => r.localId,
        spaceKey: (s) => s.localId);
    final subPaths = spacePaths<Space, Space>(tops,
        rooms: (s) => s.subspaces,
        subspaces: (s) => s.subspaces,
        key: (s) => s.localId,
        spaceKey: (s) => s.localId);
    final spaceRail = <String, int>{
      for (var i = 0; i < tops.length; i++) tops[i].localId: i,
    };
    for (final MapEntry(:key, :value) in subPaths.entries) {
      spaceRail.putIfAbsent(key as String, () => value.rail);
    }
    return NewHomeSpaceIndex._(tops, paths, spaceRail, subPaths);
  }

  SpacePath<Space>? pathOf(Room room) => paths[room.localId];

  /// The space [ref] names (on its account when it still has it there),
  /// or null when you've left it.
  Space? spaceOf(ClientManager manager, SpaceRef ref) {
    final spaces =
        manager.spaces.where((s) => s.identifier == ref.space).toList();
    return spaces
            .where(
                (s) => ref.client == null || s.client.identifier == ref.client)
            .firstOrNull ??
        spaces.firstOrNull;
  }

  /// Whether [room] is in [ref]'s space or its subspaces.
  bool inSpace(ClientManager manager, Room room, SpaceRef ref) =>
      (_refRooms[ref] ??= {
        for (final r in spaceOf(manager, ref)?.roomsWithChildren ?? <Room>[])
          r.localId
      })
          .contains(room.localId);

  /// The spaces a Rooms section of [filter] shows as rows, in rail order,
  /// with their rail index.
  List<(int, Space)> sectionSpaces(ClientManager manager, RoomsFilter filter) {
    final picked = <String>{
      for (final ref in filter.spaceList)
        if (spaceOf(manager, ref) case final space?) space.localId
    };
    final List<Space> spaces = switch (filter.spaces) {
      RoomsFilter.spacesAll => tops,
      RoomsFilter.spacesExcept =>
        tops.where((s) => !picked.contains(s.localId)).toList(),
      RoomsFilter.spacesOnly => [
          for (final ref in filter.spaceList)
            if (spaceOf(manager, ref) case final space?) space
        ],
      _ => const [],
    };
    final rows = [
      for (final space in spaces)
        if (spaceRail[space.localId] case final rail?) (rail, space)
    ];
    // Stable: spaces in one rail entry keep the order picked.
    return _stableByRail(rows);
  }

  static List<(int, Space)> _stableByRail(List<(int, Space)> rows) {
    final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
    indexed.sort((a, b) {
      final byRail = a.$2.$1.compareTo(b.$2.$1);
      return byRail != 0 ? byRail : a.$1.compareTo(b.$1);
    });
    return [for (final (_, row) in indexed) row];
  }

  /// How the Rooms section reads Commet rooms.
  RoomsFacts<Room> facts(
    ClientManager manager, {
    required bool Function(Room room) isStandalone,
    required bool Function(Room room) isDirectMessage,
    required bool Function(Room room, String tag) hasTag,
  }) =>
      RoomsFacts<Room>(
        lastEvent: (r) => r.lastEvent == null ? null : r.lastEventTimestamp,
        isStandalone: isStandalone,
        isDirectMessage: isDirectMessage,
        hasTag: hasTag,
        railIndex: (r) => paths[r.localId]?.rail,
        inSpace: (r, ref) => inSpace(manager, r, ref),
        identity: (r) => r.identifier,
      );
}
