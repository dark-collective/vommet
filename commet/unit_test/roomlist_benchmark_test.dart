// Vommet: how long the room list work after each sync takes for an account
// the size of a heavy real one (~300 rooms, ~30 spaces), and the home
// screen's room filter (ClientManager.singleRooms). A CPU profile on a
// Pinebook Pro put the room list update at ~14% and singleRooms at ~6% of the
// UI isolate. Prints timings; asserts only that the results are right, so a
// slow CI machine can't fail it.
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

const roomCount = 300;
const spaceCount = 30;
const roomsPerSpace = 8;
const dmCount = 30;

String roomId(int i) => "!room$i:example.com";
String spaceId(int i) => "!space$i:example.com";

double _msPer(Stopwatch clock, int runs) =>
    clock.elapsedMicroseconds / runs / 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient("roomlist-benchmark");

    // Spaces hold the first spaceCount * roomsPerSpace rooms; the last
    // dmCount rooms are DMs; the rest sit in no space.
    await sync(
      client,
      join: {
        for (var s = 0; s < spaceCount; s++)
          spaceId(s): joined(spaceId(s), children: [
            for (var r = 0; r < roomsPerSpace; r++)
              roomId(s * roomsPerSpace + r),
          ]),
        for (var r = 0; r < roomCount; r++) roomId(r): joined(roomId(r)),
      },
      accountData: [
        directChats({
          for (var d = 0; d < dmCount; d++)
            "@friend$d:example.com": [roomId(roomCount - 1 - d)],
        }),
      ],
    );
  });

  tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

  test("room list update after a sync", () async {
    expect(client.rooms.length, roomCount);
    expect(client.spaces.length, spaceCount);

    // An empty sync still rebuilds the room and space lists.
    void emptySync() =>
        client.onMatrixClientSync(matrix.SyncUpdate(nextBatch: "bench"));

    for (var i = 0; i < 5; i++) {
      emptySync();
    }
    const runs = 50;
    final clock = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      emptySync();
    }
    clock.stop();
    debugPrint("BENCH room list update after a sync "
        "($roomCount rooms, $spaceCount spaces): "
        "${_msPer(clock, runs).toStringAsFixed(3)} ms");

    expect(client.rooms.length, roomCount);
    for (var r = 0; r < roomCount; r++) {
      expect(client.getRoom(roomId(r))?.identifier, roomId(r));
    }
  });

  test("home screen room filter (singleRooms)", () {
    final manager = ClientManager();
    manager.clients.add(client);

    var single = manager.singleRooms();
    for (var i = 0; i < 5; i++) {
      single = manager.singleRooms();
    }
    const runs = 50;
    final clock = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      single = manager.singleRooms();
    }
    clock.stop();
    debugPrint("BENCH singleRooms ($roomCount rooms, $spaceCount spaces, "
        "$dmCount DMs): ${_msPer(clock, runs).toStringAsFixed(3)} ms");

    // Neither in a space nor a DM.
    final expected = [
      for (var r = spaceCount * roomsPerSpace; r < roomCount - dmCount; r++)
        roomId(r),
    ];
    expect(single.map((r) => r.identifier).toSet(), expected.toSet());
    expect(single.length, expected.length);
  });

  test("last-message preview text (plainTextBody)", () {
    final sdkRoom = client.getMatrixClient().getRoomById(roomId(0))!;
    final events = [
      for (var i = 0; i < roomCount; i++)
        MatrixTimelineEventMessage(
          matrix.Event(
            type: "m.room.message",
            content: {
              "msgtype": "m.text",
              "body": "hello **world** $i",
              "format": "org.matrix.custom.html",
              "formatted_body": "<p>hello <strong>world</strong> $i "
                  "<a href=\"https://example.com/$i\">link</a></p>",
            },
            eventId: "\$preview$i",
            senderId: "@friend:example.com",
            originServerTs: DateTime.fromMillisecondsSinceEpoch(1700000000000),
            room: sdkRoom,
          ),
          client: client,
        ),
    ];

    // One pass is one rebuild of a room list showing every room.
    for (final e in events) {
      e.plainTextBody;
    }
    const runs = 20;
    final clock = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      for (final e in events) {
        e.plainTextBody;
      }
    }
    clock.stop();
    debugPrint("BENCH last-message previews ($roomCount formatted): "
        "${_msPer(clock, runs).toStringAsFixed(3)} ms per rebuild");

    expect(events[7].plainTextBody, events[7].event.plaintextBody);
    expect(events[7].plainTextBody, contains("world"));
  });
}
