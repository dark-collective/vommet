import 'package:commet/client/matrix/components/direct_messages/matrix_bridged_dm.dart';
import 'package:commet/client/matrix/components/direct_messages/matrix_dm_shape.dart';
import 'package:commet/utils/dm_shape.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const me = '@me:example.org';
const bot = '@telegrambot:example.org';
const person = '@telegram_123:example.org';
const other = '@kit:example.org';
const roomId = '!portal:example.org';

class FakeClient extends Fake implements matrix.Client {
  FakeClient(this.chats);
  final Map<String, List<String>> chats;
  @override
  String? get userID => me;
  @override
  bool get formatLocalpart => true;
  @override
  bool get mxidLocalPartFallback => true;
  @override
  Map<String, List<String>> get directChats => chats;
}

matrix.Room portal({
  String type = 'm.bridge',
  Map<String, dynamic>? bridge,
  List<String> direct = const [bot],
  List<String> active = const [me, bot, person],
  List<String>? heroes,
  int? count = 3,
}) {
  final room = matrix.Room(
    id: roomId,
    client: FakeClient({
      for (final id in direct) id: [roomId],
    }),
    summary: matrix.RoomSummary.fromJson({
      if (count != null) 'm.joined_member_count': count,
      'm.heroes': heroes ?? [bot, person],
    }),
  );
  room.states[type] = {
    'bridge': matrix.StrippedStateEvent(
      type: type,
      stateKey: 'bridge',
      senderId: bot,
      content: bridge ?? {'bridgebot': bot},
    ),
  };
  room.states[matrix.EventTypes.RoomMember] = {
    for (final id in active)
      id: matrix.StrippedStateEvent(
        type: matrix.EventTypes.RoomMember,
        stateKey: id,
        senderId: id,
        content: {
          'membership': 'join',
          'displayname':
              {bot: 'Bridge bot', person: 'Juniper', other: 'Kit'}[id] ?? 'Me',
          'avatar_url': 'mxc://example.org/${id == person ? 'person' : 'bot'}',
        },
      ),
  };
  return room;
}

void main() {
  for (final type in ['m.bridge', 'uk.half-shot.bridge']) {
    group(type, () {
      test('a bot-listed portal resolves to its remote person', () {
        final room = portal(type: type);
        expect(room.directChatMatrixID, bot); // Existing SDK behavior.
        expect(MatrixBridgedDm.partner(room), person);
        expect(MatrixDmShape.of(room).kind, DmShapeKind.person);
        expect(MatrixDmShape.of(room).partnerId, person);
        expect(MatrixDmShape.groupName(room), 'Juniper');
        expect(
          MatrixBridgedDm.avatar(room),
          Uri.parse('mxc://example.org/person'),
        );
      });

      test('a correct m.direct entry keeps its partner', () {
        expect(
          MatrixBridgedDm.partner(portal(type: type, direct: [person])),
          person,
        );
        expect(
          MatrixBridgedDm.partner(portal(type: type, direct: [bot, person])),
          person,
        );
      });
    });
  }

  test('personal nicknames win over explicit portal names', () {
    final room = portal();
    room.states[matrix.EventTypes.RoomName] = {
      '': matrix.StrippedStateEvent(
        type: matrix.EventTypes.RoomName,
        senderId: me,
        stateKey: '',
        content: {'name': 'My portal'},
      ),
    };
    expect(MatrixBridgedDm.displayName(room, person), 'My portal');
    expect(MatrixBridgedDm.displayName(room, person, petName: 'My friend'),
        'My friend');
    room.states.remove(matrix.EventTypes.RoomName);
    expect(MatrixBridgedDm.displayName(room, person), 'Juniper');
    expect(MatrixBridgedDm.displayName(room, person, petName: 'My friend'),
        'My friend');
  });

  test('an explicit room avatar is preserved', () {
    final room = portal();
    room.states[matrix.EventTypes.RoomAvatar] = {
      '': matrix.StrippedStateEvent(
        type: matrix.EventTypes.RoomAvatar,
        senderId: me,
        stateKey: '',
        content: {'url': 'mxc://example.org/custom'},
      ),
    };
    expect(MatrixBridgedDm.avatar(room), Uri.parse('mxc://example.org/custom'));
  });

  test('lazy-loaded bot hero is excluded from the summary count', () {
    final room = portal(active: [me, person]);
    expect(MatrixDmShape.of(room).kind, DmShapeKind.person);
    expect(MatrixBridgedDm.activeCount(room, {bot}), 2);
  });

  test('an invited bridgebot also does not turn a DM into a group', () {
    final room = portal(count: 2);
    room.summary = matrix.RoomSummary.fromJson({
      'm.joined_member_count': 2,
      'm.invited_member_count': 1,
      'm.heroes': [bot, person],
    });
    room.states[matrix.EventTypes.RoomMember]![bot]!.content['membership'] =
        'invite';
    expect(MatrixDmShape.of(room).kind, DmShapeKind.person);
  });

  test('a third real member still creates a group, without the bot name', () {
    final room = portal(
      active: [me, bot, person, other],
      heroes: [bot, person, other],
      count: 4,
    );
    expect(MatrixBridgedDm.partner(room), isNull);
    expect(MatrixDmShape.of(room).kind, DmShapeKind.group);
    expect(MatrixDmShape.groupName(room), 'Juniper and Kit');
  });

  test('unknown summary counts use known real members', () {
    expect(MatrixDmShape.of(portal(count: null)).kind, DmShapeKind.person);
    expect(
      MatrixDmShape.of(
        portal(active: [me, bot, person, other], count: null),
      ).kind,
      DmShapeKind.group,
    );
  });

  test('departed bot is not subtracted from an active member count', () {
    final room = portal(active: [me, person, other], count: 3);
    room.states[matrix.EventTypes.RoomMember]![bot] = matrix.StrippedStateEvent(
      type: matrix.EventTypes.RoomMember,
      senderId: bot,
      stateKey: bot,
      content: {'membership': 'leave'},
    );
    expect(MatrixBridgedDm.activeCount(room, {bot}), 3);
    expect(MatrixDmShape.of(room).kind, DmShapeKind.group);
  });

  test('a real partner who left remains the DM partner', () {
    final room = portal(direct: [person], active: [me, bot], count: 2);
    room.states[matrix.EventTypes.RoomMember]![person] =
        matrix.StrippedStateEvent(
      type: matrix.EventTypes.RoomMember,
      senderId: person,
      stateKey: person,
      content: {'membership': 'leave', 'displayname': 'Juniper'},
    );
    expect(MatrixDmShape.of(room).kind, DmShapeKind.leftPartner);
    expect(MatrixDmShape.of(room).partnerId, person);
  });

  test('a room outside m.direct is not converted into a DM', () {
    final room = portal(direct: []);
    expect(MatrixBridgedDm.partner(room), isNull);
    expect(MatrixDmShape.of(room), DmShape.room);
  });

  test('ordinary DMs and bot-like user IDs are not guessed away', () {
    for (final content in <Map<String, dynamic>>[
      {},
      {'bridgebot': ''},
      {'bridgebot': 123},
      {'bridgebot': me},
      {'bridgebot': 'not an mxid'},
    ]) {
      final room = portal(bridge: content);
      expect(MatrixBridgedDm.partner(room), bot);
      expect(MatrixBridgedDm.bots(room), isEmpty);
    }
  });

  test('valid IDs containing s are accepted, whitespace IDs are rejected', () {
    for (final id in ['@signalbot:server.example', '@steam:example.org']) {
      expect(MatrixBridgedDm.bots(portal(bridge: {'bridgebot': id})), {id});
    }
    for (final id in [
      '@ bot:example.org',
      '@bot:bad server',
      '@bot:example.org '
    ]) {
      expect(MatrixBridgedDm.bots(portal(bridge: {'bridgebot': id})), isEmpty);
    }
  });

  test('bridge declarations changing do not leave a cached partner', () {
    final room = portal();
    expect(MatrixBridgedDm.partner(room), person);
    room.states['m.bridge']!['bridge']!.content.clear();
    expect(MatrixBridgedDm.partner(room), bot);
    room.states['m.bridge']!['bridge']!.content['bridgebot'] = bot;
    expect(MatrixBridgedDm.partner(room), person);
  });

  test('ordinary two-person DMs retain their partner and avatar', () {
    final room = portal(direct: [person], active: [me, person], count: 2);
    room.states.remove('m.bridge');
    expect(MatrixBridgedDm.partner(room), person);
    expect(MatrixDmShape.of(room).kind, DmShapeKind.person);
    expect(MatrixBridgedDm.avatar(room), Uri.parse('mxc://example.org/person'));
  });

  test('ordinary DMs keep the SDK name fallback for unnamed members', () {
    final room = portal(direct: [person], active: [me, person], count: 2);
    room.states.remove('m.bridge');
    room.states[matrix.EventTypes.RoomMember]![person]!.content
        .remove('displayname');
    room.states[matrix.EventTypes.RoomName] = {
      '': matrix.StrippedStateEvent(
        type: matrix.EventTypes.RoomName,
        senderId: me,
        stateKey: '',
        content: {'name': 'Named chat'},
      ),
    };
    expect(MatrixBridgedDm.displayName(room, person), 'Named chat');
  });

  test('a bot-only DM does not guess another partner or reuse its avatar', () {
    final room = portal(active: [me, bot], heroes: [bot], count: 2);
    expect(MatrixBridgedDm.partner(room), isNull);
    expect(MatrixBridgedDm.avatar(room), isNull);
  });

  test('both bridge state types and multiple state keys are combined', () {
    final room = portal();
    room.states['uk.half-shot.bridge'] = {
      'second': matrix.StrippedStateEvent(
        type: 'uk.half-shot.bridge',
        stateKey: 'second',
        senderId: other,
        content: {'bridgebot': other},
      ),
    };
    expect(MatrixBridgedDm.bots(room), {bot, other});
  });
}
