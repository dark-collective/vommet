/// Vommet: order of the "Share to…" room picker (Vommet issue 794).
/// Favorites first, then the [recentCount] rooms with the latest activity,
/// then direct messages, then everything else. Each item appears once, in the
/// first group it fits; within a group the newest activity comes first.
List<T> orderShareTargets<T>(
  Iterable<T> items, {
  required DateTime Function(T) lastActivity,
  required bool Function(T) isFavorite,
  required bool Function(T) isDirectMessage,
  int recentCount = 7,
}) {
  final rest = items.toList()
    ..sort((a, b) => lastActivity(b).compareTo(lastActivity(a)));

  final favorites = rest.where(isFavorite).toList();
  rest.removeWhere(isFavorite);

  final recent = rest.take(recentCount).toList();
  rest.removeRange(0, recent.length);

  final direct = rest.where(isDirectMessage).toList();
  rest.removeWhere(isDirectMessage);

  return [...favorites, ...recent, ...direct, ...rest];
}
