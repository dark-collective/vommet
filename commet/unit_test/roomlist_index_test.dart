// Vommet: the client's id → room index, the spaces' child index, the DM id
// cache and the plaintext cache must answer exactly what a scan of the
// lists (or the SDK) would, through joins, leaves, rejoins and bans.
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/components/direct_messages/matrix_direct_chat_ids.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/client/matrix/timeline_events/matrix_plaintext_cache.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

const a = "!a:example.com";
const b = "!b:example.com";
const c = "!c:example.com";
const space = "!space:example.com";

/// What getRoom/hasRoom answered before the index: a scan of the list.
void expectIndexMatchesList(MatrixClient client, Iterable<String> ids) {
  for (final id in ids) {
    final scanned = client.rooms.where((r) => r.identifier == id).firstOrNull;
    expect(client.getRoom(id), same(scanned), reason: id);
    expect(client.hasRoom(id), scanned != null, reason: id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;
  var n = 0;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient("roomlist-index-${n++}");
  });

  tearDown(() => client.getMatrixClient().dispose(closeDatabase: true));

  test("joined rooms are found by id; spaces and unknown ids are not",
      () async {
    await sync(client, join: {
      a: joined(a),
      b: joined(b),
      space: joined(space, children: [a]),
    });

    expect(client.rooms.map((r) => r.identifier).toSet(), {a, b});
    expectIndexMatchesList(client, [a, b, c, space]);
    expect(client.getRoom(space), isNull);
    expect(client.getSpace(space)?.identifier, space);
    expect(client.hasSpace(space), isTrue);
    expect(client.hasSpace(a), isFalse);
  });

  test("a room we leave is dropped from the index", () async {
    await sync(client, join: {a: joined(a), b: joined(b)});
    final removed = <String>[];
    client.onRoomRemoved.listen((r) => removed.add(r.identifier));

    await sync(client, leave: {a: left("leave")});

    expect(removed, [a]);
    expect(client.rooms.map((r) => r.identifier), [b]);
    expectIndexMatchesList(client, [a, b]);
    expect(client.getRoom(a), isNull);
  });

  test("a rejoined room is found as its new object", () async {
    await sync(client, join: {a: joined(a)});
    final before = client.getRoom(a);

    await sync(client, leave: {a: left("leave")});
    expect(client.hasRoom(a), isFalse);

    await sync(client, join: {a: joined(a)});
    final after = client.getRoom(a) as MatrixRoom;
    expect(after, isNot(same(before)));
    expect(after.matrixRoom, same(client.getMatrixClient().getRoomById(a)));
    expect(client.rooms.where((r) => r.identifier == a).length, 1);
    expectIndexMatchesList(client, [a]);
  });

  test("a banned room stays found until dismissed, then it's gone", () async {
    await sync(client, join: {a: joined(a), b: joined(b)});
    final listed = client.getRoom(a);

    await sync(client, leave: {a: left("ban")});

    expect(client.getRoom(a), same(listed));
    expect(client.getRoom(a)!.isBanned, isTrue);
    expectIndexMatchesList(client, [a, b]);

    // An unrelated sync keeps it (and doesn't re-add it).
    await sync(client, join: {b: joined(b)});
    expect(client.getRoom(a), same(listed));
    expect(client.rooms.where((r) => r.identifier == a).length, 1);

    await client.dismissBannedRoom(listed as MatrixRoom);
    expect(client.getRoom(a), isNull);
    expect(client.hasRoom(a), isFalse);
    expectIndexMatchesList(client, [a, b]);
  });

  test("rooms added and removed directly keep the index in step", () async {
    await sync(client, join: {a: joined(a), b: joined(b)});
    final roomA = client.getRoom(a)!;
    final roomB = client.getRoom(b)!;

    client.rooms.remove(roomA);
    expectIndexMatchesList(client, [a, b]);
    client.rooms.insert(0, roomA);
    expectIndexMatchesList(client, [a, b]);
    client.rooms.removeWhere((r) => r.identifier == b);
    expectIndexMatchesList(client, [a, b]);
    client.rooms[0] = roomB;
    expectIndexMatchesList(client, [a, b]);
    client.rooms.clear();
    expectIndexMatchesList(client, [a, b]);
    expect(client.rooms, isEmpty);

    // The next sync lists them again.
    await sync(client, join: {c: joined(c)});
    expect(client.rooms.map((r) => r.identifier).toSet(), {a, b, c});
    expectIndexMatchesList(client, [a, b, c]);
  });

  test("a space knows its child rooms as they join and leave", () async {
    await sync(client, join: {
      a: joined(a),
      b: joined(b),
      space: joined(space, children: [a, c]),
    });
    final s = client.getSpace(space) as MatrixSpace;
    expect(s.containsRoom(a), isTrue);
    expect(s.containsRoom(b), isFalse);
    expect(s.containsRoom(c), isFalse);

    await sync(client, join: {c: joined(c)});
    expect(s.containsRoom(c), isTrue);

    await sync(client, leave: {a: left("leave")});
    expect(s.containsRoom(a), isFalse);
    for (final id in [a, b, c]) {
      expect(s.containsRoom(id), s.rooms.any((r) => r.identifier == id),
          reason: id);
    }
  });

  test("a space's color stays the hash of its id", () async {
    await sync(client, join: {space: joined(space, children: [])});
    final s = client.getSpace(space) as MatrixSpace;
    expect(s.color, s.color);
    expect(s.color.a, greaterThan(0));
  });

  group("DM ids", () {
    bool isDm(String id) => client
        .getComponent<DirectMessagesComponent>()!
        .isRoomDirectMessage(client.getRoom(id)!);

    test("follow m.direct changes, matching the SDK", () async {
      await sync(client, join: {a: joined(a), b: joined(b), c: joined(c)});
      final mx = client.getMatrixClient();
      expect([a, b, c].map(isDm), [false, false, false]);

      await sync(client, accountData: [
        directChats({
          "@friend:example.com": [a]
        })
      ]);
      expect(MatrixDirectChatIds.of(mx), {a});
      expect([a, b, c].map(isDm), [true, false, false]);

      await sync(client, accountData: [
        directChats({
          "@friend:example.com": [b],
          "@other:example.com": [c],
        })
      ]);
      expect(MatrixDirectChatIds.of(mx), {b, c});
      expect([a, b, c].map(isDm), [false, true, true]);
      for (final id in [a, b, c]) {
        expect(isDm(id), mx.getRoomById(id)!.isDirectChat, reason: id);
      }

      await sync(client, accountData: [directChats({})]);
      expect([a, b, c].map(isDm), [false, false, false]);
    });

    test("the same m.direct gives the same set", () async {
      await sync(client, accountData: [
        directChats({
          "@friend:example.com": [a]
        })
      ]);
      final mx = client.getMatrixClient();
      expect(MatrixDirectChatIds.of(mx), same(MatrixDirectChatIds.of(mx)));
    });

    test("an invite is left to the SDK", () {
      final room = matrix.Room(
          id: c,
          membership: matrix.Membership.invite,
          client: client.getMatrixClient());
      expect(MatrixDirectChatIds.mayBeDirectChat(room), isTrue);
    });
  });

  group("plaintext cache", () {
    matrix.Event message(Map<String, Object?> content) => matrix.Event(
          type: "m.room.message",
          content: {"msgtype": "m.text", ...content},
          eventId: "\$m${n++}",
          senderId: "@friend:example.com",
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          room: matrix.Room(id: a, client: client.getMatrixClient()),
        );

    setUp(MatrixPlaintextCache.clear);

    test("gives the SDK's text for formatted and plain messages", () {
      final events = [
        message({
          "body": "*hi*",
          "format": "org.matrix.custom.html",
          "formatted_body": "<em>hi</em> <a href='https://x.y'>there</a>",
        }),
        message({"body": "plain"}),
        message({
          "body": "fallback",
          "format": "something.else",
          "formatted_body": "<b>not html</b>",
        }),
        message({
          "body": "empty",
          "format": "org.matrix.custom.html",
          "formatted_body": "",
        }),
      ];
      for (final e in events) {
        expect(e.cachedPlaintextBody, e.plaintextBody);
        expect(e.cachedPlaintextBody, e.plaintextBody);
      }
      expect(MatrixPlaintextCache.length, 1);
    });

    test("an edit with new HTML gets new text", () {
      final first = message({
        "body": "one",
        "format": "org.matrix.custom.html",
        "formatted_body": "<b>one</b>",
      });
      final edited = message({
        "body": "two",
        "format": "org.matrix.custom.html",
        "formatted_body": "<b>two</b>",
      });
      expect(first.cachedPlaintextBody, first.plaintextBody);
      expect(edited.cachedPlaintextBody, edited.plaintextBody);
      expect(edited.cachedPlaintextBody, isNot(first.cachedPlaintextBody));
      expect(first.cachedPlaintextBody, first.plaintextBody);
    });

    test("stays bounded", () {
      for (var i = 0; i < 2000; i++) {
        message({
          "body": "$i",
          "format": "org.matrix.custom.html",
          "formatted_body": "<b>$i</b>",
        }).cachedPlaintextBody;
      }
      expect(MatrixPlaintextCache.length, lessThanOrEqualTo(512));
    });
  });
}
