// Made-up rooms for testing the real RoomPanel / chatEntryOf bindings.
import 'dart:async';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TopicClient extends Fake implements Client {
  final fixtureRooms = <TopicRoom>[];
  late final direct = _Direct(this);
  final presence = _Presence();
  @override
  String get identifier => 'topic-fixture';
  // The shared unread index listens to these; the fixture never syncs.
  @override
  NotifyingList<Room> get rooms =>
      NotifyingList<Room>.empty(growable: true)..addAll(fixtureRooms);
  @override
  Stream<void> get onSync => const Stream.empty();
  @override
  Stream<Room> get onRoomAdded => const Stream.empty();
  @override
  Stream<Room> get onRoomRemoved => const Stream.empty();
  @override
  Profile get self => _Member('@me:example.org');
  @override
  T? getComponent<T extends Component>() => T == DirectMessagesComponent
      ? direct as T
      : T == UserPresenceComponent
          ? presence as T
          : null;
}

class _Direct extends Fake implements DirectMessagesComponent {
  _Direct(this.client);
  @override
  final TopicClient client;
  @override
  NotifyingList<Room> get directMessageRooms => client.rooms;
  @override
  bool isRoomDirectMessage(Room room) => true;
  @override
  String getDirectMessagePartnerId(Room room) =>
      '@${room.identifier}:example.org';
  @override
  List<Room> directMessagesWith(String id) => client.fixtureRooms
      .where((r) => getDirectMessagePartnerId(r) == id)
      .toList();
}

class _Presence extends Fake implements UserPresenceComponent {
  @override
  Stream<(String, UserPresence)> get onPresenceChanged => const Stream.empty();
  @override
  Future<UserPresence> getUserPresence(String userId) async =>
      UserPresence(UserPresenceStatus.unknown);
}

class _Member extends Fake implements Member, Profile {
  _Member(this.identifier);
  @override
  final String identifier;
  @override
  String get displayName => 'You';
  @override
  Color get defaultColor => Colors.blue;
  @override
  ImageProvider? get avatar => null;
}

class _Permissions extends Permissions {}

class _Message extends Fake implements TimelineEvent {
  _Message(this.plainTextBody, this.originServerTs, this.senderId);
  @override
  final String plainTextBody;
  @override
  final DateTime originServerTs;
  @override
  final String senderId;
}

class TopicRoom extends Fake implements Room {
  TopicRoom(this.client,
      {required this.identifier,
      required this.displayName,
      required this.at,
      this.topic,
      String? body = 'Want to play after dinner?',
      bool sentBySelf = true,
      this.count = 0,
      this.mentions = 0,
      this.color = Colors.teal,
      this.muted = false}) {
    if (body != null)
      lastMessage = _Message(body, at,
          sentBySelf ? '@me:example.org' : '@$identifier:example.org');
    client.fixtureRooms.add(this);
  }
  @override
  final TopicClient client;
  @override
  final String identifier;
  @override
  final String displayName;
  final DateTime at;
  final int count, mentions;
  final Color color;
  final bool muted;
  @override
  String? topic;
  final updates = StreamController<void>.broadcast();
  @override
  Stream<void> get onUpdate => updates.stream;
  @override
  TimelineEvent? lastMessage;
  @override
  TimelineEvent? get lastEvent => lastMessage;
  @override
  DateTime get lastEventTimestamp => at;
  @override
  String get localId => '${client.identifier}:$identifier';
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => color;
  @override
  int get notificationCount => count;
  @override
  int get highlightedNotificationCount => mentions;
  @override
  int get displayHighlightedNotificationCount => mentions;
  @override
  int get badgeCount => mentions;
  @override
  bool get badgeNoisy => true;
  @override
  bool get messagesAreNoisy => true;
  @override
  PushRule get pushRule => muted ? PushRule.dontNotify : PushRule.notify;
  @override
  bool get isFavorite => false;
  @override
  bool get isSpecialRoomType => false;
  @override
  bool get isE2EE => true;
  @override
  Permissions get permissions => _Permissions();
  @override
  T? getComponent<T extends RoomComponent>() => null;
  @override
  Member getMemberOrFallback(String id) => _Member(id);
  @override
  Color getColorOfUser(String id) => color;
  void updateTopic(String? value) {
    topic = value;
    updates.add(null);
  }
}
