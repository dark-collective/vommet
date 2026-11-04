// Vommet: the tree behind the space join picker (and the "also leave its
// rooms" chooser). Pure Dart, no client or network code: rooms come from a
// [HierarchyFetcher], so the paging and the hostile-space limits can be unit
// tested.

/// One `m.space.child` link of a space.
class HierarchyChildLink {
  const HierarchyChildLink(this.roomId,
      {this.suggested = false, this.via = const []});

  final String roomId;
  final bool suggested;
  final List<String> via;
}

/// One room or space as the server (or the local client) describes it.
class HierarchyRoomInfo {
  const HierarchyRoomInfo({
    required this.roomId,
    this.name,
    this.avatarUrl,
    this.roomType,
    this.members = 0,
    this.joinRule,
    this.topic,
    this.children = const [],
  });

  final String roomId;
  final String? name;
  final Uri? avatarUrl;
  final String? roomType;
  final int members;
  final String? joinRule;

  /// The room's `m.room.topic`, so it can be read before joining.
  final String? topic;
  final List<HierarchyChildLink> children;

  bool get isSpace => roomType == "m.space";
}

class HierarchyPage {
  const HierarchyPage(this.rooms, {this.nextBatch});

  final List<HierarchyRoomInfo> rooms;
  final String? nextBatch;
}

/// Fetches one page of a space's direct children (`/hierarchy` with
/// `max_depth=1`). The space itself may come first, as the server sends it.
typedef HierarchyFetcher = Future<HierarchyPage> Function(String spaceId,
    {String? from, required int limit});

class SpaceTreeNode {
  SpaceTreeNode(this.roomId,
      {this.info,
      this.parent,
      this.depth = 0,
      this.suggested = false,
      this.via = const []});

  final String roomId;
  HierarchyRoomInfo? info;
  final SpaceTreeNode? parent;

  /// 0 for the space being joined, 1 for its direct children, ...
  final int depth;
  final bool suggested;
  final List<String> via;

  final List<SpaceTreeNode> children = [];

  bool expanded = false;
  bool loading = false;
  bool fullyLoaded = false;
  String? nextBatch;

  bool get isSpace => depth == 0 || (info?.isSpace ?? false);

  String get name {
    final n = info?.name;
    return (n == null || n.trim().isEmpty) ? roomId : n;
  }

  /// The topic on one line (line breaks folded into spaces), or null when
  /// the room has none.
  String? get topic {
    final t = info?.topic?.replaceAll(RegExp(r"\s+"), " ").trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// How many children the space lists (known before they are loaded).
  int get childCount {
    final links = info?.children ?? const [];
    return links.isNotEmpty ? links.length : children.length;
  }
}

/// The loaded part of a space's hierarchy plus the selection made on it.
class SpaceTree {
  SpaceTree({
    required String spaceId,
    required this.fetch,
    required this.isJoined,
    HierarchyRoomInfo? rootInfo,
    List<String> via = const [],
    this.selectionCap = actionCap,
    this.depthLimit = maxDepth,
  }) : root = SpaceTreeNode(spaceId, info: rootInfo, via: via) {
    _byId[spaceId] = root;
  }

  /// Entries asked for per `/hierarchy` request.
  static const int pageSize = 50;

  /// Entries loaded per "Load more" (and before the first one).
  static const int batchCap = 500;

  /// Entries loaded in total, whatever the user does.
  static const int totalCap = 5000;

  /// Levels below the joined space that are loaded (by default: the
  /// server is asked level by level).
  static const int maxDepth = 8;

  /// Vommet: levels loaded for this tree. A tree built from local data
  /// (inviting) can go deeper than [maxDepth].
  final int depthLimit;

  /// Rooms and spaces joined (or left) per action.
  static const int actionCap = 100;

  /// At most this many ticked at once ([actionCap] for joins).
  final int selectionCap;

  final HierarchyFetcher fetch;
  final bool Function(String roomId) isJoined;
  final SpaceTreeNode root;

  final Map<String, SpaceTreeNode> _byId = {};
  final List<SpaceTreeNode> _paused = [];
  int _budget = batchCap;

  /// Entries loaded, not counting the space itself.
  int loadedCount = 0;

  final Set<String> selected = {};

  /// Subspaces ticked as a whole: their children get ticked as they load.
  final Set<String> _tickAllOnLoad = {};
  bool _followSuggested = true;

  /// Set when a selection was cut to [actionCap]: how many it would have
  /// ticked.
  int? truncatedFrom;

  /// Some loading stopped at [batchCap]; "Load more" continues it.
  bool get canLoadMore => _paused.isNotEmpty && loadedCount < totalCap;

  /// Loading stopped for good at [totalCap].
  bool get hitTotalCap => _paused.isNotEmpty && loadedCount >= totalCap;

  SpaceTreeNode? node(String roomId) => _byId[roomId];

  bool selectable(SpaceTreeNode n) => n != root && !isJoined(n.roomId);

  bool canExpand(SpaceTreeNode n) =>
      n.isSpace && n.depth < depthLimit && n != root && n.childCount > 0;

  /// Loads the first entries of the space, and the suggested subspaces
  /// under it, within the first [batchCap].
  Future<void> loadRoot() async {
    await loadChildren(root);
    root.expanded = true;
    final queue = root.children.where((c) => c.suggested && c.isSpace).toList();
    while (queue.isNotEmpty && _budget > 0) {
      final n = queue.removeAt(0);
      if (!canExpand(n)) continue;
      await loadChildren(n);
      n.expanded = true;
      queue.addAll(n.children.where((c) => c.suggested && c.isSpace));
    }
  }

  /// Loads [n]'s children page by page until they're all in, or until the
  /// current batch (or the total cap) runs out.
  Future<void> loadChildren(SpaceTreeNode n) async {
    if (n.fullyLoaded || n.loading) return;
    if (n != root && !canExpand(n)) {
      n.fullyLoaded = true;
      return;
    }
    n.loading = true;
    try {
      while (!n.fullyLoaded) {
        final remaining = _remaining;
        if (remaining <= 0) {
          if (!_paused.contains(n)) _paused.add(n);
          return;
        }
        // The first page carries the space itself, which isn't counted.
        final first = n.nextBatch == null && n.children.isEmpty;
        final limit = (remaining < pageSize ? remaining : pageSize) +
            (first && remaining < pageSize ? 1 : 0);
        final page = await fetch(n.roomId, from: n.nextBatch, limit: limit);
        _addPage(n, page);
        final next = page.nextBatch;
        if (next == null || next.isEmpty || page.rooms.isEmpty) {
          n.fullyLoaded = true;
          _paused.remove(n);
        } else {
          n.nextBatch = next;
        }
      }
    } finally {
      n.loading = false;
    }
  }

  int get _remaining {
    final total = totalCap - loadedCount;
    return total < _budget ? total : _budget;
  }

  void _addPage(SpaceTreeNode n, HierarchyPage page) {
    for (final info in page.rooms) {
      if (info.roomId == n.roomId) {
        n.info = info;
        continue;
      }
      // Only the space's own children: a server may send anything.
      final links = n.info?.children;
      HierarchyChildLink? link;
      if (links != null && links.isNotEmpty) {
        for (final l in links) {
          if (l.roomId == info.roomId) {
            link = l;
            break;
          }
        }
        if (link == null) continue;
      }
      // Seen already (twice in one space, or a space inside itself).
      if (_byId.containsKey(info.roomId)) continue;
      if (_remaining <= 0) {
        if (!_paused.contains(n)) _paused.add(n);
        break;
      }

      final child = SpaceTreeNode(info.roomId,
          info: info,
          parent: n,
          depth: n.depth + 1,
          suggested: link?.suggested ?? false,
          via: link?.via ?? const []);
      _byId[info.roomId] = child;
      n.children.add(child);
      loadedCount++;
      _budget--;

      if (!selectable(child)) continue;
      if (_tickAllOnLoad.contains(n.roomId)) {
        if (_tick(child) && child.isSpace) _tickAllOnLoad.add(child.roomId);
      } else if (_followSuggested && child.suggested) {
        _tick(child);
      }
    }
  }

  bool _tick(SpaceTreeNode n) {
    if (selected.contains(n.roomId)) return true;
    if (selected.length >= selectionCap) {
      truncatedFrom = (truncatedFrom ?? selectionCap) + 1;
      return false;
    }
    selected.add(n.roomId);
    return true;
  }

  /// Continues every load that stopped at the batch cap, for one more
  /// batch.
  Future<void> loadMore() async {
    if (!canLoadMore) return;
    _budget = batchCap;
    final paused = List.of(_paused);
    _paused.clear();
    for (final n in paused) {
      await loadChildren(n);
    }
  }

  /// Opens [n], loading its children the first time.
  Future<void> expand(SpaceTreeNode n) async {
    if (!canExpand(n)) return;
    n.expanded = true;
    await loadChildren(n);
  }

  /// Every loaded node under [n], in tree order.
  Iterable<SpaceTreeNode> descendants(SpaceTreeNode n) sync* {
    for (final c in n.children) {
      yield c;
      yield* descendants(c);
    }
  }

  /// true = ticked, false = not, null = some of it (a dash).
  bool? stateOf(SpaceTreeNode n) {
    final ids = [
      if (selectable(n)) n,
      if (n.isSpace) ...descendants(n).where(selectable),
    ];
    if (ids.isEmpty) return isJoined(n.roomId);
    final count = ids.where((i) => selected.contains(i.roomId)).length;
    if (count == 0) return false;
    if (count == ids.length) return true;
    return null;
  }

  /// Ticks or unticks [n]; for a subspace, everything loaded under it too.
  void toggle(SpaceTreeNode n) {
    truncatedFrom = null;
    if (!n.isSpace) {
      if (!selectable(n)) return;
      if (!selected.remove(n.roomId)) _tick(n);
      return;
    }
    final all = [n, ...descendants(n)];
    if (stateOf(n) == true) {
      for (final i in all) {
        selected.remove(i.roomId);
        _tickAllOnLoad.remove(i.roomId);
      }
      return;
    }
    for (final i in all) {
      if (i.isSpace) _tickAllOnLoad.add(i.roomId);
      if (selectable(i)) _tick(i);
    }
    if (truncatedFrom != null) _tickAllOnLoad.clear();
  }

  /// Ticks everything, after opening the unloaded subspaces within what's
  /// left of the current batch (never more), and at most [actionCap].
  Future<void> selectAll() async {
    final queue = descendants(root)
        .where((n) => n.isSpace && !n.fullyLoaded && canExpand(n))
        .toList();
    while (queue.isNotEmpty && _remaining > 0) {
      final n = queue.removeAt(0);
      await loadChildren(n);
      queue.addAll(n.children.where((c) => c.isSpace && canExpand(c)));
    }
    final all = descendants(root).where(selectable).toList();
    selected
      ..clear()
      ..addAll(all.take(selectionCap).map((n) => n.roomId));
    truncatedFrom = all.length > selectionCap ? all.length : null;
    _tickAllOnLoad.clear();
    _followSuggested = false;
  }

  void selectNone() {
    selected.clear();
    _tickAllOnLoad.clear();
    _followSuggested = false;
    truncatedFrom = null;
  }

  void selectSuggested() {
    selected.clear();
    _tickAllOnLoad.clear();
    truncatedFrom = null;
    _followSuggested = true;
    for (final n in descendants(root)) {
      if (n.suggested && selectable(n)) _tick(n);
    }
  }

  /// The ticked nodes in tree order (a subspace before its rooms).
  List<SpaceTreeNode> get selectedInOrder =>
      descendants(root).where((n) => selected.contains(n.roomId)).toList();

  /// Where to join [n] through: its own link's servers, else its parents'.
  List<String> viaFor(SpaceTreeNode n) {
    SpaceTreeNode? at = n;
    while (at != null) {
      if (at.via.isNotEmpty) return at.via;
      at = at.parent;
    }
    return const [];
  }

  /// The rows to show: open subspaces' children, or with a [filter], the
  /// matching loaded entries plus the subspaces they sit in.
  List<SpaceTreeNode> visibleRows({String filter = ""}) {
    final result = <SpaceTreeNode>[];
    final f = filter.trim().toLowerCase();
    if (f.isEmpty) {
      void walkOpen(SpaceTreeNode n) {
        for (final c in n.children) {
          result.add(c);
          if (c.expanded) walkOpen(c);
        }
      }

      walkOpen(root);
      return result;
    }

    bool matches(SpaceTreeNode n) => n.name.toLowerCase().contains(f);
    bool walkMatching(SpaceTreeNode n) {
      var any = false;
      for (final c in n.children) {
        final at = result.length;
        result.add(c);
        final inside = walkMatching(c);
        if (inside || matches(c)) {
          any = true;
        } else {
          result.removeRange(at, result.length);
        }
      }
      return any;
    }

    walkMatching(root);
    return result;
  }

  int get loadedSpaces =>
      _byId.values.where((n) => n != root && n.isSpace).length;

  int get loadedRooms => _byId.values.where((n) => !n.isSpace).length;
}
