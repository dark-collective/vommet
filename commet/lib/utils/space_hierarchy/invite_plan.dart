// Vommet: how a room's history goes along when inviting someone to it.
// Pure Dart so it can be unit tested.

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
