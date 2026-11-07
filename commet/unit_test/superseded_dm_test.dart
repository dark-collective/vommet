// Vommet issue 311: an upgraded DM leaves the DM list once you're in its
// replacement, so the person shows once. The list is a NotifyingListFilter
// over the client's rooms, re-checked by roomReplacementsChanged when a
// replacement room joins or leaves.
import 'package:commet/client/client.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/notifying_list_filter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClient extends Fake implements Client {
  final rooms = NotifyingList<Room>.empty(growable: true);

  @override
  Room? getRoom(String identifier) =>
      rooms.where((r) => r.identifier == identifier).firstOrNull;
}

class _FakeReplacement extends Fake implements RoomReplacement {
  _FakeReplacement({this.tombstone, this.predecessor});

  @override
  final RoomTombstone? tombstone;

  @override
  final RoomPredecessor? predecessor;
}

class _FakeRoom extends Fake implements Room {
  _FakeRoom(this.identifier, this.client,
      {String? replacedBy, String? continues, this.isBanned = false})
      : replacement = _FakeReplacement(
            tombstone: replacedBy == null
                ? null
                : RoomTombstone(replacementRoomId: replacedBy),
            predecessor:
                continues == null ? null : RoomPredecessor(roomId: continues));

  @override
  final String identifier;

  @override
  final Client client;

  @override
  final RoomReplacement replacement;

  @override
  final bool isBanned;

  @override
  String toString() => identifier;
}

/// The DM component's list: every room here is a DM.
NotifyingListFilter<Room> _dmList(_FakeClient client) => NotifyingListFilter(
      client.rooms,
      where: (room) => !isSupersededRoom(room),
      onFilterParamsChanged: [roomReplacementsChanged(client.rooms)],
    );

void main() {
  late _FakeClient client;

  setUp(() => client = _FakeClient());

  test('an upgraded DM is hidden when you are in its replacement', () {
    client.rooms
      ..add(_FakeRoom("!old", client, replacedBy: "!new"))
      ..add(_FakeRoom("!new", client, continues: "!old"));

    expect(_dmList(client).map((r) => r.identifier), ["!new"]);
  });

  test('every older room in a chain of upgrades is hidden', () {
    client.rooms
      ..add(_FakeRoom("!v1", client, replacedBy: "!v2"))
      ..add(_FakeRoom("!v2", client, replacedBy: "!v3", continues: "!v1"))
      ..add(_FakeRoom("!v3", client, continues: "!v2"));

    expect(_dmList(client).map((r) => r.identifier), ["!v3"]);
  });

  test('stays until you join the replacement, then goes', () async {
    client.rooms.add(_FakeRoom("!old", client, replacedBy: "!new"));
    final dms = _dmList(client);
    expect(dms.map((r) => r.identifier), ["!old"]);

    client.rooms.add(_FakeRoom("!new", client, continues: "!old"));
    await pumpEventQueue();

    expect(dms.map((r) => r.identifier), ["!new"]);
  });

  test('comes back when you leave the replacement', () async {
    final replacement = _FakeRoom("!new", client, continues: "!old");
    client.rooms
      ..add(_FakeRoom("!old", client, replacedBy: "!new"))
      ..add(replacement);
    final dms = _dmList(client);

    client.rooms.remove(replacement);
    await pumpEventQueue();

    expect(dms.map((r) => r.identifier), ["!old"]);
  });

  test('a replacement you are banned from keeps the old DM', () {
    client.rooms
      ..add(_FakeRoom("!old", client, replacedBy: "!new"))
      ..add(_FakeRoom("!new", client, continues: "!old", isBanned: true));

    expect(_dmList(client).map((r) => r.identifier), ["!old", "!new"]);
  });

  test('adding the replacement does not list it twice', () async {
    client.rooms.add(_FakeRoom("!old", client, replacedBy: "!new"));
    final dms = _dmList(client);

    client.rooms.add(_FakeRoom("!new", client, continues: "!old"));
    await pumpEventQueue();

    expect(dms.length, 1);
  });

  test('only rooms that continue another one trigger a re-check', () async {
    var fired = 0;
    roomReplacementsChanged(client.rooms).listen((_) => fired++);

    client.rooms.add(_FakeRoom("!plain", client));
    await pumpEventQueue();
    expect(fired, 0);

    client.rooms.add(_FakeRoom("!new", client, continues: "!old"));
    await pumpEventQueue();
    expect(fired, 1);
  });
}
