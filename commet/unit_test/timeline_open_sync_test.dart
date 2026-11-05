// Vommet: a sync that reaches a room while it opens (a gap fill, new
// messages) is mirrored once, not applied to the still-empty event list.
// The SDK reported the inserts and removals before the first copy: they
// were added twice, or removed past the end (RangeError in the IT
// "sliding sync gap: encrypted below newer").
import 'dart:async';
import 'dart:convert';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

const roomId = "!open:example.com";

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {"content-type": "application/json"});

int _n = 0;

matrix.MatrixEvent message(String body) => matrix.MatrixEvent(
      type: matrix.EventTypes.Message,
      content: {"msgtype": "m.text", "body": body},
      senderId: "@bob:example.com",
      eventId: "\$m${_n++}",
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1700000100000 + _n),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test("a sync while the room opens is mirrored once", () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();

    final historyAsked = Completer<void>();
    final history = Completer<void>();
    final server = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith("/sync")) {
        await Future.delayed(const Duration(seconds: 5));
        return _json({"next_batch": "idle"});
      }
      if (path.endsWith("/filter")) return _json({"filter_id": "f"});
      if (path.endsWith("/versions")) {
        return _json({
          "versions": ["v1.11"]
        });
      }
      if (path.endsWith("/messages")) {
        if (!historyAsked.isCompleted) historyAsked.complete();
        await history.future;
        return _json({"chunk": [], "start": "p", "end": "p2"});
      }
      return _json({});
    });
    final database =
        await MatrixSdkDriftDatabase.init(NativeDatabase.memory(), "open-sync");
    final client = http.runWithClient(
        () => MatrixClient(identifier: "open-sync", database: database),
        () => server);
    final mx = client.getMatrixClient();
    await mx.init(
      newToken: "token",
      newHomeserver: Uri.parse("https://example.com"),
      newUserID: me,
      newDeviceID: "DEVICE",
      newDeviceName: "test",
      waitForFirstSync: false,
    );
    // A room with no stored messages: opening it asks for history.
    await sync(client, join: {
      roomId: matrix.JoinedRoomUpdate(
          state: roomState(roomId),
          timeline: matrix.TimelineUpdate(events: [], prevBatch: "p")),
    });

    final errors = <Object>[];
    final room = client.getRoom(roomId) as MatrixRoom;
    late Future<void> open;
    await runZonedGuarded(() async {
      open = room.getTimeline(holder: Object());
      await historyAsked.future;
      // While the open waits for history: new messages, then a limited
      // sync (a gap fill) that drops what isn't in it.
      await sync(client, join: {
        roomId: matrix.JoinedRoomUpdate(
            timeline: matrix.TimelineUpdate(
                events: [message("one"), message("two")], prevBatch: "p")),
      });
      await sync(client, join: {
        roomId: matrix.JoinedRoomUpdate(
            timeline: matrix.TimelineUpdate(
                events: [message("three")], limited: true, prevBatch: "q")),
      });
      history.complete();
      await open;
      await pumpEventQueue();
    }, (error, _) => errors.add(error));

    expect(errors, isEmpty);
    final timeline = room.timeline as MatrixTimeline;
    final sdkIds = timeline.matrixTimeline!.events.map((e) => e.eventId);
    final ids = timeline.events.map((e) => e.eventId).toList();
    expect(ids.toSet().length, ids.length, reason: "no event shown twice");
    expect(ids, sdkIds.toList(), reason: "the view mirrors the SDK timeline");
    expect(ids, isNotEmpty);

    await mx.dispose(closeDatabase: true);
  });
}
