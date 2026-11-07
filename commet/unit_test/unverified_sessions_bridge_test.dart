// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:commet/client/matrix/unverified_sessions.dart';
import 'package:commet/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 972: the bridge's own sessions don't warn in its portals.

const me = '@me:example.org';
const bot = '@telegrambot:bridge.example';
const ghost = '@telegram_123:bridge.example';
const realMember = '@kit:example.org';
const realOnBridgeServer = '@alice:bridge.example';
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

matrix.Room room({
  Map<String, dynamic>? bridge,
  List<String> members = const [me, bot, ghost],
  bool direct = false,
}) {
  final r = matrix.Room(
    id: roomId,
    client: FakeClient({
      if (direct) members[1]: [roomId]
    }),
    summary: matrix.RoomSummary.fromJson({
      'm.joined_member_count': members.length,
      'm.heroes': members.where((m) => m != me).toList(),
    }),
  );
  if (bridge != null) {
    r.states['m.bridge'] = {
      'b': matrix.StrippedStateEvent(
          type: 'm.bridge', stateKey: 'b', senderId: bot, content: bridge),
    };
  }
  r.states[matrix.EventTypes.RoomMember] = {
    for (final id in members)
      id: matrix.StrippedStateEvent(
        type: matrix.EventTypes.RoomMember,
        stateKey: id,
        senderId: id,
        content: {'membership': 'join'},
      ),
  };
  return r;
}

class _FakeDatabase implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

matrix.DeviceKeys _device(matrix.Client client, String user, String id) =>
    matrix.DeviceKeys.fromJson({
      'user_id': user,
      'device_id': id,
      'algorithms': ['m.olm.v1.curve25519-aes-sha2'],
      'keys': {'curve25519:$id': 'c-$id', 'ed25519:$id': 'e-$id'},
      'signatures': {},
    }, client);

/// The strip's real input: [UnverifiedSessions.shown] of an encrypted
/// bridged DM whose bot, ghost and [extra] sessions are all withheld and
/// in use.
List<String> shownIn({Map<String, dynamic>? bridge, String? extra}) {
  final client = matrix.Client('test', database: _FakeDatabase());
  client.accountData['m.direct'] =
      matrix.BasicEvent(type: 'm.direct', content: {
    bot: [roomId]
  });
  final r = matrix.Room(id: roomId, client: client);
  if (bridge != null) {
    r.states['m.bridge'] = {
      'b': matrix.StrippedStateEvent(
          type: 'm.bridge', stateKey: 'b', senderId: bot, content: bridge),
    };
  }
  r.states[matrix.EventTypes.Encryption] = {
    '': matrix.StrippedStateEvent(
        type: matrix.EventTypes.Encryption,
        stateKey: '',
        senderId: bot,
        content: {'algorithm': 'm.megolm.v1.aes-sha2'}),
  };
  r.states[matrix.EventTypes.RoomMember] = {
    for (final id in [bot, ghost, if (extra != null) extra])
      id: matrix.StrippedStateEvent(
        type: matrix.EventTypes.RoomMember,
        stateKey: id,
        senderId: id,
        content: {'membership': 'join'},
      ),
  };
  final devices = [
    for (final id in [bot, ghost, if (extra != null) extra])
      _device(client, id, 'D${id.hashCode.abs()}'),
  ];
  for (final d in devices) {
    UnverifiedSessions.noteActivity(client, d.userId, d.deviceId!,
        DateTime.now().subtract(const Duration(minutes: 3)),
        asked: true);
  }
  final state = UnverifiedSessions.forTesting(r);
  expect(state.room.isDirectChat, isTrue);
  state.withheld.value = devices;
  return state.shown.map((d) => d.userId).toList();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    UnverifiedSessions.reloadActivity();
  });

  test('the strip of a bridged DM skips the bridge, keeps real members', () {
    // Declared portal: the bot and its ghost don't warn, a real member on
    // another server who looks like a bridge bot still does.
    const outsider = '@discordbot:other.example';
    expect(shownIn(bridge: {'bridgebot': bot}, extra: outsider), [outsider]);
    expect(
        shownIn(bridge: {'bridgebot': bot}, extra: realMember), [realMember]);
    // Undeclared DM (Vommet issue 971 fallback): same.
    expect(shownIn(), isEmpty);
  });

  test('in a declared portal a known bot id needs a ghost on its server', () {
    const sameServerBot = '@discordbot:bridge.example';
    const elsewhere = '@whatsappbot:wa.example';
    final noGhost = room(
        bridge: {'bridgebot': bot},
        members: [me, bot, sameServerBot, elsewhere]);
    expect(UnverifiedSessions.isBridgeOwned(noGhost, bot), isTrue);
    expect(UnverifiedSessions.isBridgeOwned(noGhost, sameServerBot), isFalse);
    expect(UnverifiedSessions.isBridgeOwned(noGhost, elsewhere), isFalse);
    final withGhost = room(
        bridge: {'bridgebot': bot}, members: [me, bot, ghost, sameServerBot]);
    expect(UnverifiedSessions.isBridgeOwned(withGhost, sameServerBot), isTrue);
  });

  test('a declared portal skips its bot and ghosts', () {
    final r = room(
        bridge: {'bridgebot': bot},
        members: [me, bot, ghost, realMember, realOnBridgeServer]);
    expect(UnverifiedSessions.isBridgeOwned(r, bot), isTrue);
    expect(UnverifiedSessions.isBridgeOwned(r, ghost), isTrue);
    // Real Matrix members keep the warning, even on the bridge's server.
    expect(UnverifiedSessions.isBridgeOwned(r, realMember), isFalse);
    expect(UnverifiedSessions.isBridgeOwned(r, realOnBridgeServer), isFalse);
    expect(UnverifiedSessions.isBridgeOwned(r, me), isFalse);
  });

  test('a ghost-like ID on another server is not the bridge', () {
    const stranger = '@telegram_9:other.example';
    final r = room(bridge: {'bridgebot': bot}, members: [me, bot, stranger]);
    expect(UnverifiedSessions.isBridgeOwned(r, stranger), isFalse);
  });

  test('a portal without a bridgebot still skips a known bot id', () {
    final r = room(
        bridge: {'network': 'telegram'}, members: [me, bot, ghost, realMember]);
    // The known bot shares its server with the portal's ghost.
    expect(UnverifiedSessions.isBridgeOwned(r, bot), isTrue);
    expect(UnverifiedSessions.isBridgeOwned(r, ghost), isTrue);
    expect(UnverifiedSessions.isBridgeOwned(r, realMember), isFalse);
  });

  test('a known bot id on another server keeps the warning', () {
    const outsider = '@discordbot:other.example';
    final declared = room(
        bridge: {'bridgebot': bot},
        members: [me, bot, ghost, outsider, realMember]);
    expect(UnverifiedSessions.isBridgeOwned(declared, outsider), isFalse);
    // Without a declared bot, a known bot id needs a ghost on its server.
    final undeclared =
        room(bridge: {'network': 'telegram'}, members: [me, outsider, ghost]);
    expect(UnverifiedSessions.isBridgeOwned(undeclared, outsider), isFalse);
    expect(UnverifiedSessions.isBridgeOwned(undeclared, ghost), isFalse);
    // A room that is not a portal never matches a known bot id.
    final plain = room(members: [me, outsider, realMember]);
    expect(UnverifiedSessions.isBridgeOwned(plain, outsider), isFalse);
  });

  test('an undeclared DM with the bot on another server keeps warning', () {
    const remoteGhost = '@telegram_123:other.example';
    final r = room(direct: true, members: [me, bot, remoteGhost]);
    expect(UnverifiedSessions.isBridgeOwned(r, bot), isFalse);
    expect(UnverifiedSessions.isBridgeOwned(r, remoteGhost), isFalse);
  });

  test('an undeclared DM uses the known bot rule', () {
    final r = room(direct: true);
    expect(UnverifiedSessions.isBridgeOwned(r, bot), isTrue);
    expect(UnverifiedSessions.isBridgeOwned(r, ghost), isTrue);
  });

  test('rooms that are not portals keep every warning', () {
    // Not a DM, no bridge state: nothing is guessed.
    final group = room();
    expect(UnverifiedSessions.isBridgeOwned(group, bot), isFalse);
    expect(UnverifiedSessions.isBridgeOwned(group, ghost), isFalse);
    // An empty (redacted) bridge event doesn't make a portal.
    final redacted = room(bridge: {}, members: [me, bot, ghost, realMember]);
    expect(UnverifiedSessions.isBridgeOwned(redacted, bot), isFalse);
    expect(UnverifiedSessions.isBridgeOwned(redacted, ghost), isFalse);
  });
}
