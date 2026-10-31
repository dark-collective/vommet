// Vommet issue 729: a DM accepted before anything was said sank to the
// bottom of the DM list. The invite's room is partial, so the sync that
// joined it dropped our join event and only the invite's stripped copy of
// our membership stayed; the newest full state event was the inviter's room
// creation.

import 'package:commet/client/matrix/matrix_room.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _me = "@me:example.org";
const _them = "@them:example.org";

class _FakeSdkClient extends Fake implements matrix.Client {
  @override
  String? get userID => _me;
}

class _FakeSdkRoom extends Fake implements matrix.Room {
  _FakeSdkRoom(this.membership);

  @override
  final matrix.Client client = _FakeSdkClient();

  @override
  final String id = "!dm:example.org";

  @override
  matrix.Membership membership;

  @override
  final Map<String, Map<String, matrix.StrippedStateEvent>> states = {};

  void put(matrix.StrippedStateEvent state) =>
      (states[state.type] ??= {})[state.stateKey!] = state;
}

matrix.Event _state(matrix.Room room, String type, String stateKey, DateTime at,
        Map<String, dynamic> content) =>
    matrix.Event(
        content: content,
        type: type,
        eventId: "\$$type-$stateKey",
        senderId: _them,
        originServerTs: at,
        room: room,
        stateKey: stateKey);

void main() {
  final created = DateTime(2026, 10, 1);
  final now = DateTime(2026, 10, 24, 12);

  _FakeSdkRoom acceptedDm({required bool joinLoaded}) {
    final room = _FakeSdkRoom(matrix.Membership.join);
    room.put(_state(room, matrix.EventTypes.RoomCreate, "", created, {}));
    if (joinLoaded) {
      room.put(_state(room, matrix.EventTypes.RoomMember, _me,
          DateTime(2026, 10, 24, 11, 59), {"membership": "join"}));
    } else {
      room.put(matrix.StrippedStateEvent(
          type: matrix.EventTypes.RoomMember,
          content: {"membership": "invite"},
          senderId: _them,
          stateKey: _me));
    }
    return room;
  }

  test("a just-accepted invite sorts by when it was accepted", () {
    final room = acceptedDm(joinLoaded: false);
    expect(MatrixRoom.newestStateTimestamp(room, joinedAt: () => now), now);
  });

  test("once our join is loaded, its own time counts", () {
    final room = acceptedDm(joinLoaded: true);
    expect(MatrixRoom.newestStateTimestamp(room, joinedAt: () => now),
        DateTime(2026, 10, 24, 11, 59));
  });

  test("a pending invite keeps the newest full state event", () {
    final room = acceptedDm(joinLoaded: false)
      ..membership = matrix.Membership.invite;
    expect(MatrixRoom.newestStateTimestamp(room, joinedAt: () => now), created);
  });

  test("a joined room without our member state loaded is left alone", () {
    final room = _FakeSdkRoom(matrix.Membership.join);
    room.put(_state(room, matrix.EventTypes.RoomCreate, "", created, {}));
    expect(MatrixRoom.newestStateTimestamp(room, joinedAt: () => now), created);
  });
}
