/// Vommet issue 99: you can end up with more than one direct message room
/// with the same person (both pressed "Message" at once, an old DM was left
/// and a new one made, a bridge made its own). The lists show one row per
/// person: the room with the newest activity, which is also the one the
/// SDK's `startDirectChat` picks. The other rooms stay reachable from that
/// row and from the room's header.
class DmGroups {
  /// [rooms] grouped by their direct message partner, each group newest
  /// activity first. Rooms without a partner are left out. Ties go by
  /// [idOf], so the pick doesn't flip between builds.
  static Map<String, List<R>> byPartner<R>(
    Iterable<R> rooms, {
    required String? Function(R room) partnerOf,
    required DateTime Function(R room) lastActivity,
    required String Function(R room) idOf,
  }) {
    final groups = <String, List<R>>{};
    for (final room in rooms) {
      final partner = partnerOf(room);
      if (partner == null) continue;
      (groups[partner] ??= []).add(room);
    }
    for (final group in groups.values) {
      if (group.length < 2) continue;
      group.sort((a, b) {
        final byTime = lastActivity(b).compareTo(lastActivity(a));
        return byTime != 0 ? byTime : idOf(a).compareTo(idOf(b));
      });
    }
    return groups;
  }

  /// Whether [room] is an older room of a person with several: the lists
  /// leave it out and show the newest one instead.
  static bool isOlder<R>(R room, List<R>? group) =>
      group != null &&
      group.length > 1 &&
      !identical(group.first, room) &&
      group.contains(room);

  /// The newest room of each group with more than one, by partner: what
  /// the lists show. When it changes, the lists have to look again.
  static Map<String, R> shownOfShared<R>(Map<String, List<R>> groups) => {
        for (final entry in groups.entries)
          if (entry.value.length > 1) entry.key: entry.value.first,
      };

  /// The counts a person's row shows: every room's added up.
  static ({int notifications, int highlights}) addCounts<R>(
    Iterable<R> rooms, {
    required int Function(R room) notifications,
    required int Function(R room) highlights,
  }) {
    var n = 0, h = 0;
    for (final room in rooms) {
      n += notifications(room);
      h += highlights(room);
    }
    return (notifications: n, highlights: h);
  }
}
