import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _me = "@me:example.org";
const _them = "@them:example.org";

class _FakeSdkClient extends Fake implements matrix.Client {
  @override
  String? get userID => _me;
}

Map<String, Object?> _read(String eventId, int ts) => {
      "latest": {"e": eventId, "ts": ts},
      "public": {"e": eventId, "ts": ts},
    };

matrix.Room _room(Map<String, Object?> receipts) {
  final room = matrix.Room(id: "!r:example.org", client: _FakeSdkClient());
  room.receiptState = matrix.LatestReceiptState.fromJson(receipts);
  rememberUnreadOrder(
      room, [r'$o', r'$x', r'$n', r'$t2', r'$t', r'$t1', r'$m']);
  return room;
}

matrix.Event _event(matrix.Room room, String id, int ts, {String? thread}) =>
    matrix.Event(
      type: matrix.EventTypes.Message,
      eventId: id,
      senderId: _them,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
      room: room,
      content: {
        "msgtype": "m.text",
        "body": id,
        if (thread != null)
          "m.relates_to": {"rel_type": "m.thread", "event_id": thread},
      },
    );

void main() {
  test('private receipt wins by position even with an older timestamp', () {
    final room = _room({
      'global': {
        'public': {'e': r'$m', 'ts': 9000},
        'private': {'e': r'$x', 'ts': 1},
      }
    });
    expect(readByOwnReceipts(room, _event(room, r'$n', 10000)), isTrue);
  });
  test('local own receipts cover the newest event before the sync echo', () {
    final room = _room({});
    recordOwnReceipt(room, r'$n');
    expect(readByOwnReceipts(room, _event(room, r'$n', 10000)), isTrue);
    expect(readByOwnReceipts(room, _event(room, r'$t1', 20000)), isTrue);
  });
  test('a newer main receipt does not read an older reply in another scope',
      () {
    final room = _room({
      'main': _read(r'$o', 999999),
      'thread': {r'$root': _read(r'$m', 1)},
    });
    expect(
        readByOwnReceipts(room, _event(room, r'$t2', 5000, thread: r'$root')),
        isFalse);
    expect(cachedUnreadPrefixLength(room), 6);
    expect(ownReceiptIdsForThread(room, r'$root'), isNot(contains(r'$o')));
    recordOwnReceipt(room, r'$o', threadId: 'main');
    expect(
        readByOwnReceipts(room, _event(room, r'$t2', 5000, thread: r'$root')),
        isFalse);
  });
  test('an unknown main receipt does not prevent known unread thread recovery',
      () {
    final room = _room({
      'main': _read(r'$outside', 999999),
      'thread': {r'$root': _read(r'$m', 1)},
    });
    expect(cachedUnreadPrefixLength(room), 6);
    expect(
        readByOwnReceipts(room, _event(room, r'$t2', 5000, thread: r'$root')),
        isFalse);
  });
  test(
      'an unknown global receipt prevents historical unread inference in every scope',
      () {
    final room = _room({
      'global': _read(r'$outside', 999999),
      'thread': {r'$root': _read(r'$m', 1)},
    });
    expect(cachedUnreadPrefixLength(room), 0);
  });
  test(
      'a fully read main scope without known thread reads needs no payload scan',
      () {
    final room = _room({'main': _read(r'$o', 1)});
    expect(cachedUnreadPrefixLength(room), 0);
  });
  group("Vommet issue 843: the unread mark and thread receipts", () {
    test("a main receipt on the newest message reads it", () {
      final room = _room({
        "main": _read(r"$m", 1000),
      });
      expect(readByOwnReceipts(room, _event(room, r"$m", 1000)), isTrue);
      expect(readByOwnReceipts(room, _event(room, r"$n", 2000)), isFalse);
    });

    test("a newer thread reply is read by its thread's receipt", () {
      final room = _room({
        "main": _read(r"$m", 1000),
        "thread": {r"$root": _read(r"$t2", 3000)},
      });
      expect(
          readByOwnReceipts(room, _event(room, r"$t2", 3000, thread: r"$root")),
          isTrue);
      expect(
          readByOwnReceipts(room, _event(room, r"$t1", 2000, thread: r"$root")),
          isTrue);
    });

    test("another thread's receipt doesn't read a reply", () {
      final room = _room({
        "main": _read(r"$m", 1000),
        "thread": {r"$other": _read(r"$o", 5000)},
      });
      expect(
          readByOwnReceipts(room, _event(room, r"$t", 3000, thread: r"$root")),
          isFalse);
      // ... nor a main message.
      expect(readByOwnReceipts(room, _event(room, r"$n", 3000)), isFalse);
    });

    test("an unthreaded receipt reads everything before it", () {
      final room = _room({
        "global": _read(r"$x", 4000),
      });
      expect(
          readByOwnReceipts(room, _event(room, r"$t", 3000, thread: r"$root")),
          isTrue);
      expect(readByOwnReceipts(room, _event(room, r"$n", 3500)), isTrue);
    });
  });
}
