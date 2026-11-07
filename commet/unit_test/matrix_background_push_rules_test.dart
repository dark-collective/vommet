// Vommet issue 979: background notification facts read from persisted rows.
import 'dart:convert';

import 'package:commet/client/matrix_background/matrix_background_client.dart';
import 'package:commet/client/matrix_background/matrix_background_room.dart';
import 'package:commet/utils/push_rule_check.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/database.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

const _me = '@me:example.org';
const _sender = '@sender:example.org';
const _creator = '@creator:example.org';
const _roomId = '!room:example.org';
const _otherRoom = '!other:example.org';

class _SdkClient extends Fake implements matrix.Client {}

// Let the SDK independently interpret the same stored state for version cases.
matrix.Room _sdkRoom(MatrixBackgroundRoom background) {
  final room = matrix.Room(id: _roomId, client: _SdkClient());
  for (final raw in [
    ...background.preloadState.map((r) => r.content),
    ...background.nonPreloadState.map((r) => r.content),
  ]) {
    final event = matrix.StrippedStateEvent.fromJson(jsonDecode(raw));
    (room.states[event.type] ??= {})[event.stateKey ?? ''] = event;
  }
  return room;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MatrixSdkDriftDatabase storage;
  late MatrixBackgroundClient client;

  setUp(() async {
    storage = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), 'background push facts');
    client = MatrixBackgroundClient(databaseId: 'background push facts')
      ..database = storage
      ..userId = _me;
  });

  tearDown(() => storage.close());

  Future<void> account(String content,
      {String type = matrix.EventTypes.PushRules}) async {
    await storage.db.into(storage.db.accountData).insertOnConflictUpdate(
        AccountDataCompanion.insert(type: type, content: content));
    client.accountData = await storage.db.select(storage.db.accountData).get();
  }

  Future<void> member(String id, Map<String, Object?> content,
      {String roomId = _roomId}) async {
    await storage.db
        .into(storage.db.roomMembers)
        .insertOnConflictUpdate(RoomMembersCompanion.insert(
            roomId: roomId,
            userId: id,
            content: jsonEncode({
              'type': matrix.EventTypes.RoomMember,
              'sender': id,
              'state_key': id,
              'content': content,
            })));
  }

  Future<void> state(String type, Map<String, Object?> content,
      {bool preload = true,
      String roomId = _roomId,
      String stateKey = '',
      String sender = _creator}) async {
    final raw = jsonEncode({
      'type': type,
      'state_key': stateKey,
      'sender': sender,
      'content': content,
    });
    if (preload) {
      await storage.db.into(storage.db.preloadRoomState).insertOnConflictUpdate(
          PreloadRoomStateCompanion.insert(
              roomId: roomId, type: type, stateKey: stateKey, content: raw));
    } else {
      await storage.db
          .into(storage.db.nonPreloadRoomState)
          .insertOnConflictUpdate(NonPreloadRoomStateCompanion.insert(
              roomId: roomId, type: type, stateKey: stateKey, content: raw));
    }
  }

  Future<MatrixBackgroundRoom> room({String content = '{}'}) async {
    await storage.db.into(storage.db.roomData).insertOnConflictUpdate(
        RoomDataCompanion.insert(roomId: _roomId, content: content));
    client.allRooms = await storage.db.select(storage.db.roomData).get();
    client.preloadRoomStates =
        await storage.db.select(storage.db.preloadRoomState).get();
    client.nonPreloadRoomStates =
        await storage.db.select(storage.db.nonPreloadRoomState).get();
    return client.getRoom(_roomId)! as MatrixBackgroundRoom;
  }

  group('stored push rules', () {
    test('missing rules are unknown even when another account-data row exists',
        () async {
      await account('{}', type: 'm.ignored_user_list');
      expect(client.pushRules, isNull);
    });

    for (final raw in [
      '{',
      'null',
      '[]',
      '{}',
      '{"global":null}',
      '{"global":[]}',
      '{"global":{"override":"invalid"}}',
    ]) {
      test('unreadable rules are unknown: $raw', () async {
        await account(raw);
        expect(client.pushRules, isNull);
      });
    }

    test('a valid stored rule reaches the evaluator with its actions intact',
        () async {
      await account('{}', type: 'm.ignored_user_list');
      await account(jsonEncode({
        'global': {
          'room': [
            {
              'rule_id': _roomId,
              'default': false,
              'enabled': true,
              'actions': ['notify'],
            }
          ],
        },
      }));
      final facts = await (await room()).pushRoomFacts(_sender);
      final rules = client.pushRules;
      expect(rules, isNotNull);
      expect(rules!.room!.single.ruleId, _roomId);
      final verdict = PushRuleCheck.evaluate(
          rules,
          {
            'type': matrix.EventTypes.Message,
            'sender': _sender,
            'content': {'msgtype': 'm.text', 'body': 'hello'},
          },
          facts!);
      expect(verdict, isNotNull);
      expect(verdict!.notify, isTrue);
      expect(verdict.sound, isFalse);
    });
  });

  group('stored summary', () {
    for (final entry in <String, String>{
      'missing summary': '{}',
      'missing count': '{"summary":{}}',
      'zero count': '{"summary":{"m.joined_member_count":0}}',
      'negative count': '{"summary":{"m.joined_member_count":-1}}',
      'string count': '{"summary":{"m.joined_member_count":"4"}}',
      'fractional count': '{"summary":{"m.joined_member_count":4.5}}',
      'malformed room JSON': '{',
    }.entries) {
      test('${entry.key} is unknown, not a zero-member room', () async {
        final background = await room(content: entry.value);
        expect(background.joinedMemberCountOrNull, isNull);
        expect((await background.pushRoomFacts(_sender))!.joinedMemberCount,
            isNull);
      });
    }

    test('a positive count is read from the stored summary', () async {
      final background =
          await room(content: '{"summary":{"m.joined_member_count":4}}');
      expect(background.joinedMemberCountOrNull, 4);
      expect((await background.pushRoomFacts(_sender))!.joinedMemberCount, 4);
    });
  });

  group('own stored member', () {
    test('a missing own row stays unknown; other users and rooms do not count',
        () async {
      await member(
          _sender, {'membership': 'join', 'displayname': 'Someone else'});
      await member(_me, {'membership': 'join', 'displayname': 'Elsewhere'},
          roomId: _otherRoom);
      final facts = await (await room()).pushRoomFacts(_sender);
      expect(facts!.ownDisplayName, isNull);
      expect(facts.ownUserId, _me);
      expect(facts.roomId, _roomId);
    });

    for (final content in <Map<String, Object?>>[
      {'membership': 'join'},
      {'membership': 'join', 'displayname': null},
      {'membership': 'join', 'displayname': ''},
    ]) {
      test('an existing member with no name is a known empty name: $content',
          () async {
        await member(_me, content);
        expect(
            (await (await room()).pushRoomFacts(_sender))!.ownDisplayName, '');
      });
    }

    test('the own name comes from the member row for this room', () async {
      await member(_me, {'membership': 'join', 'displayname': 'Elsewhere'},
          roomId: _otherRoom);
      await member(_me, {'membership': 'join', 'displayname': 'Juniper'});
      await member(_sender, {'membership': 'join', 'displayname': 'Sender'});
      expect((await (await room()).pushRoomFacts(_sender))!.ownDisplayName,
          'Juniper');
    });

    test('without the account user ID all room facts stay unknown', () async {
      client.userId = null;
      expect(await (await room()).pushRoomFacts(_sender), isNull);
    });
  });

  group('stored power and create state', () {
    for (final missing in ['power', 'create', 'both']) {
      test(
          '$missing missing keeps sender level and notification thresholds unknown',
          () async {
        if (missing != 'power' && missing != 'both') {
          await state(matrix.EventTypes.RoomPowerLevels, {'users_default': 10});
        }
        if (missing != 'create' && missing != 'both') {
          await state(matrix.EventTypes.RoomCreate, {'room_version': '11'});
        }
        final facts = await (await room()).pushRoomFacts(_sender);
        expect(facts!.senderPowerLevel, isNull);
        expect(facts.notificationPowerLevels, isNull);
      });
    }

    for (final powersPreloaded in [true, false]) {
      test('both state tables are read (power preloaded: $powersPreloaded)',
          () async {
        await state(
            matrix.EventTypes.RoomPowerLevels,
            {
              'users': {_sender: 75},
              'users_default': 10,
              'notifications': {'room': 60, 'custom': 20},
            },
            preload: powersPreloaded);
        await state(matrix.EventTypes.RoomCreate, {'room_version': '11'},
            preload: !powersPreloaded);
        final facts = await (await room()).pushRoomFacts(_sender);
        expect(facts!.senderPowerLevel, 75);
        expect(facts.notificationPowerLevels, {'room': 60, 'custom': 20});
      });
    }

    test(
        'other rooms and nonempty state keys cannot supply power or create state',
        () async {
      await state(matrix.EventTypes.RoomPowerLevels, {'users_default': 90},
          roomId: _otherRoom);
      await state(matrix.EventTypes.RoomCreate, {'room_version': '12'},
          roomId: _otherRoom);
      await state(matrix.EventTypes.RoomPowerLevels, {'users_default': 90},
          stateKey: 'not-empty');
      await state(matrix.EventTypes.RoomCreate, {'room_version': '12'},
          stateKey: 'not-empty');
      final facts = await (await room()).pushRoomFacts(_sender);
      expect(facts!.senderPowerLevel, isNull);
      expect(facts.notificationPowerLevels, isNull);
    });

    test(
        'users_default supplies an absent user entry; missing notifications is known',
        () async {
      await state(matrix.EventTypes.RoomPowerLevels, {
        'users': {_creator: 100},
        'users_default': 17,
      });
      await state(matrix.EventTypes.RoomCreate, {'room_version': '11'});
      final facts = await (await room()).pushRoomFacts(_sender);
      expect(facts!.senderPowerLevel, 17);
      expect(facts.notificationPowerLevels, isEmpty);
    });

    test('absent users_default is zero even for an old-room creator', () async {
      // The spec defines 0 when a power-level event exists. The SDK has a
      // separate creator fallback quirk, so this case is a spec contract.
      await state(matrix.EventTypes.RoomPowerLevels, {});
      await state(matrix.EventTypes.RoomCreate, {'room_version': '11'},
          sender: _sender);
      final facts = await (await room()).pushRoomFacts(_sender);
      expect(facts!.senderPowerLevel, 0);
      expect(facts.notificationPowerLevels, isEmpty);
    });

    for (final versionCase in <String, int>{
      '11': 17,
      '12': 9007199254740991,
      '13': 9007199254740991,
      'org.example.experimental': 17,
    }.entries) {
      final version = versionCase.key;
      for (final additional in [false, true]) {
        test(
            'version $version creator (additional: $additional) agrees with SDK',
            () async {
          await state(matrix.EventTypes.RoomPowerLevels, {
            'users_default': 17,
            'notifications': {'room': 50},
          });
          await state(
              matrix.EventTypes.RoomCreate,
              {
                'room_version': version,
                if (additional) 'additional_creators': [_sender],
              },
              sender: additional ? _creator : _sender);
          final background = await room();
          final facts = await background.pushRoomFacts(_sender);
          expect(facts!.senderPowerLevel, versionCase.value);
          expect(facts.senderPowerLevel,
              _sdkRoom(background).getPowerLevelByUserId(_sender));
          expect(facts.notificationPowerLevels, {'room': 50});
        });
      }
    }
  });
}
