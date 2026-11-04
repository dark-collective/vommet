import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/personal_space_order.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/components/space_component.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/room_preview.dart';
import 'package:commet/client/space_child.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'unread_fixtures.dart';

class ArrangeClient extends UnreadClient {
  ArrangeClient() : super('@alex:example.org') {
    addTearDown(close);
  }
  @override
  Profile? self;
  @override
  T? getComponent<T extends Component>() => null;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class ArrangePermissions extends Permissions {
  ArrangePermissions(this.admin);
  final bool admin;
  @override
  bool get canEditChildren => admin;
  @override
  bool get canInviteUser => false;
  @override
  bool get canEditAnything => admin;
}

class ArrangeRoom implements Room {
  ArrangeRoom(this.identifier, this.displayName, this.client);
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  final Client client;
  @override
  String get localId => '${client.identifier}:$identifier';
  @override
  bool get isBanned => false;
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => Colors.teal;
  @override
  Stream<void> get onUpdate => const Stream.empty();
  @override
  T? getComponent<T extends RoomComponent>() => null;
  @override
  PushRule get pushRule => PushRule.notify;
  @override
  int get notificationCount => 0;
  @override
  int get highlightedNotificationCount => 0;
  @override
  bool get messagesAreNoisy => false;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class ArrangeSpace extends Space implements PersonalSpaceOrdering {
  ArrangeSpace(
      {this.displayName = 'Garden community',
      this.identifier = '!garden:example.org',
      bool admin = false})
      : permissions = ArrangePermissions(admin);
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  final Client client = ArrangeClient();
  @override
  final Permissions permissions;
  final updates = StreamController<void>.broadcast();
  List<SpaceChild> items = [];
  @override
  List<String>? personalChildOrder;
  @override
  String get personalOrderAccountId => client.identifier;
  int writes = 0;
  bool failSave = false;
  Completer<void>? pendingSave;
  @override
  Future<void> savePersonalChildOrder(List<String>? order) async {
    writes++;
    if (pendingSave != null) await pendingSave!.future;
    if (failSave) throw StateError('Fixture save failed');
    personalChildOrder = order?.toList();
    updates.add(null);
  }

  void changed() => updates.add(null);
  @override
  List<SpaceChild> get allChildren => items.toList();
  @override
  List<SpaceChild> get children =>
      items.where((i) => i is! SpaceChildUnjoined).toList();
  @override
  List<Room> get rooms =>
      children.whereType<SpaceChildRoom>().map((i) => i.child).toList();
  @override
  List<Space> get subspaces =>
      children.whereType<SpaceChildSpace>().map((i) => i.child).toList();
  @override
  List<RoomPreview> get childPreviews => [];
  @override
  bool get fullyLoaded => true;
  @override
  Future<void> loadExtra() async {}
  @override
  Stream<void> get onUpdate => updates.stream;
  @override
  Stream<void> get onChildRoomsUpdated => const Stream.empty();
  @override
  Stream<void> get onChildRoomPreviewsUpdated => const Stream.empty();
  @override
  Stream<Space> get onChildSpaceAdded => const Stream.empty();
  @override
  Stream<Space> get onChildSpaceRemoved => const Stream.empty();
  @override
  Stream<Room> get onRoomAdded => const Stream.empty();
  @override
  Stream<Room> get onRoomRemoved => const Stream.empty();
  @override
  Stream<RoomPreview> get onChildRoomPreviewAdded => const Stream.empty();
  @override
  Stream<RoomPreview> get onChildRoomPreviewRemoved => const Stream.empty();
  @override
  Color get color => Colors.teal;
  @override
  ImageProvider? get avatar => null;
  @override
  T? getComponent<T extends SpaceComponent>() => null;
  @override
  PushRule get pushRule => PushRule.notify;
  @override
  RoomVisibility get visibility => RoomVisibilityPublic();
  @override
  String get topic => 'A place to grow ideas together.';
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

ArrangeSpace personalOrderFixture({bool admin = false}) {
  final root = ArrangeSpace(admin: admin);
  final projects = ArrangeSpace(
      displayName: 'Projects', identifier: '!projects:example.org');
  projects.items = [
    SpaceChildRoom(
        ArrangeRoom('!planning:example.org', 'planning', root.client))
  ];
  root.items = [
    SpaceChildRoom(ArrangeRoom(
        '!announcements:example.org', 'announcements', root.client)),
    SpaceChildRoom(ArrangeRoom('!general:example.org', 'general', root.client)),
    SpaceChildSpace(projects),
    SpaceChildRoom(ArrangeRoom('!lounge:example.org', 'lounge', root.client)),
    SpaceChildUnjoined('!help:example.org', null),
  ];
  root.personalChildOrder = [
    root.items[2].id,
    root.items[1].id,
    root.items[0].id,
    root.items[3].id,
    root.items[4].id
  ];
  return root;
}
