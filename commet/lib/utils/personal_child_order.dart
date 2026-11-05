class PersonalChildOrder {
  static List<String>? parse(Map<String, Object?>? content) {
    final order = content?['order'];
    if (order is! List) return null;
    return order
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  /// A fresh projection: existing saved IDs first, unseen children in default
  /// order. Never mutates a caller's (often shared) lists.
  static List<T> project<T>(
      Iterable<T> defaults, List<String>? saved, String Function(T) id) {
    final byId = <String, T>{};
    for (final value in defaults) {
      byId.putIfAbsent(id(value), () => value);
    }
    return [
      for (final key in saved ?? const <String>[])
        if (byId.remove(key) case final value?) value,
      ...byId.values,
    ];
  }

  /// Missing children may only be lazily loaded. Keep their saved slots while
  /// replacing the visible slots with the edited order; append newly seen IDs.
  static List<String> preserveMissing(
      List<String>? saved, List<String> edited) {
    final unique = edited.toSet().toList();
    final visible = unique.toSet();
    var index = 0;
    return [
      for (final id in (saved ?? const <String>[]).toSet())
        if (!visible.contains(id)) id else unique[index++],
      ...unique.skip(index),
    ];
  }

  static Map<String, Object?> content(
          Map<String, Object?> previous, List<String>? order) =>
      {...previous}
        ..remove('order')
        ..addAll({if (order != null) 'order': order.toSet().toList()});
}
