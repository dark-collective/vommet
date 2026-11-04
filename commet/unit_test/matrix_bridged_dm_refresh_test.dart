// Vommet issue 971: a sync that switches the known bot fallback on or off
// refreshes who a DM is with, through the component's real sync path.
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/matrix/components/direct_messages/matrix_direct_messages_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/unread_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _me = '@me:example.org';
const _bot = '@telegrambot:example.org';
const _person = '@telegram_123:example.org';
const _other = '@kit:example.org';
const _roomId = '!portal:example.org';

class _Database extends Fake implements matrix.DatabaseApi {}

class _Sdk extends matrix.Client {
  _Sdk() : super('dm-refresh', database: _Database());

  @override
  String? get userID => _me;

  @override
  Map<String, List<String>> get directChats => {
        _bot: [_roomId]
      };
}

class _Room extends Fake implements MatrixRoom {
  _Room(this.matrixRoom, this.client);
  @override
  final matrix.Room matrixRoom;
  @override
  final Client client;
  @override
  String get identifier => matrixRoom.id;
  @override
  DateTime get lastEventTimestamp => DateTime(2026, 11, 3);
  @override
  RoomReplacement get replacement => _NoReplacement();
}

class _NoReplacement extends Fake implements RoomReplacement {
  @override
  RoomTombstone? get tombstone => null;
  @override
  RoomPredecessor? get predecessor => null;
}

class _Client extends Fake implements MatrixClient {
  _Client(this.sdk);
  final _Sdk sdk;
  @override
  final rooms = NotifyingList<Room>.empty(growable: true);
  @override
  matrix.Client getMatrixClient() => sdk;
  @override
  matrix.Client get matrixClient => sdk;
  @override
  Stream<void> get onSync => const Stream.empty();
  @override
  Stream<Room> get onRoomAdded => const Stream.empty();
  @override
  Stream<Room> get onRoomRemoved => const Stream.empty();
  @override
  T? getComponent<T extends Component>() => null;
  @override
  Room? getRoom(String identifier) => null;
}

void setMembers(matrix.Room room, Map<String, String> members) {
  room.summary = matrix.RoomSummary.fromJson({
    'm.joined_member_count':
        members.values.where((m) => m == 'join').length + 1,
    'm.heroes': [
      for (final e in members.entries)
        if (e.value == 'join') e.key
    ],
  });
  room.states[matrix.EventTypes.RoomMember] = {
    for (final id in [_me, ...members.keys])
      id: matrix.StrippedStateEvent(
        type: matrix.EventTypes.RoomMember,
        stateKey: id,
        senderId: id,
        content: {'membership': members[id] ?? 'join'},
      ),
  };
}

matrix.SyncUpdate memberSync(String id, String membership) =>
    matrix.SyncUpdate.fromJson({
      'next_batch': 'b',
      'rooms': {
        'join': {
          _roomId: {
            'timeline': {
              'events': [
                {
                  'type': 'm.room.member',
                  'state_key': id,
                  'sender': id,
                  'event_id': '\$$membership',
                  'origin_server_ts': 0,
                  'content': {'membership': membership},
                }
              ]
            }
          }
        }
      }
    });

void main() {
  late _Sdk sdk;
  late _Client client;
  late matrix.Room portal;
  late MatrixDirectMessagesComponent component;

  setUp(() async {
    sdk = _Sdk();
    client = _Client(sdk);
    // The fixture never syncs unread state; a closed index answers "read".
    UnreadIndex.of(client);
    await UnreadIndex.disposeFor(client);
    portal = matrix.Room(id: _roomId, client: sdk);
    setMembers(portal, {_bot: 'join', _person: 'join'});
    component = MatrixDirectMessagesComponent(client);
    client.rooms.add(_Room(portal, client));
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    await sdk.onSync.close();
    client.rooms.close();
  });

  test('an undeclared portal is grouped under its person', () {
    expect(component.directMessagesWith(_person).map((r) => r.identifier),
        [_roomId]);
    expect(component.directMessagesWith(_bot), isEmpty);
  });

  test('the ghost leaving moves the DM back to the bot', () {
    expect(component.directMessagesWith(_person), isNotEmpty);
    // The SDK applies the sync to the room before onSync fires.
    setMembers(portal, {_bot: 'join', _person: 'leave'});
    component.onMatrixSync(memberSync(_person, 'leave'));
    expect(component.directMessagesWith(_person), isEmpty);
    expect(
        component.directMessagesWith(_bot).map((r) => r.identifier), [_roomId]);
  });

  test('a third account joining stops the fallback', () {
    expect(component.directMessagesWith(_person), isNotEmpty);
    setMembers(portal, {_bot: 'join', _person: 'join', _other: 'join'});
    component.onMatrixSync(memberSync(_other, 'join'));
    expect(component.directMessagesWith(_person), isEmpty);
  });
}
