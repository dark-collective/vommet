// Vommet: the pending edits on the "Manage rooms" page (experiment
// `experiment_manage_space_rooms`), by ID only so it can be unit tested, and
// the operations that apply them. Nothing reaches the server until Save.

/// One operation on a space's children.
sealed class SpaceRoomsOp {
  const SpaceRoomsOp(this.parent);
  final String parent;
}

/// Add [child] to [parent] (a move's first half); [from] is a space it was
/// in, to copy its join servers from.
class AddChildOp extends SpaceRoomsOp {
  const AddChildOp(super.parent, this.child, {this.from});
  final String child;
  final String? from;
  @override
  String toString() => "add $child to $parent";
}

/// Give [parent]'s children this order.
class OrderChildrenOp extends SpaceRoomsOp {
  const OrderChildrenOp(super.parent, this.children);
  final List<String> children;
  @override
  String toString() => "order $parent: ${children.join(", ")}";
}

/// Remove [child] from [parent] (a removal, or a move's second half).
class RemoveChildOp extends SpaceRoomsOp {
  const RemoveChildOp(super.parent, this.child);
  final String child;
  @override
  String toString() => "remove $child from $parent";
}

class SpaceRoomsEdit {
  /// [original]: each space's child IDs in their current order. A child may
  /// be in more than one space (Matrix allows it).
  SpaceRoomsEdit(Map<String, List<String>> original)
      : _original = {
          for (final e in original.entries) e.key: List.unmodifiable(e.value)
        },
        _current = {for (final e in original.entries) e.key: List.of(e.value)};

  final Map<String, List<String>> _original;
  final Map<String, List<String>> _current;
  final Set<(String, String)> _removed = {};

  /// [parent]'s children as shown, including removed ones (crossed out).
  List<String> childrenOf(String parent) =>
      List.unmodifiable(_current[parent] ?? const []);

  bool isRemoved(String parent, String child) =>
      _removed.contains((parent, child));

  /// [child] was moved into [parent] in this edit.
  bool isMovedIn(String parent, String child) =>
      !(_original[parent]?.contains(child) ?? false);

  /// Move within [parent], as ReorderableListView reports it.
  void reorder(String parent, int oldIndex, int newIndex) {
    final list = _current[parent]!;
    if (newIndex > oldIndex) newIndex -= 1;
    list.insert(newIndex, list.removeAt(oldIndex));
  }

  /// Swap with the nearest neighbour above that isn't crossed out.
  void moveUp(String parent, String child) {
    final list = _current[parent]!;
    final i = list.indexOf(child);
    var j = i - 1;
    while (j >= 0 && _removed.contains((parent, list[j]))) {
      j--;
    }
    if (i > 0 && j >= 0) list.insert(j, list.removeAt(i));
  }

  /// Swap with the nearest neighbour below that isn't crossed out.
  void moveDown(String parent, String child) {
    final list = _current[parent]!;
    final i = list.indexOf(child);
    var j = i + 1;
    while (j < list.length && _removed.contains((parent, list[j]))) {
      j++;
    }
    if (i >= 0 && j < list.length) list.insert(j, list.removeAt(i));
  }

  /// Move [child] from [from] to the end of [to]. If [to] already has it,
  /// it's just taken out of [from].
  void moveTo(String child, String from, String to) {
    if (from == to) return;
    _current[from]!.remove(child);
    _removed.remove((from, child));
    final target = _current.putIfAbsent(to, () => []);
    if (!target.contains(child)) target.add(child);
    _removed.remove((to, child));
  }

  void remove(String parent, String child) => _removed.add((parent, child));

  /// Spaces reachable from [root] without passing a crossed-out row (where
  /// a moved room would still be in the space after saving).
  Set<String> reachable(String root) {
    final seen = <String>{};
    void walk(String s) {
      if (!seen.add(s)) return;
      for (final c in _current[s] ?? const <String>[]) {
        if (_current.containsKey(c) && !_removed.contains((s, c))) walk(c);
      }
    }

    walk(root);
    return seen;
  }

  void undoRemove(String parent, String child) =>
      _removed.remove((parent, child));

  List<String> _effective(String parent) => [
        for (final c in _current[parent] ?? const <String>[])
          if (!_removed.contains((parent, c))) c
      ];

  /// The operations to apply: all adds first, then orders, then removals,
  /// so a moved child is never in no space if saving stops halfway.
  List<SpaceRoomsOp> plan() {
    final adds = <SpaceRoomsOp>[];
    final orders = <SpaceRoomsOp>[];
    final removes = <SpaceRoomsOp>[];
    final parents = {..._original.keys, ..._current.keys};
    for (final parent in parents) {
      final before = _original[parent] ?? const <String>[];
      final after = _effective(parent);
      final added = [
        for (final c in after)
          if (!before.contains(c)) c
      ];
      for (final c in added) {
        final from = _original.entries
            .where((e) => e.key != parent && e.value.contains(c))
            .map((e) => e.key)
            .firstOrNull;
        adds.add(AddChildOp(parent, c, from: from));
      }
      for (final c in before) {
        if (!after.contains(c)) removes.add(RemoveChildOp(parent, c));
      }
      // What the server ends up with without an explicit order: the kept
      // children in their old order, then the added ones.
      final natural = [
        for (final c in before)
          if (after.contains(c)) c,
        ...added,
      ];
      if (!_sameOrder(natural, after)) {
        orders.add(OrderChildrenOp(parent, after));
      }
    }
    return [...adds, ...orders, ...removes];
  }

  bool get hasChanges => plan().isNotEmpty;

  /// e.g. "3 changes: 1 moved, 1 reordered, 1 removed".
  String summary() {
    final ops = plan();
    final removed = ops
        .whereType<RemoveChildOp>()
        .where((r) => _removed.contains((r.parent, r.child)))
        .length;
    // A move is an add plus a removal, or just a removal when the target
    // already had it; count each moved child once.
    final moved = {
      ...ops.whereType<AddChildOp>().map((a) => a.child),
      ...ops
          .whereType<RemoveChildOp>()
          .where((r) => !_removed.contains((r.parent, r.child)))
          .map((r) => r.child),
    }.length;
    final reordered = ops.whereType<OrderChildrenOp>().length;
    final total = moved + reordered + removed;
    final parts = [
      if (moved > 0) "$moved moved",
      if (reordered > 0) "$reordered reordered",
      if (removed > 0) "$removed removed",
    ];
    return "$total ${total == 1 ? "change" : "changes"}: ${parts.join(", ")}";
  }

  /// After a successful save: what's shown becomes the new starting point.
  void commit() {
    for (final parent in {..._original.keys, ..._current.keys}) {
      final after = _effective(parent);
      _original[parent] = List.unmodifiable(after);
      _current[parent] = List.of(after);
    }
    _removed.clear();
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
