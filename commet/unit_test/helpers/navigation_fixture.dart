import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/space_component.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/room_preview.dart';
import 'package:commet/client/space_child.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'unread_fixtures.dart';

// Empty account data lets navigation tests exercise the real page containers
// without a homeserver. Capture fixtures can supply real rooms and spaces.
class NavigationPageFixture extends Fake
    with Diagnosticable
    implements MainPageState {
  NavigationPageFixture(this.clientManager,
      {this.currentView = MainPageSubView.rooms, this.currentSpace});
  @override
  final ClientManager clientManager;
  @override
  MainPageSubView currentView;
  @override
  Space? currentSpace;
  @override
  Room? currentRoom;
  @override
  Client? get filterClient => null;
  @override
  Profile? get currentUser => null;
  @override
  Profile? getCurrentUser() => null;
  @override
  bool get showAsTextRoom => false;
  @override
  final favoriteRooms = NotifyingList<Room>.empty(growable: true);
  @override
  final directMessages = NotifyingList<Room>.empty(growable: true);
  @override
  final singleRooms = NotifyingList<Room>.empty(growable: true);
}

class _NavigationPermissions extends Permissions {}

class NavigationSpaceFixture extends Space {
  NavigationSpaceFixture(this.client);
  @override
  final UnreadClient client;
  @override
  String get identifier => '!lantern:example.org';
  @override
  String get displayName => 'Lantern Club';
  @override
  ImageProvider? get avatar => null;
  @override
  Color get color => Colors.teal;
  @override
  Permissions get permissions => _NavigationPermissions();
  @override
  List<Room> get rooms => const [];
  @override
  List<Space> get subspaces => const [];
  @override
  List<SpaceChild> get children => const [];
  @override
  List<RoomPreview> get childPreviews => const [];
  @override
  bool get fullyLoaded => true;
  @override
  bool get isTopLevel => true;
  @override
  String get topic => '';
  @override
  PushRule get pushRule => PushRule.notify;
  @override
  RoomVisibility get visibility => RoomVisibilityPrivate();
  @override
  Stream<void> get onUpdate => const Stream.empty();
  @override
  Stream<Room> get onChildRoomUpdated => const Stream.empty();
  @override
  Stream<Room> get onRoomAdded => const Stream.empty();
  @override
  Stream<Room> get onRoomRemoved => const Stream.empty();
  @override
  Stream<void> get onChildRoomsUpdated => const Stream.empty();
  @override
  Stream<RoomPreview> get onChildRoomPreviewAdded => const Stream.empty();
  @override
  Stream<RoomPreview> get onChildRoomPreviewRemoved => const Stream.empty();
  @override
  Stream<Space> get onChildSpaceAdded => const Stream.empty();
  @override
  Stream<Space> get onChildSpaceRemoved => const Stream.empty();
  @override
  Stream<void> get onChildRoomPreviewsUpdated => const Stream.empty();
  @override
  T? getComponent<T extends SpaceComponent>() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
