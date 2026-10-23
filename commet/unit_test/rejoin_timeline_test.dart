// Vommet: after leaving and rejoining a room its timeline failed to load
// ("Bad state: No element": the stored timeline still listed the events
// deleted on leave), and the closed room object kept handling the room's
// syncs ("Cannot add new events after calling close").
import 'dart:async';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

const a = "!a:example.com";

int _n = 0;

matrix.MatrixEvent message(String id) => matrix.MatrixEvent(
      type: matrix.EventTypes.Message,
      content: {"msgtype": "m.text", "body": "body $id"},
      senderId: "@bob:example.com",
      eventId: id,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1700000100000 + _n++),
    );

matrix.JoinedRoomUpdate joinedWith(List<String> ids) => matrix.JoinedRoomUpdate(
      state: roomState(a),
      timeline: matrix.TimelineUpdate(
          events: [for (final id in ids) message(id)], prevBatch: "p"),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;
  var n = 0;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient("rejoin-timeline-${n++}");
  });

  tearDown(() => client.getMatrixClient().dispose(closeDatabase: true));

  test("a rejoined room's timeline loads with the new events", () async {
    await sync(client, join: {
      a: joinedWith([r"$old1", r"$old2"])
    });
    await sync(client, leave: {a: left("leave")});
    await sync(client, join: {
      a: joinedWith([r"$new1", r"$new2"])
    });

    final room = client.getMatrixClient().getRoomById(a)!;
    final timeline = await room.getTimeline();
    final ids = timeline.events.map((e) => e.eventId).toList();
    expect(ids, containsAll([r"$new1", r"$new2"]));
    expect(ids, isNot(contains(r"$old1")));
    expect(ids, isNot(contains(r"$old2")));
    timeline.cancelSubscriptions();
  });

  test("the left room's object is closed and ignores later syncs", () async {
    await sync(client, join: {
      a: joinedWith([r"$e1"])
    });
    final before = client.getRoom(a) as MatrixRoom;
    final closed = Completer<void>();
    before.onUpdate.listen((_) {}, onDone: closed.complete);

    await sync(client, leave: {a: left("leave")});
    await closed.future.timeout(const Duration(seconds: 5));

    // Syncs for the rejoined room reach the new object only; the old one
    // used to throw on each of them.
    await sync(client, join: {
      a: joinedWith([r"$e2"])
    });
    await sync(client, join: {
      a: joinedWith([r"$e3"])
    });
    final after = client.getRoom(a);
    expect(after, isNot(same(before)));
    var updates = 0;
    (after as MatrixRoom).onUpdate.listen((_) => updates++);
    await sync(client, join: {
      a: joinedWith([r"$e4"])
    });
    expect(updates, greaterThan(0));

    // Closing it again (leaveRoom closes too) is harmless.
    await before.close();
  });
}
