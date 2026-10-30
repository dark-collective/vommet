/// Vommet: what a chat is right now, for the "New room info page"
/// experiment's live direct-chat rules. A room listed in the account's
/// m.direct is shown as a person only while it really is between two people;
/// nothing here ever edits m.direct.
enum DmShapeKind {
  /// A direct chat with one other person (joined or invited).
  person,

  /// A direct chat whose other person left (or was banned): still shown as
  /// that person, with "Left the chat".
  leftPartner,

  /// Any other room, including a direct chat that now has three or more
  /// people ([DmShape.convertedFromDm]).
  group,
}

class DmShape {
  const DmShape(this.kind, {this.partnerId, this.convertedFromDm = false});

  /// A room that isn't a direct chat.
  static const DmShape room = DmShape(DmShapeKind.group);

  final DmShapeKind kind;

  /// The person the direct chat is with (m.direct), when it is one.
  final String? partnerId;

  /// A group that started as a direct chat (it's still in m.direct): "Started
  /// as a direct chat with [partnerId]".
  final bool convertedFromDm;

  /// Shown as a person (profile tab, presence, the person's name and
  /// picture) rather than as a group.
  bool get isPerson => kind != DmShapeKind.group;

  bool get partnerLeft => kind == DmShapeKind.leftPartner;

  @override
  bool operator ==(Object other) =>
      other is DmShape &&
      other.kind == kind &&
      other.partnerId == partnerId &&
      other.convertedFromDm == convertedFromDm;

  @override
  int get hashCode => Object.hash(kind, partnerId, convertedFromDm);

  @override
  String toString() =>
      "DmShape($kind, partner: $partnerId, convertedFromDm: $convertedFromDm)";

  /// Decides the shape. [activeMemberIds] are the joined and invited members
  /// known locally; [activeMemberCount] is the server's count of them (the
  /// room summary), which wins when members are lazy-loaded. A
  /// [partnerMembership] of "leave" or "ban" means the partner left; an
  /// unknown membership never counts as left.
  static DmShape decide({
    required bool inMDirect,
    required Iterable<String> activeMemberIds,
    required String ownId,
    String? partnerId,
    String? partnerMembership,
    int? activeMemberCount,
  }) {
    if (!inMDirect) return room;
    final active = {...activeMemberIds, ownId};
    final count = activeMemberCount == null || activeMemberCount < active.length
        ? active.length
        : activeMemberCount;
    final others = active.where((id) => id != ownId);
    final partner = partnerId ?? (others.length == 1 ? others.first : null);
    if (count >= 3) {
      return DmShape(DmShapeKind.group,
          partnerId: partner, convertedFromDm: true);
    }
    if (partner != null &&
        (partnerMembership == "leave" || partnerMembership == "ban")) {
      return DmShape(DmShapeKind.leftPartner, partnerId: partner);
    }
    return DmShape(DmShapeKind.person, partnerId: partner);
  }
}

/// "Juniper and Kit", "Juniper, Kit and Ash", "Juniper, Kit, Ash and 2
/// others": an unnamed group's name from the other members' names. [total]
/// is how many other members there are (at least [names].length).
String dmGroupName(List<String> names, {int? total}) {
  if (names.isEmpty) return "";
  final all = total == null || total < names.length ? names.length : total;
  final listed = names.take(3).toList();
  final rest = all - listed.length;
  if (rest > 0) {
    return "${listed.join(", ")} and $rest ${rest == 1 ? "other" : "others"}";
  }
  if (listed.length == 1) return listed.first;
  return "${listed.sublist(0, listed.length - 1).join(", ")} and "
      "${listed.last}";
}
