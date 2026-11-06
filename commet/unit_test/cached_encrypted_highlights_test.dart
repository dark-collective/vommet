import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/components/message_filters/message_filters.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/unread_index.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'roomlist_fixture.dart';

const _roomId = '!cached:example.com';
matrix.BasicEvent _rules(String word) =>
    matrix.BasicEvent(type: matrix.EventTypes.PushRules, content: {
      'global': {
        'override': [
          {
            'rule_id': 'test-mention',
            'default': false,
            'enabled': true,
            'conditions': [
              {'kind': 'event_match', 'key': 'content.body', 'pattern': word}
            ],
            'actions': [
              'notify',
              {'set_tweak': 'highlight', 'value': true}
            ],
          }
        ]
      }
    });
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MatrixClient client;
  var sequence = 0;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    sequence = 0;
    client = await signedInClient('cached-highlights');
    await sync(client, join: {
      _roomId: matrix.JoinedRoomUpdate(state: [
        ...roomState(_roomId),
        stateEvent(
            matrix.EventTypes.Encryption, {'algorithm': 'm.megolm.v1.aes-sha2'})
      ])
    });
    client.matrixClient.accountData[matrix.EventTypes.PushRules] =
        _rules('ping');
  });
  tearDown(() async {
    await UnreadIndex.disposeFor(client);
    for (final room in client.rooms) await room.close();
    await client.matrixClient.dispose(closeDatabase: true);
  });
  matrix.Room sdk() => client.matrixClient.getRoomById(_roomId)!;
  matrix.Event message(String id, String body,
      {String? root, String? edit, String? sender}) {
    final content = <String, dynamic>{
      'msgtype': 'm.text',
      'body': body,
      if (root != null)
        'm.relates_to': {'rel_type': 'm.thread', 'event_id': root},
      if (edit != null) ...{
        'm.relates_to': {'rel_type': 'm.replace', 'event_id': edit},
        'm.new_content': {'msgtype': 'm.text', 'body': body}
      },
    };
    final time = DateTime.now().add(Duration(milliseconds: sequence++));
    return matrix.Event(
        type: matrix.EventTypes.Message,
        eventId: id,
        senderId: sender ?? '@them:example.com',
        originServerTs: time,
        room: sdk(),
        content: content,
        originalSource: matrix.MatrixEvent(
            type: matrix.EventTypes.Encrypted,
            eventId: id,
            senderId: sender ?? '@them:example.com',
            originServerTs: time,
            content: {
              'algorithm': 'm.megolm.v1.aes-sha2',
              'ciphertext': 'fixture'
            }));
  }

  Future<void> send(List<matrix.MatrixEvent> events) => sync(client, join: {
        _roomId: matrix.JoinedRoomUpdate(
            timeline: matrix.TimelineUpdate(events: events))
      });
  void receipt(String id, {String? thread}) {
    sdk().receiptState = matrix.LatestReceiptState.fromJson({
      thread == null
          ? 'global'
          : thread == 'main'
              ? 'main'
              : 'thread': thread == null || thread == 'main'
          ? {
              'public': {'e': id, 'ts': 1}
            }
          : {
              thread: {
                'public': {'e': id, 'ts': 1}
              }
            }
    });
  }

  Future<void> readBaseline() async {
    await send([message(r'$read', 'read message')]);
    receipt(r'$read');
  }

  Future<MatrixRoom> recreate(int expected) async {
    final original = client.getRoom(_roomId) as MatrixRoom;
    await original.close();
    client.rooms.remove(original);
    final recreated = MatrixRoom(client, sdk(), client.matrixClient);
    // Real MatrixClient reloads remove/add in the same synchronous turn.
    client.rooms.add(recreated);
    final index = UnreadIndex.of(client);
    if (expected > 0) {
      await index.onChanged
          .firstWhere((_) => recreated.highlightedNotificationCount == expected)
          .timeout(const Duration(seconds: 5));
    } else {
      await index.onChanged.first.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(recreated.highlightedNotificationCount, expected);
    return recreated;
  }

  for (final knownReceipt in [false, true]) {
    test(
        knownReceipt
            ? 'cached decrypted mentions with known unread positions survive recreation'
            : 'cached mentions with no receipts or marker survive recreation',
        () async {
      if (knownReceipt) await readBaseline();
      final mention = message(r'$mention', 'ping');
      expect(MatrixPushRules.match(mention).highlight, isTrue);
      await send([mention]);
      expect(
          (client.getRoom(_roomId) as MatrixRoom).highlightedNotificationCount,
          1);
      final stored = await client.matrixClient.database
          .getEventById(mention.eventId, sdk());
      expect(stored?.originalSource?.type, matrix.EventTypes.Encrypted);
      await recreate(1);
    });
  }
  test('a marker without a receipt keeps historical unread state unknown',
      () async {
    final mention = message(r'$marker-only', 'ping');
    await send([mention]);
    sdk().roomAccountData['m.fully_read'] = matrix.BasicEvent(
        type: 'm.fully_read', content: {'event_id': mention.eventId});
    final room = await recreate(0);
    expect(room.restoreCachedHighlights([mention]), isFalse);
  });
  test('no-receipt recovery excludes history before a cached join', () async {
    final join = matrix.Event(
        type: matrix.EventTypes.RoomMember,
        eventId: r'$join',
        senderId: me,
        stateKey: me,
        room: sdk(),
        originServerTs: DateTime.now(),
        content: {'membership': 'join'});
    await send(
        [message(r'$prejoin', 'ping'), join, message(r'$postjoin', 'ping')]);
    await recreate(1);
  });
  test('blocking and unblocking recover an older cached mention', () async {
    await readBaseline();
    await send([
      message(r'$blocked', 'ping'),
      message(r'$ordinary', 'ordinary', sender: '@else:example.com')
    ]);
    final room = await recreate(1);
    final index = UnreadIndex.of(client);
    final blocking = client.getComponent<UserBlockingComponent>()!;
    var changed = index.onChanged
        .firstWhere((_) => room.highlightedNotificationCount == 0);
    await blocking.block('@them:example.com');
    await changed.timeout(const Duration(seconds: 5));
    changed = index.onChanged
        .firstWhere((_) => room.highlightedNotificationCount == 1);
    await blocking.unblock('@them:example.com');
    await changed.timeout(const Duration(seconds: 5));
  });
  test('filter changes hide and recover an older cached mention', () async {
    await readBaseline();
    await send(
        [message(r'$filtered', 'ping'), message(r'$ordinary', 'ordinary')]);
    final room = await recreate(1);
    final index = UnreadIndex.of(client);
    var changed = index.onChanged
        .firstWhere((_) => room.highlightedNotificationCount == 0);
    await MessageFilters.save(
        client,
        MessageFilterSettings(rules: [
          MessageFilterRule(term: 'ping', kind: MessageFilterKind.word)
        ]));
    await changed.timeout(const Duration(seconds: 5));
    changed = index.onChanged
        .firstWhere((_) => room.highlightedNotificationCount == 1);
    await MessageFilters.save(client, const MessageFilterSettings());
    await changed.timeout(const Duration(seconds: 5));
  });
  test('multiple earlier cached mentions survive a newer ordinary message',
      () async {
    await readBaseline();
    await send([
      message(r'$one', 'ping'),
      message(r'$two', 'ping'),
      message(r'$ordinary', 'ordinary')
    ]);
    expect((client.getRoom(_roomId) as MatrixRoom).highlightedNotificationCount,
        2);
    await recreate(2);
  });
  test(
      'a newer receipt outside the stored fragment does not resurrect old highlights',
      () async {
    await readBaseline();
    final mention = message(r'$old-mention', 'ping');
    await send([mention]);
    receipt(r'$newer-outside-fragment');
    final room = await recreate(0);
    expect(room.restoreCachedHighlights([mention]), isFalse);
    expect(room.highlightedNotificationCount, 0);
  });
  test('stored history before a known read position is not counted', () async {
    await send(
        [message(r'$history', 'ping'), message(r'$read', 'read message')]);
    receipt(r'$read');
    await recreate(0);
  });
  test('a cached page never replaces a newly found live mention', () async {
    await readBaseline();
    final older = message(r'$old', 'ping');
    await send([older]);
    final room = await recreate(1);
    await send([message(r'$live', 'ping')]);
    expect(room.highlightedNotificationCount, 2);
    room.restoreCachedHighlights([older]);
    expect(room.highlightedNotificationCount, 2);
  });
  test('redacting a non-preview highlight blocks stale cached copies',
      () async {
    await readBaseline();
    final mention = message(r'$redacted', 'ping');
    await send([mention, message(r'$preview', 'ordinary')]);
    final stale =
        await client.matrixClient.database.getEventById(mention.eventId, sdk());
    final room = await recreate(1);
    await send([
      matrix.MatrixEvent(
          type: matrix.EventTypes.Redaction,
          eventId: r'$redaction',
          redacts: mention.eventId,
          senderId: '@them:example.com',
          originServerTs: DateTime.now().add(const Duration(seconds: 1)),
          content: {})
    ]);
    expect(room.highlightedNotificationCount, 0);
    room.restoreCachedHighlights([stale!]);
    expect(room.highlightedNotificationCount, 0);
  });
  test('push rule changes remove old matches and recover new cached matches',
      () async {
    await readBaseline();
    await send([
      message(r'$oldword', 'ping'),
      message(r'$newword1', 'other'),
      message(r'$newword2', 'other')
    ]);
    final room = await recreate(1);
    final index = UnreadIndex.of(client);
    final changed = index.onChanged
        .firstWhere((_) => room.highlightedNotificationCount == 2);
    await sync(client, accountData: [_rules('other')]);
    await changed.timeout(const Duration(seconds: 5));
    expect(room.highlightedNotificationCount, 2);
  });
  test(
      'a late history decryption updates known unread highlights without changing IDs',
      () async {
    await readBaseline();
    final decrypted = message(r'$late', 'ping');
    await send([decrypted.originalSource!, message(r'$newest', 'ordinary')]);
    final room = await recreate(0);
    final order = unreadOrder(sdk()).toList();
    expect(order, contains(r'$late'));
    final changed = UnreadIndex.of(client)
        .onChanged
        .firstWhere((_) => room.highlightedNotificationCount == 1);
    // Exercise the existing room update API used by SDK history decryption.
    // ignore: deprecated_member_use
    room.onEvent(matrix.EventUpdate(
        roomID: _roomId,
        type: matrix.EventUpdateType.history,
        content: decrypted.toJson()));
    await changed.timeout(const Duration(seconds: 5));
    expect(unreadOrder(sdk()), order);
    expect(room.highlightedNotificationCount, 1);
  });
  test('edits and own messages are not reconstructed as new mentions',
      () async {
    await readBaseline();
    await send([
      message(r'$original', 'ordinary'),
      message(r'$edit', 'ping', edit: r'$original'),
      message(r'$own', 'ping', sender: me)
    ]);
    final room = await recreate(0);
    final stored =
        await client.matrixClient.database.getEventList(sdk(), limit: 10);
    room.restoreCachedHighlights(stored);
    expect(room.highlightedNotificationCount, 0);
  });
  test('a main read does not truncate recovery of an unread thread mention',
      () async {
    await send([
      message(r'$thread-read', 'ordinary', root: r'$root'),
      message(r'$reply', 'ping', root: r'$root'),
      message(r'$main', 'ordinary')
    ]);
    sdk().receiptState = matrix.LatestReceiptState.fromJson({
      'main': {
        'public': {'e': r'$main', 'ts': 999999}
      },
      'thread': {
        r'$root': {
          'public': {'e': r'$thread-read', 'ts': 1}
        }
      }
    });
    await recreate(1);
  });
}
