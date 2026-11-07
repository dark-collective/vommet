// Vommet issue 1223: loaded SDK state, with fakes only at account/wrapper boundaries.
import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

class AutocompleteClient implements MatrixClient {
  AutocompleteClient(this.identifier);
  @override
  final String identifier;
  @override
  final rooms = NotifyingList<Room>.empty(growable: true);
  @override
  final spaces = <Space>[];
  @override
  Room? getRoom(String id) {
    for (final room in rooms) {
      if (room.identifier == id) return room;
    }
    return null;
  }

  @override
  (String, List<String>?)? parseAddressToIdAndVia(String address) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SdkClient extends Fake implements matrix.Client {}

matrix.Room loadedRoom(String id,
    {String? alias,
    List<dynamic> alternatives = const [],
    matrix.Membership membership = matrix.Membership.join}) {
  final room =
      matrix.Room(id: id, client: _SdkClient(), membership: membership);
  setLoadedAliases(room, {'alias': alias, 'alt_aliases': alternatives});
  return room;
}

void setLoadedAliases(matrix.Room room, Map<String, dynamic>? content) {
  if (content == null) {
    room.states.remove('m.room.canonical_alias');
    return;
  }
  room.states['m.room.canonical_alias'] = {
    '': matrix.StrippedStateEvent(
      type: 'm.room.canonical_alias',
      stateKey: '',
      senderId: '@me:example.org',
      content: content,
    ),
  };
}

class AutocompleteRoom extends Fake implements MatrixRoom {
  AutocompleteRoom(this.client, this.identifier, this.displayName,
      {String? alias,
      List<dynamic> alternatives = const [],
      matrix.Membership membership = matrix.Membership.join})
      : matrixRoom = loadedRoom(identifier,
            alias: alias, alternatives: alternatives, membership: membership);
  @override
  final AutocompleteClient client;
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  final matrix.Room matrixRoom;
  @override
  T? getComponent<T extends RoomComponent>() => null;
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => Colors.blue;
  @override
  IconData get icon => Icons.tag;
}

class AutocompleteSpace extends Fake implements MatrixSpace {
  AutocompleteSpace(this.client, this.identifier, this.displayName,
      {String? alias,
      List<dynamic> alternatives = const [],
      matrix.Membership membership = matrix.Membership.join})
      : matrixRoom = loadedRoom(identifier,
            alias: alias, alternatives: alternatives, membership: membership);
  @override
  final AutocompleteClient client;
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  final matrix.Room matrixRoom;
  @override
  final rooms = <Room>[];
  @override
  final subspaces = <Space>[];
  @override
  bool containsRoom(String id) => rooms.any((r) => r.identifier == id);
}

class AutocompleteSetup {
  final client = AutocompleteClient('account-a');
  final otherAccount = AutocompleteClient('account-b');
  late final dm = AutocompleteRoom(client, '!dm:example.org', 'Alex');
  late final current = AutocompleteRoom(
      client, '!current:example.org', 'General',
      alias: '#general:example.org');
  late final sibling = AutocompleteRoom(
      client, '!sibling:example.org', 'Garden notes',
      alias: '#notes:example.org');
  late final outside = AutocompleteRoom(
      client, '!outside:example.org', 'Garden',
      alias: '#garden:example.org',
      alternatives: [
        '#flowers:example.org',
        '#seasonal-announcements:example.org'
      ]);
  late final parent = AutocompleteSpace(
      client, '!parent:example.org', 'Garden community',
      alias: '#community:example.org');
  AutocompleteSetup() {
    client.rooms.addAll([dm, current, outside, sibling]);
    parent.rooms.addAll([current, sibling]);
    client.spaces.add(parent);
  }
}
