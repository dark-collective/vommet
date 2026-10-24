// Vommet: maps Matrix join rules (m.room.join_rules) to Commet's
// RoomVisibility and back, including knocking ("Ask to join"), and tells which
// room versions support knocking.
import 'package:commet/client/room.dart';

/// Visibility for a raw `join_rule` value. [allow] is the list of room ids
/// from the event's `allow` conditions (restricted / knock_restricted).
/// A missing join rule keeps Commet's old behaviour (public).
RoomVisibility roomVisibilityFromJoinRule(String? joinRule,
    {List<String> allow = const []}) {
  return switch (joinRule) {
    null => RoomVisibilityPublic(),
    "public" => RoomVisibilityPublic(),
    "knock" => RoomVisibilityKnock(const []),
    "knock_restricted" => RoomVisibilityKnock(allow),
    "restricted" => RoomVisibilityRestricted(allow),
    _ => RoomVisibilityPrivate(),
  };
}

/// The room ids in a join rules event's `allow` list.
List<String> joinRuleAllowedRooms(Map<String, dynamic>? content) {
  final allow = content?["allow"];
  if (allow is! List) return [];
  return [
    for (final entry in allow)
      if (entry is Map && entry["room_id"] is String) entry["room_id"] as String
  ];
}

/// Content of the `m.room.join_rules` state event for [visibility].
Map<String, dynamic> joinRuleContent(RoomVisibility visibility) {
  List<Map<String, dynamic>> allow(List<String> spaces) => [
        for (final id in spaces) {"room_id": id, "type": "m.room_membership"},
      ];

  return switch (visibility) {
    final RoomVisibilityPublic _ => {"join_rule": "public"},
    final RoomVisibilityPrivate _ => {"join_rule": "invite"},
    final RoomVisibilityRestricted r => {
        "join_rule": "restricted",
        "allow": allow(r.spaces),
      },
    final RoomVisibilityKnock k when k.spaces.isEmpty => {"join_rule": "knock"},
    final RoomVisibilityKnock k => {
        "join_rule": "knock_restricted",
        "allow": allow(k.spaces),
      },
    _ => throw UnimplementedError(),
  };
}

int? _roomVersionNumber(String? version) =>
    // A room without a version in m.room.create is version 1.
    int.tryParse(version ?? "1");

/// Knocking ("knock" join rule) needs room version 7 or later.
bool roomVersionSupportsKnock(String? version) =>
    (_roomVersionNumber(version) ?? 0) >= 7;

/// "knock_restricted" (ask to join, or join as a member of a space) needs
/// room version 10 or later.
bool roomVersionSupportsKnockRestricted(String? version) =>
    (_roomVersionNumber(version) ?? 0) >= 10;
