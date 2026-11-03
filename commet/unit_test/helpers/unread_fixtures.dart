import 'package:commet/client/components/room_component.dart';
import 'dart:async';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/unread_index.dart';
import 'package:flutter_test/flutter_test.dart';

class UnreadClient extends Fake implements Client {
  UnreadClient([this.identifier = 'account']);
  @override
  final String identifier;
  @override
  final rooms = NotifyingList<Room>.empty(growable: true);
  final sync = StreamController<void>.broadcast();
  @override
  Stream<void> get onSync => sync.stream;
  @override
  Stream<Room> get onRoomAdded => rooms.onAdd;
  @override
  Stream<Room> get onRoomRemoved => rooms.onRemove;
  final dms = UnreadDms();
  @override
  T? getComponent<T extends Component>() => dms is T ? dms as T : null;
  @override
  List<Space> get spaces => const [];
  Future<void> close() async {
    await UnreadIndex.of(this).dispose();
    await sync.close();
  }
}

class UnreadDms extends Fake implements DirectMessagesComponent {
  final groups = <String, List<Room>>{};
  @override
  final directMessageRooms = NotifyingList<Room>.empty(growable: true);
  @override
  String? getDirectMessagePartnerId(Room room) =>
      groups.entries.where((e) => e.value.contains(room)).firstOrNull?.key;
  @override
  bool isRoomDirectMessage(Room room) =>
      getDirectMessagePartnerId(room) != null;
  @override
  List<Room> directMessagesWith(String id) => groups[id] ?? const [];
}

class UnreadRoom extends Room {
  UnreadRoom(this.client, this.identifier,
      {this.notificationCount = 0,
      this.highlightedNotificationCount = 0,
      this.pushRule = PushRule.notify,
      this.messagesAreNoisy = false,
      this.isFavorite = false}) {
    client.rooms.add(this);
  }
  @override
  final UnreadClient client;
  @override
  final String identifier;
  @override
  String get localId => '${client.identifier}/$identifier';
  @override
  int notificationCount;
  @override
  int highlightedNotificationCount;
  @override
  PushRule pushRule;
  @override
  bool messagesAreNoisy;
  @override
  bool isFavorite;
  @override
  Stream<void> get onUpdate => updates.stream;
  final updates = StreamController<void>.broadcast();
  @override
  T? getComponent<T extends RoomComponent>() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
