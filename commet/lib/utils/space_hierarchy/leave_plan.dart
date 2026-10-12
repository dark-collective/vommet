// Vommet: what "Leave space" can also leave: the rooms and subspaces under a
// space that you're in, as local hierarchy data for the leave tree, and the
// order to leave them in (rooms before the spaces holding them, the space
// itself last). Pure Dart so it can be unit tested.

import 'package:commet/utils/space_hierarchy/space_tree.dart';

class JoinedSpaceIndex {
  JoinedSpaceIndex(this.spaceId);

  final String spaceId;

  /// Every joined room and space under the space (and the space itself).
  final Map<String, HierarchyRoomInfo> infos = {};

  /// Joined children of each space, in the space's order.
  final Map<String, List<String>> children = {};

  /// Rooms and subspaces under the space that you're also in through
  /// another space: id → that space's name. They start unticked.
  final Map<String, String> alsoIn = {};

  /// Adds a space with its joined [childIds]; returns false if it was
  /// already there (a space inside itself).
  bool addSpace(String id, String name, List<String> childIds,
      {Uri? avatarUrl}) {
    if (children.containsKey(id)) return false;
    children[id] = childIds;
    infos[id] = HierarchyRoomInfo(
        roomId: id,
        name: name,
        avatarUrl: avatarUrl,
        roomType: "m.space",
        children: [for (final c in childIds) HierarchyChildLink(c)]);
    return true;
  }

  void addRoom(String id, String name, {String? roomType}) {
    infos.putIfAbsent(id,
        () => HierarchyRoomInfo(roomId: id, name: name, roomType: roomType));
  }

  Set<String> _under() {
    final seen = <String>{};
    void walk(String id) {
      for (final c in children[id] ?? const <String>[]) {
        if (c == spaceId || !seen.add(c)) continue;
        walk(c);
      }
    }

    walk(spaceId);
    return seen;
  }

  int get roomCount =>
      _under().where((id) => !(infos[id]?.isSpace ?? false)).length;

  int get subspaceCount =>
      _under().where((id) => infos[id]?.isSpace ?? false).length;

  int get total => _under().length;

  HierarchyFetcher get fetcher =>
      (String spaceId, {String? from, required int limit}) async {
        final kids = children[spaceId] ?? const [];
        final start = from == null ? 0 : int.parse(from);
        final page = <HierarchyRoomInfo>[];
        var room = limit;
        if (from == null) {
          page.add(infos[spaceId] ?? HierarchyRoomInfo(roomId: spaceId));
          room--;
        }
        var end = start + room;
        if (end > kids.length) end = kids.length;
        for (var i = start; i < end; i++) {
          final info = infos[kids[i]];
          if (info != null) page.add(info);
        }
        return HierarchyPage(page,
            nextBatch: end < kids.length ? "$end" : null);
      };

  /// A tree of everything under the space, all of it selectable (every
  /// row is a room you're in), nothing ticked.
  SpaceTree tree() => SpaceTree(
        spaceId: spaceId,
        rootInfo: infos[spaceId],
        fetch: fetcher,
        isJoined: (_) => false,
        selectionCap: SpaceTree.totalCap,
      );

  /// Marks the ids under the space that [otherSpace] (a joined space outside
  /// this one) also holds, walking its [childrenOf] (joined rooms and
  /// subspaces). The space itself is never walked into: being a subspace of
  /// [otherSpace] doesn't make its rooms shared.
  void markShared(String otherSpace, String otherName,
      List<String> Function(String spaceId) childrenOf) {
    if (otherSpace == spaceId) return;
    final under = _under();
    final seen = <String>{otherSpace};
    void walk(String id) {
      for (final c in childrenOf(id)) {
        if (c == spaceId || !seen.add(c)) continue;
        if (under.contains(c)) alsoIn.putIfAbsent(c, () => otherName);
        walk(c);
      }
    }

    walk(otherSpace);
  }

  /// The starting selection: everything, except what you're also in
  /// through another space. Expects a loaded tree ([loadAll]).
  Future<void> selectDefault(SpaceTree tree) async {
    await tree.selectAll();
    tree.selected.removeAll(alsoIn.keys);
    syncSpaces(tree);
  }

  /// A subspace is left only when everything you're in under it is ticked;
  /// a half-ticked one (a dash) stays joined. Run after every change.
  static void syncSpaces(SpaceTree tree) {
    for (final n in tree.descendants(tree.root).toList().reversed) {
      if (!n.isSpace || !tree.selectable(n)) continue;
      final inside = tree.descendants(n).where(tree.selectable).toList();
      if (inside.isEmpty) continue;
      if (inside.every((c) => tree.selected.contains(c.roomId))) {
        tree.selected.add(n.roomId);
      } else {
        tree.selected.remove(n.roomId);
      }
    }
  }

  /// Ticked rooms and (whole) subspaces in [tree].
  (int rooms, int spaces) selectedCounts(SpaceTree tree) {
    var rooms = 0, spaces = 0;
    for (final id in tree.selected) {
      if (infos[id]?.isSpace ?? false) {
        spaces++;
      } else {
        rooms++;
      }
    }
    return (rooms, spaces);
  }

  /// Loads the whole tree and opens every subspace.
  static Future<void> loadAll(SpaceTree tree) async {
    await tree.loadRoot();
    var opened = true;
    while (opened) {
      opened = false;
      for (final n in tree.descendants(tree.root).toList()) {
        if (n.isSpace && !n.expanded && tree.canExpand(n)) {
          await tree.expand(n);
          opened = true;
        }
      }
    }
  }

  /// Everything to leave, in order: with [all], every room and subspace
  /// under the space; otherwise the ones ticked in [tree]. Rooms come
  /// before the spaces they're in, and the space itself is always last.
  List<String> leaveOrder({required bool all, SpaceTree? tree}) {
    final ordered = <String>[];
    if (all || tree == null) {
      final seen = <String>{spaceId};
      void walkIds(String id) {
        for (final c in children[id] ?? const <String>[]) {
          if (!seen.add(c)) continue;
          walkIds(c);
          ordered.add(c);
        }
      }

      if (all) walkIds(spaceId);
    } else {
      void walkNodes(SpaceTreeNode n) {
        for (final c in n.children) {
          walkNodes(c);
          if (tree.selected.contains(c.roomId)) ordered.add(c.roomId);
        }
      }

      walkNodes(tree.root);
    }
    return [...ordered, spaceId];
  }
}
