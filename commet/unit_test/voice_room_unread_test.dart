// Vommet (operator report 2026-11-04): a voice room lit its unread dot when
// people only joined the call or changed their avatar. Discord marks a
// voice channel unread only for a new message in its text chat. The joins
// were never counted; the read receipt was. It sat on a call or member
// event this device never stored (a gappy sync, or read on another device),
// so its position was unknown and the room's last message looked unread.
import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/room_unread_source.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/notification_debug_collect.dart';
import 'package:commet/utils/unread_index.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'roomlist_fixture.dart';

const _room = '!voice:example.com';
final _t0 = DateTime.now().subtract(const Duration(hours: 1));

matrix.MatrixEvent _message(String id, DateTime at) => matrix.MatrixEvent(
      type: matrix.EventTypes.Message,
      content: {'msgtype': 'm.text', 'body': 'hi'},
      senderId: '@bob:example.com',
      eventId: id,
      originServerTs: at,
    );

/// Someone joining the call: their call membership.
matrix.MatrixEvent _callJoin(String id, String user, DateTime at) =>
    matrix.MatrixEvent(
      type: 'org.matrix.msc3401.call.member',
      content: {
        'application': 'm.call',
        'call_id': '',
        'scope': 'm.room',
        'device_id': 'DEV',
        'focus_active': {'type': 'livekit'},
        'foci_preferred': [],
      },
      senderId: user,
      stateKey: '_${user}_DEV',
      eventId: id,
      originServerTs: at,
    );

/// Someone changing their avatar.
matrix.MatrixEvent _avatar(String id, String user, DateTime at) =>
    matrix.MatrixEvent(
      type: matrix.EventTypes.RoomMember,
      content: {'membership': 'join', 'avatar_url': 'mxc://example.com/a'},
      senderId: user,
      stateKey: user,
      eventId: id,
      originServerTs: at,
    );

/// Our read receipt on [eventId], sent at [at].
matrix.BasicEvent _receipt(String eventId, DateTime at) => matrix.BasicEvent(
      type: 'm.receipt',
      content: {
        eventId: {
          'm.read': {
            me: {'ts': at.millisecondsSinceEpoch},
          },
        },
      },
    );

matrix.JoinedRoomUpdate _update(List<matrix.MatrixEvent> events,
        {bool limited = false, List<matrix.BasicEvent>? ephemeral}) =>
    matrix.JoinedRoomUpdate(
      state: roomState(_room),
      unreadNotifications: matrix.UnreadNotificationCounts(
          notificationCount: 0, highlightCount: 0),
      timeline: matrix.TimelineUpdate(
          events: events, limited: limited, prevBatch: limited ? 'gap' : null),
      ephemeral: ephemeral,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MatrixClient client;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient('voice-room-unread');
  });
  tearDown(() async {
    await UnreadIndex.disposeFor(client);
    for (final room in client.rooms) await room.close();
    await client.matrixClient.dispose(closeDatabase: true);
  });
  Room room() => client.rooms.firstWhere((r) => r.identifier == _room);

  /// Bob's message, then people join the call after a gap; our receipt (we
  /// read the room on another device) is on a join this device never got.
  Future<void> readPastTheGap(
      {List<matrix.MatrixEvent> after = const []}) async {
    // An older message we'd read: the room was already known here.
    await sync(client, join: {
      _room: _update([
        _message(r'$old', _t0.subtract(const Duration(minutes: 10)))
      ], ephemeral: [
        _receipt(r'$old', _t0.subtract(const Duration(minutes: 9))),
      ]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sync(client, join: {
      _room: _update([_message(r'$msg', _t0)]),
    });
    // The app was running: the unread index stored the message's place.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(unreadOrder((room() as MatrixRoom).matrixRoom), contains(r'$msg'));
    expect(computeRoomUnread(room()).unread, isTrue, reason: "bob's message");
    await sync(client, join: {
      _room: _update(
          [
            _callJoin(r'$join3', '@carol:example.com',
                _t0.add(const Duration(minutes: 3))),
            _avatar(r'$avatar', '@dave:example.com',
                _t0.add(const Duration(minutes: 4))),
            ...after,
          ],
          limited: true,
          ephemeral: [
            _receipt(r'$join2', _t0.add(const Duration(minutes: 2))),
          ]),
    });
    // Let the unread index read the stored order.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  test('a receipt past a gap: joins and an avatar change show no dot',
      () async {
    await readPastTheGap();
    final unread = computeRoomUnread(room());
    expect((unread.activity, unread.badge, unread.unread), (false, 0, false));
    expect(UnreadIndex.roomOf(room()).unread, isFalse);
    // The debug dump says why.
    final evidence = notificationReadEvidence(room() as MatrixRoom);
    expect((evidence.visibleCoverage, evidence.readAfterVisible), (null, true));
  });

  test('a receipt past a gap: a newer message still shows the dot', () async {
    await readPastTheGap(after: [
      _message(r'$new', _t0.add(const Duration(minutes: 5))),
    ]);
    final unread = computeRoomUnread(room());
    expect((unread.activity, unread.unread), (true, true));
  });

  test('read, then people join and change avatars: no dot', () async {
    await sync(client, join: {
      _room: _update([_message(r'$msg', _t0)],
          ephemeral: [_receipt(r'$msg', _t0.add(const Duration(minutes: 1)))]),
    });
    await sync(client, join: {
      _room: _update([
        _callJoin(r'$join', '@carol:example.com',
            _t0.add(const Duration(minutes: 2))),
        _avatar(r'$avatar', '@dave:example.com',
            _t0.add(const Duration(minutes: 3))),
      ]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(computeRoomUnread(room()).unread, isFalse);
  });

  test('the Unread card agrees: the message read past the gap counts read',
      () async {
    await readPastTheGap();
    final mx = (room() as MatrixRoom).matrixRoom;
    final event = matrix.Event.fromMatrixEvent(_message(r'$msg', _t0), mx);
    expect(readByOwnReceipts(mx, event), isTrue);
  });

  test('a receipt past a gap sent before the message: still unread', () async {
    await sync(client, join: {
      _room: _update([_message(r'$msg', _t0)]),
    });
    await sync(client, join: {
      _room: _update(
          [
            _callJoin(r'$join3', '@carol:example.com',
                _t0.add(const Duration(minutes: 3))),
          ],
          limited: true,
          ephemeral: [
            // An older receipt, on an event this device never got.
            _receipt(r'$old', _t0.subtract(const Duration(minutes: 1))),
          ]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(computeRoomUnread(room()).unread, isTrue);
  });

  test(
      'a message that arrives after a receipt this device can\'t place, '
      'sent before it: still unread, also after a later gap', () async {
    // A slow federated server: Bob's mention left at _t0 but reached us
    // after we read the room elsewhere at _t0 + 30 s. The room was already
    // known here, and the two syncs come in a burst, before the unread index
    // reads the stored order again.
    await sync(client, join: {
      _room: _update([
        _message(r'$old', _t0.subtract(const Duration(minutes: 10)))
      ], ephemeral: [
        _receipt(r'$old', _t0.subtract(const Duration(minutes: 9))),
      ]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(computeRoomUnread(room()).unread, isFalse);
    await sync(client, join: {
      _room: _update(
          [
            _callJoin(r'$join3', '@carol:example.com', _t0),
          ],
          limited: true,
          ephemeral: [
            _receipt(r'$elsewhere', _t0.add(const Duration(seconds: 30))),
          ]),
    });
    await sync(client, join: {
      _room: _update([
        matrix.MatrixEvent(
          type: matrix.EventTypes.Message,
          content: {
            'msgtype': 'm.text',
            'body': 'hey',
            'm.mentions': {
              'user_ids': [me],
            },
          },
          senderId: '@bob:example.com',
          eventId: r'$late',
          originServerTs: _t0,
        ),
      ]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(computeRoomUnread(room()).unread, isTrue);
    final mx = (room() as MatrixRoom).matrixRoom;
    final late = await mx.getEventById(r'$late');
    // Not read for the Unread card and local mention highlights either.
    expect(readByOwnReceipts(mx, late!), isFalse);
    // Then a burst of joins: a limited sync drops the stored order again.
    await sync(client, join: {
      _room: _update([
        _callJoin(r'$join9', '@erin:example.com',
            _t0.add(const Duration(minutes: 9))),
      ], limited: true),
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(unreadOrder(mx), isNot(contains(r'$late')));
    expect(computeRoomUnread(room()).unread, isTrue);
    expect(readByOwnReceipts(mx, late), isFalse);
  });

  test(
      'a receipt this device can\'t place in the same sync as a late '
      'message: still unread', () async {
    await sync(client, join: {
      _room: _update([
        _message(r'$old', _t0.subtract(const Duration(minutes: 10)))
      ], ephemeral: [
        _receipt(r'$old', _t0.subtract(const Duration(minutes: 9))),
      ]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // After a reconnect: Bob's message (sent at _t0, delivered late) and a
    // receipt from another device on an event this device never got.
    await sync(client, join: {
      _room: _update([_message(r'$late', _t0)],
          limited: true,
          ephemeral: [
            _receipt(r'$elsewhere', _t0.add(const Duration(seconds: 30))),
          ]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(computeRoomUnread(room()).unread, isTrue);
  });

  test('a gap fill bringing the message back keeps the dot cleared', () async {
    // The message came with the room's first sync, before the joins.
    await sync(client, join: {
      _room: _update([_message(r'$msg', _t0)]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sync(client, join: {
      _room: _update(
          [
            _callJoin(r'$join3', '@carol:example.com',
                _t0.add(const Duration(minutes: 3))),
          ],
          limited: true,
          ephemeral: [
            _receipt(r'$join2', _t0.add(const Duration(minutes: 2))),
          ]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(computeRoomUnread(room()).unread, isFalse);
    // The SDK's sliding-sync gap filler: a sync of its own, no next_batch.
    await client.matrixClient.handleSync(matrix.SyncUpdate(
      nextBatch: '',
      rooms: matrix.RoomsUpdate(join: {
        _room: matrix.JoinedRoomUpdate(
            timeline: matrix.TimelineUpdate(events: [_message(r'$msg', _t0)])),
      }),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(computeRoomUnread(room()).unread, isFalse);
  });

  // Vommet (operator report 2026-11-04): Mark as read cleared a text room's
  // dot but not a voice room's. The receipt goes on the newest event: in a
  // text room the message itself, in a voice room someone's call join.
  // After a limited sync the message isn't in the stored order, so the join
  // couldn't be compared with it.
  for (final voice in [false, true]) {
    test(
        voice
            ? 'Mark as read on a voice room whose newest event is a join '
                'after a gap clears the dot'
            : 'Mark as read on a text room clears the dot', () async {
      await sync(client, join: {
        _room: _update([_message(r'$msg', _t0)]),
      });
      if (voice) {
        await sync(client, join: {
          _room: _update([
            _callJoin(r'$join', '@carol:example.com',
                _t0.add(const Duration(minutes: 1))),
          ], limited: true),
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(computeRoomUnread(room()).unread, isTrue);
      await room().markAsRead();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(computeRoomUnread(room()).unread, isFalse);
      expect(UnreadIndex.roomOf(room()).unread, isFalse);
      // A message after the mark lights it again.
      await sync(client, join: {
        _room: _update([_message(r'$new', DateTime.now())]),
      });
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(computeRoomUnread(room()).unread, isTrue);
    });
  }
}
