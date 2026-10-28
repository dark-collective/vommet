import 'package:collection/collection.dart';

/// Vommet: where each room sits in your spaces, so the forward picker can
/// tell apart rooms with the same name (Vommet issue 252).
class SpacePaths {
  /// Maps each room id to every chain of spaces leading to it, from a
  /// top-level space down to the space that holds the room, shortest first.
  /// Spaces that contain themselves (directly or further down) are walked
  /// once per chain, and chains stop at [maxDepth].
  static Map<String, List<List<S>>> index<S>(
    Iterable<S> topLevel, {
    required Iterable<String> Function(S space) roomIds,
    required Iterable<S> Function(S space) subspaces,
    required String Function(S space) id,
    int maxDepth = 8,
  }) {
    final result = <String, List<List<S>>>{};

    void walk(S space, List<S> path) {
      if (path.length >= maxDepth) return;
      if (path.any((s) => id(s) == id(space))) return;

      final chain = [...path, space];
      for (final roomId in roomIds(space)) {
        result.putIfAbsent(roomId, () => []).add(chain);
      }
      for (final sub in subspaces(space)) {
        walk(sub, chain);
      }
    }

    for (final space in topLevel) {
      walk(space, const []);
    }

    for (final paths in result.values) {
      mergeSort(paths, compare: (a, b) => a.length.compareTo(b.length));
    }
    return result;
  }

  /// The chain to show under a room, as "Space › Subspace". [inside] is the
  /// space the list is filtered to: the part of the chain down to it is left
  /// out, and a room directly in it gets no label. Returns null when the room
  /// is in no space (or directly in [inside]).
  static String? label<S>(
    List<List<S>>? paths, {
    required String Function(S space) name,
    required String Function(S space) id,
    List<S> inside = const [],
  }) {
    if (paths == null || paths.isEmpty) return null;

    final insideIds = inside.map(id).toList();
    final chains = paths
        .where((chain) =>
            chain.length >= insideIds.length &&
            const ListEquality<String>().equals(
                chain.take(insideIds.length).map(id).toList(), insideIds))
        .map((chain) => chain.skip(insideIds.length).toList())
        .toList();
    if (chains.isEmpty || chains.first.isEmpty) return null;

    final text = chains.first.map(name).join(" › ");
    final others = chains.length - 1;
    return others > 0 ? "$text +$others" : text;
  }
}
