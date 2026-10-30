/// Ranks rooms (or anything with a name and an id) against a typed query.
///
/// Matching is case-insensitive. Better matches come first:
///   0. the name starts with the query
///   1. a word in the name starts with the query
///   2. the name contains the query
///   3. the id contains the query (e.g. pasting part of a room id)
/// Within the same rank the most recently active item wins, then the
/// original order. An empty query returns the items unchanged.
class RoomSearch {
  static final RegExp _wordSeparators = RegExp(r"[\s\-_#:.,/()\[\]]+");

  static List<T> rank<T>(List<T> items, String query,
      {required String Function(T item) name,
      required String Function(T item) id,
      DateTime? Function(T item)? lastActive}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List.of(items);

    final scored = <(int, int, T)>[];
    for (var i = 0; i < items.length; i++) {
      final s = score(name(items[i]), id(items[i]), q);
      if (s != null) scored.add((s, i, items[i]));
    }

    scored.sort((a, b) {
      final byScore = a.$1.compareTo(b.$1);
      if (byScore != 0) return byScore;

      if (lastActive != null) {
        final ta = lastActive(a.$3);
        final tb = lastActive(b.$3);
        if (ta != null && tb != null) {
          final byTime = tb.compareTo(ta);
          if (byTime != 0) return byTime;
        } else if (ta != null) {
          return -1;
        } else if (tb != null) {
          return 1;
        }
      }

      return a.$2.compareTo(b.$2);
    });

    return [for (final e in scored) e.$3];
  }

  /// Rank of a single item for an already lower-cased, trimmed [query], or
  /// null when it does not match at all.
  static int? score(String name, String id, String query) {
    final n = name.toLowerCase();
    if (n.startsWith(query)) return 0;
    if (n.split(_wordSeparators).any((w) => w.startsWith(query))) return 1;
    if (n.contains(query)) return 2;
    if (id.toLowerCase().contains(query)) return 3;
    return null;
  }
}
