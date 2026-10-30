// Vommet issue 734: which pending invites go together under one space, so a
// space invite and its room invites show (and alert) as one invite.

/// Groups pending invites by space. Pure, so it can be unit tested.
class InviteGrouping {
  /// A space you're already in groups its room invites only from this many
  /// on: one invite is clearer under the room's own name.
  static const minJoinedGroup = 2;

  /// Returns head id → grouped invite room ids, in [invites] order.
  ///
  /// [invites] are the pending invites' room ids in list order;
  /// [spaceInvites] those that are spaces; [directInvites] DMs, which are
  /// never grouped. [childrenOf] holds the rooms each known space lists (an
  /// invited space's from the server's hierarchy, a joined space's from its
  /// `m.space.child` state). [joinedSpaces] are the spaces you're in.
  ///
  /// A head is an invited space with at least one room invite inside it
  /// (also through invited subspaces, which then belong to its group), or a
  /// joined space listing at least [minJoinedGroup] of the remaining room
  /// invites directly.
  static Map<String, List<String>> group({
    required List<String> invites,
    required Set<String> spaceInvites,
    required Set<String> directInvites,
    required Map<String, Set<String>> childrenOf,
    required List<String> joinedSpaces,
  }) {
    final order = {for (final (i, id) in invites.indexed) id: i};
    final groupable = {
      for (final id in invites)
        if (!directInvites.contains(id)) id
    };

    Set<String> reach(String space) {
      final found = <String>{};
      final seen = {space};
      final queue = [space];
      while (queue.isNotEmpty) {
        final at = queue.removeLast();
        for (final child in childrenOf[at] ?? const <String>{}) {
          if (!seen.add(child)) continue;
          if (groupable.contains(child)) found.add(child);
          if (spaceInvites.contains(child)) queue.add(child);
        }
      }
      return found;
    }

    List<String> sorted(Iterable<String> ids) =>
        ids.toList()..sort((a, b) => order[a]!.compareTo(order[b]!));

    final spaces = [
      for (final id in invites)
        if (spaceInvites.contains(id) && groupable.contains(id)) id
    ];
    final reached = {for (final s in spaces) s: reach(s)};
    // Outermost invited spaces first; a subspace you're also invited to goes
    // into its parent's group.
    final roots = [
      for (final s in spaces)
        if (!spaces.any((o) => o != s && reached[o]!.contains(s))) s,
      for (final s in spaces)
        if (spaces.any((o) => o != s && reached[o]!.contains(s))) s,
    ];

    final groups = <String, List<String>>{};
    final assigned = <String>{};
    for (final space in roots) {
      if (assigned.contains(space)) continue;
      final members = reached[space]!
          .where((id) => id != space && !assigned.contains(id))
          .toList();
      if (members.isEmpty) continue;
      assigned
        ..add(space)
        ..addAll(members);
      groups[space] = sorted(members);
    }

    for (final space in joinedSpaces) {
      if (groupable.contains(space)) continue;
      final members = (childrenOf[space] ?? const <String>{})
          .where((id) => groupable.contains(id) && !assigned.contains(id))
          .toList();
      if (members.length < minJoinedGroup) continue;
      assigned.addAll(members);
      groups[space] = sorted(members);
    }
    return groups;
  }
}
