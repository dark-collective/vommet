// Vommet: what inviting someone to a space also invites them to: the space's
// rooms and subspaces you can invite to, and the order to invite in (the
// space first, then each subspace before its rooms). Pure Dart so it can be
// unit tested.

import 'package:commet/utils/space_hierarchy/space_tree.dart';

/// How a room's history goes along with an invite (MSC4268).
enum InviteHistory {
  /// Encrypted, and its history is visible to new members: the invite also
  /// sends the keys to its earlier messages.
  included,

  /// Encrypted, but history isn't shared with new members.
  newMessagesOnly,

  /// Not encrypted: the server shows history as the room's settings say.
  notEncrypted,

  /// A subspace: no messages of its own.
  space,

  /// You don't have permission to invite people here.
  cannotInvite,

  /// They're already in the room or invited to it.
  alreadyMember,
}

extension InviteHistoryInvitable on InviteHistory {
  bool get invitable =>
      this != InviteHistory.cannotInvite && this != InviteHistory.alreadyMember;
}

class InvitePlan {
  /// The space first, then everything ticked in [tree], each subspace
  /// before the rooms in it.
  static List<String> order(SpaceTree tree) {
    final ordered = <String>[tree.root.roomId];
    void walk(SpaceTreeNode n) {
      for (final c in n.children) {
        if (tree.selected.contains(c.roomId) && !ordered.contains(c.roomId)) {
          ordered.add(c.roomId);
        }
        walk(c);
      }
    }

    walk(tree.root);
    return ordered;
  }

  /// "Invite", "Invite to space + 1 room", "Invite to space + 4 rooms and
  /// 2 subspaces".
  static String buttonLabel({required int rooms, required int subspaces}) {
    if (rooms == 0 && subspaces == 0) return "Invite";
    String n(int count, String one, String many) =>
        count == 1 ? "1 $one" : "$count $many";
    final parts = [
      if (rooms > 0) n(rooms, "room", "rooms"),
      if (subspaces > 0) n(subspaces, "subspace", "subspaces"),
    ];
    return "Invite to space + ${parts.join(" and ")}";
  }
}
