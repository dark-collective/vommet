/// Vommet: naming helpers for emoticon pack imports.
class EmoticonNames {
  /// [base] if it is free, otherwise the first of `base_2`, `base_3`, …
  /// that is not in [taken]. Used for shortcodes merged into an existing pack
  /// and for new pack state keys, so an import never overwrites anything.
  static String unique(String base, Iterable<String> taken) {
    final used = taken.toSet();
    if (!used.contains(base)) return base;
    for (var i = 2;; i++) {
      final candidate = "${base}_$i";
      if (!used.contains(candidate)) return candidate;
    }
  }

  /// Names for [incoming] that collide neither with [existing] nor with each
  /// other, in order.
  static List<String> uniqueAll(
      Iterable<String> incoming, Iterable<String> existing) {
    final used = existing.toSet();
    final result = <String>[];
    for (final name in incoming) {
      final picked = unique(name, used);
      used.add(picked);
      result.add(picked);
    }
    return result;
  }
}
