import 'package:commet/client/matrix/components/direct_messages/matrix_direct_messages_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _person = '@telegram_123:example.org';
const _bot = '@telegrambot:example.org';
const _portalId = '!portal:example.org';
const _newRoomId = '!new:example.org';

class _Database extends Fake implements matrix.DatabaseApi {}

class _Sdk extends matrix.Client {
  _Sdk() : super('dm-reuse', database: _Database());
  final calls = <String>[];

  @override
  Map<String, List<String>> get directChats => {
        _bot: [_portalId]
      };

  @override
  Future<String> startDirectChat(String mxid,
      {bool? enableEncryption,
      List<matrix.StateEvent>? initialState,
      bool waitForSync = true,
      Map<String, dynamic>? powerLevelContentOverride,
      matrix.CreateRoomPreset? preset =
          matrix.CreateRoomPreset.trustedPrivateChat,
      bool skipExistingChat = false}) async {
    calls.add(mxid);
    return _newRoomId;
  }
}

class _Room extends Fake implements MatrixRoom {
  _Room(this.matrixRoom);
  @override
  final matrix.Room matrixRoom;
}

class _Client extends Fake implements MatrixClient {
  _Client(this.sdk, this.newRoom);
  final _Sdk sdk;
  final Room newRoom;
  @override
  final rooms = NotifyingList<Room>.empty(growable: true);
  @override
  matrix.Client getMatrixClient() => sdk;
  @override
  Room? getRoom(String identifier) => identifier == _newRoomId ? newRoom : null;
}

class _DirectMessages extends MatrixDirectMessagesComponent {
  _DirectMessages(super.client, this.existing);
  final List<Room> existing;
  @override
  List<Room> directMessagesWith(String userId) =>
      userId == _person ? existing : const [];
}

void main() {
  late _Sdk sdk;
  late _Room newRoom;
  late _Client client;

  setUp(() {
    sdk = _Sdk();
    newRoom = _Room(matrix.Room(id: _newRoomId, client: sdk));
    client = _Client(sdk, newRoom);
  });

  tearDown(() async {
    await sdk.onSync.close();
    client.rooms.close();
  });

  test('reuse the joined portal even though the SDK indexes it under its bot',
      () async {
    final portal = matrix.Room(id: _portalId, client: sdk);
    final existing = _Room(portal);
    expect(portal.directChatMatrixID, _bot);
    final component = _DirectMessages(client, [existing]);
    expect(await component.createDirectMessage(_person), same(existing));
    expect(sdk.calls, isEmpty);
  });

  test('without a known joined DM, create it through the SDK', () async {
    final component = _DirectMessages(client, []);
    expect(await component.createDirectMessage(_person), same(newRoom));
    expect(sdk.calls, [_person]);
  });

  for (final membership in [
    matrix.Membership.invite,
    matrix.Membership.leave
  ]) {
    test('$membership keeps the SDK acceptance or creation flow', () async {
      final existing = _Room(
          matrix.Room(id: _portalId, client: sdk, membership: membership));
      final component = _DirectMessages(client, [existing]);
      expect(await component.createDirectMessage(_person), same(newRoom));
      expect(sdk.calls, [_person]);
    });
  }
}
