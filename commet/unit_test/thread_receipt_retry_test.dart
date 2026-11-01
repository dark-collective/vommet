import 'dart:async';
import 'package:commet/client/matrix/components/threads/thread_receipts.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/msc_extensions/msc_4186_sliding_sync/controller.dart';

class _Client extends Fake implements matrix.Client {
  _Client(this.userID, {bool mine = false}) {
    accountData['im.vommet.thread_read_state'] = matrix.BasicEvent(
        type: 'im.vommet.thread_read_state',
        content: {'default': mine ? 'mine' : 'all'});
  }
  @override
  final String userID;
  @override
  final Map<String, matrix.BasicEvent> accountData = {};
  @override
  final List<matrix.Room> rooms = [];
  @override
  bool get slidingSync => false;
  @override
  late final SlidingSyncController slidingSyncController =
      SlidingSyncController(this);
  bool failMarker = false;
  String? blockedEvent;
  final markerGate = Completer<void>();
  int markerRequests = 0;
  final receipts = <String?>[];
  @override
  Future<void> setReadMarker(String roomId,
      {String? mFullyRead, String? mRead, String? mReadPrivate}) async {
    markerRequests++;
    if (mFullyRead == blockedEvent) await markerGate.future;
    if (failMarker) {
      failMarker = false;
      throw StateError('marker request failed');
    }
  }

  @override
  Future<void> postReceipt(
      String roomId, matrix.ReceiptType receiptType, String eventId,
      {String? threadId}) async {
    receipts.add(threadId);
  }
}

class _Timeline extends Fake implements matrix.Timeline {
  _Timeline(this.room, this.events);
  @override
  final matrix.Room room;
  @override
  final List<matrix.Event> events;
}

matrix.Event _event(matrix.Room room, String id,
        {String? sender, String? root}) =>
    matrix.Event(
        type: matrix.EventTypes.Message,
        eventId: id,
        senderId: sender ?? '@other:example.org',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        room: room,
        content: {
          'msgtype': 'm.text',
          'body': 'message',
          if (root != null)
            'm.relates_to': {'rel_type': 'm.thread', 'event_id': root}
        });
void main() {
  test('a failed fully-read marker request does not suppress its receipt retry',
      () async {
    final client = _Client('@a:example.org')..failMarker = true;
    final room = matrix.Room(id: '!retry:example.org', client: client);
    final event = _event(room, r'$retry');
    final timeline = _Timeline(room, [event]);
    await expectLater(
        ThreadReceipts.markMainRead(timeline, public: true), throwsStateError);
    expect(readByOwnReceipts(room, event), isFalse);
    await ThreadReceipts.markMainRead(timeline, public: true);
    expect(client.markerRequests, 2);
    expect(client.receipts, ['main']);
    expect(readByOwnReceipts(room, event), isTrue);
  });
  test('an older failed marker cannot clear a newer successful receipt',
      () async {
    final client = _Client('@a:example.org')..blockedEvent = r'$old';
    final room = matrix.Room(id: '!overlap:example.org', client: client);
    final old = _event(room, r'$old');
    final fresh = _event(room, r'$fresh');
    final timeline = _Timeline(room, [old]);
    final oldRequest = ThreadReceipts.markMainRead(timeline, public: true);
    final oldFailed = expectLater(oldRequest, throwsStateError);
    timeline.events.insert(0, fresh);
    await ThreadReceipts.markMainRead(timeline, public: true);
    client.markerGate.completeError(StateError('older request failed'));
    await oldFailed;
    await ThreadReceipts.markMainRead(timeline, public: true);
    expect(client.markerRequests, 2);
    expect(client.receipts, ['main']);
  });
  test(
      'new SDK room objects do not inherit dedupe state from an earlier lifetime',
      () async {
    final client = _Client('@a:example.org');
    for (var i = 0; i < 2; i++) {
      final room = matrix.Room(id: '!recreated:example.org', client: client);
      await ThreadReceipts.markMainRead(
          _Timeline(room, [_event(room, r'$same')]),
          public: true);
    }
    expect(client.receipts, ['main', 'main']);
  });
  test('two SDK sessions for the same user send their own receipts', () async {
    final a = _Client('@same:example.org');
    final b = _Client('@same:example.org');
    final ra = matrix.Room(id: '!same-user:example.org', client: a);
    final rb = matrix.Room(id: '!same-user:example.org', client: b);
    await ThreadReceipts.markMainRead(
        _Timeline(ra, [_event(ra, r'$same-user')]),
        public: true);
    await ThreadReceipts.markMainRead(
        _Timeline(rb, [_event(rb, r'$same-user')]),
        public: false);
    expect(a.receipts, ['main']);
    expect(b.receipts, ['main']);
  });
  test('reading the same room and event from two accounts sends both receipts',
      () async {
    final a = _Client('@a:example.org');
    final b = _Client('@b:example.org');
    final ra = matrix.Room(id: '!shared:example.org', client: a);
    final rb = matrix.Room(id: '!shared:example.org', client: b);
    await ThreadReceipts.markMainRead(_Timeline(ra, [_event(ra, r'$shared')]),
        public: true);
    await ThreadReceipts.markMainRead(_Timeline(rb, [_event(rb, r'$shared')]),
        public: false);
    expect(a.receipts, ['main']);
    expect(b.receipts, ['main']);
  });
  test('a skewed older receipt timestamp cannot suppress an unread reply',
      () async {
    final client = _Client('@a:example.org', mine: true);
    final room = matrix.Room(id: '!skew:example.org', client: client);
    final reply = _event(room, r'$reply', root: r'$root');
    final old = _event(room, r'$old', root: r'$root');
    final root = _event(room, r'$root');
    final main = _event(room, r'$main');
    rememberUnreadOrder(
        room, [main.eventId, reply.eventId, old.eventId, root.eventId]);
    room.receiptState = matrix.LatestReceiptState.fromJson({
      'thread': {
        r'$root': {
          'public': {'e': old.eventId, 'ts': 999999999},
          'latest': {'e': old.eventId, 'ts': 999999999}
        }
      }
    });
    await ThreadReceipts.markMainRead(_Timeline(room, [main, reply, old, root]),
        public: true);
    expect(client.receipts, ['main', r'$root']);
    expect(readByOwnReceipts(room, reply), isTrue);
  });
  test('thread participation caches belong to the account that participated',
      () async {
    final a = _Client('@a:example.org', mine: true);
    final b = _Client('@b:example.org', mine: true);
    final ra = matrix.Room(id: '!participation:example.org', client: a);
    final rb = matrix.Room(id: '!participation:example.org', client: b);
    List<matrix.Event> events(matrix.Room room) => [
          _event(room, r'$reply', root: r'$root'),
          _event(room, r'$main'),
          _event(room, r'$root', sender: '@a:example.org')
        ];
    await ThreadReceipts.markMainRead(_Timeline(ra, events(ra)), public: true);
    await ThreadReceipts.markMainRead(_Timeline(rb, events(rb)), public: true);
    expect(a.receipts, isNot(contains(r'$root')));
    expect(b.receipts, contains(r'$root'));
  });
}
