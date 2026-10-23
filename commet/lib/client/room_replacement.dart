import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/utils/notifying_list.dart';

// Vommet: replacing a room (m.room.tombstone) and following a replaced one.
// The Matrix side lives in `client/matrix/matrix_room_replacement.dart`;
// the helpers at the bottom are plain logic, unit tested on their own.

/// What a room's tombstone says: the conversation moved to
/// [replacementRoomId].
class RoomTombstone {
  const RoomTombstone(
      {required this.replacementRoomId, this.body, this.senderId});

  final String replacementRoomId;

  /// The message the replacer left, if any.
  final String? body;
  final String? senderId;
}

/// The older room a room continues (its m.room.create `predecessor`).
class RoomPredecessor {
  const RoomPredecessor(
      {required this.roomId, this.upgradedBy, this.upgradedAt});

  final String roomId;

  /// Display name of whoever upgraded it (the new room's creator).
  final String? upgradedBy;
  final DateTime? upgradedAt;
}

/// The room versions a server offers (`m.room_versions` capability).
class RoomVersionOptions {
  const RoomVersionOptions(
      {required this.defaultVersion,
      required this.stable,
      this.unstable = const []});

  final String defaultVersion;
  final List<String> stable;
  final List<String> unstable;

  /// Every offered version, newest first: stable ones, then unstable.
  List<String> get all => [
        ...sortRoomVersions(stable),
        ...sortRoomVersions(unstable),
      ];

  String? get newestStable {
    final sorted = sortRoomVersions(stable);
    return sorted.isEmpty ? null : sorted.first;
  }

  /// What the picker starts on: the server's default, unless it offers a
  /// newer stable version.
  String get initialChoice {
    final newest = newestStable;
    if (newest == null) return defaultVersion;
    return compareRoomVersions(newest, defaultVersion) > 0
        ? newest
        : defaultVersion;
  }
}

/// The two ways to replace a room.
enum RoomReplacementKind {
  /// Server-side `/upgrade`: a copy on a newer room version.
  upgrade,

  /// A tombstone pointing at a room that already exists.
  existing,
}

abstract class RoomReplacement {
  /// Set once the room was replaced.
  RoomTombstone? get tombstone;

  /// Set when this room continues an older one.
  RoomPredecessor? get predecessor;

  /// This room's version, when known.
  String? get roomVersion;

  /// Whether the user may replace this room (can send m.room.tombstone).
  bool get canReplace;

  /// Joined members other than the user (for the "invite" checkbox).
  int get otherMemberCount;

  /// Spaces the user can edit that list this room as a child.
  List<Space> get swappableSpaces;

  Future<RoomVersionOptions?> getVersionOptions();

  /// Upgrades the room on the server; returns the new room's id.
  /// [additionalCreators] become co-owners of a v12+ replacement.
  Future<String> upgrade(String version, {List<String>? additionalCreators});

  /// Points the room at [roomId] with a tombstone.
  Future<void> replaceWith(String roomId, {String? body});

  /// In each of [spaces], lists [newRoomId] where this room was (same order
  /// and suggested flag) and removes this room.
  Future<void> swapInSpaces(String newRoomId, List<Space> spaces);

  /// Invites this room's joined members to [newRoomId]; returns how many
  /// invites failed.
  Future<int> inviteMembersTo(String newRoomId);

  /// The room the conversation moved to, joining it first if needed.
  Future<Room> openReplacement();

  /// The predecessor room, when the user is still in it.
  Room? get predecessorRoom;
}

/// Content of an m.room.tombstone pointing at [replacementRoomId].
Map<String, Object?> buildTombstoneContent(
    String replacementRoomId, String? body, String fallbackBody) {
  final trimmed = body?.trim() ?? "";
  return {
    "body": trimmed.isEmpty ? fallbackBody : trimmed,
    "replacement_room": replacementRoomId,
  };
}

/// Reads a tombstone's content; null when it doesn't name a replacement.
RoomTombstone? parseTombstone(Map<String, Object?>? content,
    {String? senderId}) {
  if (content == null) return null;
  final replacement = content["replacement_room"];
  if (replacement is! String || replacement.isEmpty) return null;
  final body = content["body"];
  final trimmed = body is String ? body.trim() : "";
  return RoomTombstone(
      replacementRoomId: replacement,
      body: trimmed.isEmpty ? null : trimmed,
      senderId: senderId);
}

/// Reads m.room.create's `predecessor`; null when the room has none.
String? parsePredecessorRoomId(Map<String, Object?>? createContent) {
  final predecessor = createContent?["predecessor"];
  if (predecessor is! Map) return null;
  final id = predecessor["room_id"];
  return id is String && id.isNotEmpty ? id : null;
}

/// The m.space.child content for the room taking over from one whose child
/// content was [old]: same order and suggested flag, [via] for the new room.
Map<String, Object?> swappedSpaceChildContent(
    Map<String, Object?> old, List<String> via) {
  final order = old["order"];
  final suggested = old["suggested"];
  return {
    "via": via,
    if (order is String) "order": order,
    if (suggested is bool) "suggested": suggested,
  };
}

/// Servers to reach a new room by: [preferred] first (ours), then the old
/// child's vias, no repeats, at most three.
List<String> replacementVia(String? preferred, Object? oldVia) {
  final result = <String>[];
  void add(Object? server) {
    if (server is String && server.isNotEmpty && !result.contains(server)) {
      result.add(server);
    }
  }

  add(preferred);
  if (oldVia is List) oldVia.forEach(add);
  return result.take(3).toList();
}

/// Who to invite to the new room: the old room's joined members, minus the
/// user and anyone already joined or invited there.
List<String> membersToInvite(Iterable<String> joinedMembers, String ownUserId,
    Set<String> alreadyInNewRoom) {
  return joinedMembers
      .where((id) => id != ownUserId && !alreadyInNewRoom.contains(id))
      .toSet()
      .toList();
}

/// The "invite the members" box starts ticked unless anyone can join.
bool defaultInviteMembers(RoomVisibility visibility) =>
    visibility is! RoomVisibilityPublic;

/// Element hides a replaced room once you're in its replacement; until then
/// it stays, so you can still follow the link.
bool shouldHideReplacedRoom(
    RoomTombstone? tombstone, bool Function(String roomId) isJoined) {
  if (tombstone == null) return false;
  return isJoined(tombstone.replacementRoomId);
}

/// Orders room versions like numbers where they are ("10" > "9"), the rest
/// by text. Returns > 0 when [a] is newer.
int compareRoomVersions(String a, String b) {
  final na = int.tryParse(a);
  final nb = int.tryParse(b);
  if (na != null && nb != null) return na.compareTo(nb);
  if (na != null) return -1;
  if (nb != null) return 1;
  return a.compareTo(b);
}

/// [versions] newest first.
List<String> sortRoomVersions(Iterable<String> versions) =>
    versions.toList()..sort((a, b) => compareRoomVersions(b, a));

/// The replacer's own message for the composer notice, or null when it is
/// missing or just a server's stock text ("This room has been replaced").
String? replacedNoticeMessage(RoomTombstone? tombstone) {
  final body = tombstone?.body?.trim();
  if (body == null || body.isEmpty) return null;
  final plain = body.toLowerCase().replaceAll(RegExp(r"[.!]+$"), "");
  const stock = {
    "this room has been replaced",
    "this room was upgraded",
    "this room has been upgraded",
  };
  return stock.contains(plain) ? null : body;
}

/// Whether the sidebar should leave [room] out: it was replaced and you're
/// in its replacement.
bool isSupersededRoom(Room room) => shouldHideReplacedRoom(
    room.replacement?.tombstone,
    (id) => room.client.getRoom(id)?.isBanned == false);

/// Fires when a room that continues an older one joins or leaves [rooms],
/// which can change what [isSupersededRoom] says about that older room.
/// Delivered after the change, so a filter re-checking on it sees the list
/// as it ends up (Vommet issue 311: an upgraded DM stayed listed).
Stream<void> roomReplacementsChanged(INotifyingList<Room> rooms) {
  final changed = StreamController<void>();
  void onChange(Room room) {
    if (room.replacement?.predecessor != null) changed.add(null);
  }

  rooms.onAdd.listen(onChange);
  rooms.onRemove.listen(onChange);
  return changed.stream;
}

/// The replacement room picker's search: every word of [query] appears in
/// the room's name or id, ignoring case.
bool roomMatchesQuery(String name, String id, String query) {
  final words = query.toLowerCase().split(RegExp(r"\s+"))
    ..removeWhere((w) => w.isEmpty);
  final haystack = "${name.toLowerCase()} ${id.toLowerCase()}";
  return words.every(haystack.contains);
}
