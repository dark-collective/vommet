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

  @override
  matrix.Event? lastEvent;

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

  matrix.Event preview(matrix.Room room, String type, DateTime at) => _state(
      room, type, "", at, {"body": "A message", "topic": "Playing Portal 2"});

  test("topic-only updates and clearing a topic keep an empty DM's join time",
      () {
    final room = acceptedDm(joinLoaded: true);
    final joined = DateTime(2026, 10, 24, 11, 59);
    for (var minute = 0; minute < 4; minute++) {
      room.put(_state(
          room,
          matrix.EventTypes.RoomTopic,
          "",
          now.add(Duration(minutes: minute)),
          {"topic": minute == 3 ? "" : "Playing"}));
      expect(MatrixRoom.activityTimestamp(room, joinedAt: () => now), joined);
    }
  });

  test("a topic cannot outrank a known message, even during SDK refresh", () {
    final room = acceptedDm(joinLoaded: true);
    final messageAt = now.subtract(const Duration(days: 1));
    room.put(preview(room, matrix.EventTypes.RoomTopic, now));
    room.lastEvent = preview(room, matrix.EventTypes.refreshingLastEvent, now);
    expect(
        MatrixRoom.activityTimestamp(room,
            preview: preview(room, matrix.EventTypes.Message, messageAt),
            joinedAt: () => now),
        messageAt);
    // A remembered message also survives both preview slots refreshing.
    expect(
        MatrixRoom.activityTimestamp(room,
            preview: room.lastEvent,
            lastMessageAt: messageAt,
            joinedAt: () => now),
        messageAt);
  });

  test("topic and refresh previews use the empty-room fallback", () {
    final room = acceptedDm(joinLoaded: true);
    final joined = DateTime(2026, 10, 24, 11, 59);
    room.lastEvent = preview(room, matrix.EventTypes.RoomTopic, now);
    expect(
        MatrixRoom.activityTimestamp(room,
            preview: preview(room, matrix.EventTypes.refreshingLastEvent, now),
            joinedAt: () => now),
        joined);
  });

  for (final type in [
    matrix.EventTypes.Message,
    matrix.EventTypes.Encrypted,
    matrix.EventTypes.Sticker,
    matrix.EventTypes.CallInvite,
    matrix.EventTypes.GroupCallMember
  ]) {
    test("SDK $type activity stays current during wrapper refresh", () {
      final room = acceptedDm(joinLoaded: true);
      room.lastEvent = preview(room, type, now);
      expect(
          MatrixRoom.activityTimestamp(room,
              preview: preview(room, matrix.EventTypes.refreshingLastEvent,
                  now.add(const Duration(minutes: 1))),
              lastMessageAt: now.subtract(const Duration(days: 1)),
              joinedAt: () => now),
          now);
    });
  }

  test("newest genuine preview wins, including a pending outgoing message", () {
    final room = acceptedDm(joinLoaded: true);
    room.lastEvent = preview(room, matrix.EventTypes.Message, now);
    final sent = now.add(const Duration(minutes: 1));
    expect(
        MatrixRoom.activityTimestamp(room,
            preview: preview(room, matrix.EventTypes.Message, sent),
            joinedAt: () => now),
        sent);
  });

  test("topic updates don't reorder an empty DM above a newer conversation",
      () {
    final quiet = acceptedDm(joinLoaded: true);
    final active = acceptedDm(joinLoaded: true);
    active.lastEvent = preview(active, matrix.EventTypes.Message, now);
    DateTime activity(matrix.Room room) =>
        MatrixRoom.activityTimestamp(room, joinedAt: () => now)!;
    List<matrix.Room> ordered() =>
        [quiet, active]..sort((a, b) => activity(b).compareTo(activity(a)));
    expect(ordered().first, same(active));
    quiet.put(preview(
        quiet, matrix.EventTypes.RoomTopic, now.add(const Duration(hours: 1))));
    expect(ordered().first, same(active));
  });

  test("other state fallbacks and accepted invites retain their ordering", () {
    final room = acceptedDm(joinLoaded: false);
    room.put(preview(
        room, matrix.EventTypes.RoomTopic, now.add(const Duration(hours: 1))));
    expect(MatrixRoom.activityTimestamp(room, joinedAt: () => now), now);
    final named = acceptedDm(joinLoaded: true);
    named.put(preview(named, matrix.EventTypes.RoomName, now));
    expect(MatrixRoom.activityTimestamp(named, joinedAt: () => now), now);
  });
}
