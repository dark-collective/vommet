import 'package:commet/utils/unread_index.dart';
import 'dart:async';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/space_component.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/room_preview.dart';
import 'package:commet/client/room_replacement.dart';
import 'package:commet/client/space_child.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:commet/debug/log.dart';

abstract class Space {
  late Key key = UniqueKey();

  String get identifier;

  Client get client;

  Permissions get permissions;

  String get displayName;

  ImageProvider? get avatar;

  List<Room> get rooms;

  List<Room> get roomsWithChildren {
    var result = List<Room>.from(rooms);
    // Vommet: the path is used to detect a real loop (a space that is its
    // own ancestor); the visited set adds each space's rooms only once, so a
    // space reached by two paths (a diamond) is not reported as a loop.
    // Compared by identifier: the subspaces all come from this space's
    // client, so the identifier names the space.
    final path = <Space>[this];
    final visited = <String>{identifier};

    for (var space in subspaces) {
      _addSubspaceRooms(result, space, path, visited);
    }

    return result;
  }

  // Vommet: loops already reported in this process, keyed by the sorted
  // identifiers of the spaces in the loop. The room list calls
  // roomsWithChildren on every filter change, so logging each time flooded
  // the log.
  static final Set<String> _reportedLoops = {};

  void _addSubspaceRooms(
      List<Room> rooms, Space space, List<Space> path, Set<String> visited) {
    rooms.addAll(space.rooms);
    visited.add(space.identifier);
    path.add(space);
    for (var subspace in space.subspaces) {
      final start = path.indexWhere((s) => s.identifier == subspace.identifier);
      if (start != -1) {
        _reportLoop(path.sublist(start));
      } else if (!visited.contains(subspace.identifier)) {
        _addSubspaceRooms(rooms, subspace, path, visited);
      }
    }
    path.removeLast();
  }

  static void _reportLoop(List<Space> loop) {
    final key = (loop.map((s) => s.identifier).toList()..sort()).join("|");
    if (!_reportedLoops.add(key)) return;

    var info = "";
    for (var i in loop) {
      info += " -> ${i.displayName}\n";
    }
    info += " -> ${loop.first.displayName} <- this space is in a loop\n";

    Log.w("Detected recursive space hierarchy, this is not good!\n${info}");
  }

  List<Space> get subspaces;

  List<SpaceChild> get children;

  /// Vommet: [children] plus the ones the account isn't in, in the space's
  /// order, for editors (Manage rooms) that must be able to remove a room
  /// after leaving it.
  List<SpaceChild> get allChildren => children;

  Future<void> setChildrenOrder(List<SpaceChild> children,
      {Function(double?)? onProgressChanged});

  bool get isTopLevel;

  String get topic;

  PushRule get pushRule;

  RoomVisibility get visibility;

  Color get color;

  String get developerInfo;

  Stream<void> get onUpdate;

  /// Vommet: true when we were banned from this space. It stays in the rail,
  /// faded, until the user dismisses it.
  bool get isBanned => false;

  /// The reason the moderator gave for the ban, if any.
  String? get banReason => null;

  /// Forget a banned space. Its rooms you're still in are not affected.
  Future<void> dismissBan() async {}

  Stream<Room> get onChildRoomUpdated;

  Stream<Room> get onRoomAdded;

  Stream<Room> get onRoomRemoved;

  Stream<void> get onChildRoomsUpdated;

  Stream<RoomPreview> get onChildRoomPreviewAdded;

  Stream<RoomPreview> get onChildRoomPreviewRemoved;

  Stream<Space> get onChildSpaceAdded;

  Stream<Space> get onChildSpaceRemoved;

  Stream<void> get onChildRoomPreviewsUpdated;

  List<RoomPreview> get childPreviews;

  bool get fullyLoaded;

  String get localId => "${client.identifier}:$identifier";

  PersonUnread get unread {
    final totals = UnreadTotals.rooms(
        _badgedRooms.map((r) => (r.localId, UnreadIndex.roomOf(r))));
    return pushRule == PushRule.dontNotify ? totals.mutedView : totals;
  }

  int get notificationCount => unread.notifications;
  int get highlightedNotificationCount => unread.highlights;
  int get displayNotificationCount => unread.notifications;
  int get displayHighlightedNotificationCount => unread.highlights;
  int get badgeCount => unread.badge;
  bool get badgeNoisy => unread.noisy;

  /// The rooms the space list shows (see [isSupersededRoom]).
  Iterable<Room> get _badgedRooms =>
      roomsWithChildren.where((room) => !isSupersededRoom(room));

  /// [rooms] with each room once (a room can sit in two subspaces).
  static Iterable<Room> uniqueRooms(Iterable<Room> rooms) {
    final seen = <String>{};
    return rooms.where((room) => seen.add(room.localId));
  }

  bool containsRoom(String identifier);

  Future<List<RoomPreview>> fetchChildren();

  Future<Room> createRoom(String name, CreateRoomArgs args);

  /// Adds an existing room as a child of a space
  /// [copyFrom]: the space it's moving from, to keep its join servers.
  Future<void> setSpaceChildRoom(Room room, {Space? copyFrom});

  Future<void> setSpaceChildSpace(Space room, {Space? copyFrom});

  Future<void> removeChild(SpaceChild child);

  Future<void> setTopic(String topic);

  /// Load extra information about the space, that is not necessarily required for functionality
  Future<void> loadExtra();

  Future<void> close();

  Future<void> setDisplayName(String newName);

  Future<void> changeAvatar(Uint8List bytes, String? mimeType);

  /// Remove this space's avatar
  Future<void> removeAvatar();

  Future<void> setPushRule(PushRule rule);

  T? getComponent<T extends SpaceComponent>();

  @override
  bool operator ==(Object other) {
    if (other is! Space) return false;
    if (other.client != client) return false;
    if (identical(this, other)) return true;
    return identifier == other.identifier;
  }

  @override
  int get hashCode => identifier.hashCode;
}
