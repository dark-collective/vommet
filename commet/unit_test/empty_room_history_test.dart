// Vommet issue 945: some rooms opened with an empty timeline, and "Load older
// messages" loaded nothing. The room was joined, but nothing of it was stored
// and it had no prev_batch (as sliding sync can leave a room it sent without
// events). The SDK kept saying history could be loaded, yet each request did
// nothing. The timeline now pages back from the room's newest event.
import 'dart:convert';

import 'package:commet/client/matrix/empty_room_history.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

const _me = "@me:example.com";
const _roomId = "!room:remote.example";

Map<String, Object?> _event(String id, int ts,
        {String type = EventTypes.Message,
        String sender = "@bob:remote.example",
        String? stateKey,
        Map<String, Object?>? content}) =>
    {
      "event_id": id,
      "type": type,
      "sender": sender,
      "origin_server_ts": ts,
      "room_id": _roomId,
      if (stateKey != null) "state_key": stateKey,
      "content": content ?? {"msgtype": "m.text", "body": id},
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {"content-type": "application/json"});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Client client;
  // The `from` of each history request ("" for none). Not the one-event
  // requests that refresh the room's preview.
  late List<String> requests;
  // Answers by `from`.
  late Map<String, Map<String, Object?>> pages;

  setUp(() async {
    requests = [];
    pages = {};
    final http = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith("/messages")) {
        final from = request.url.queryParameters["from"] ?? "";
        if (request.url.queryParameters["limit"] != "1") requests.add(from);
        final page = pages[from] ?? {"chunk": [], "start": from};
        return _json(page, page.containsKey("errcode") ? 500 : 200);
      }
      if (path.endsWith("/sync")) {
        await Future.delayed(const Duration(seconds: 5));
        return _json({"next_batch": "s1"});
      }
      if (path.endsWith("/filter")) return _json({"filter_id": "f"});
      if (path.endsWith("/versions")) {
        return _json({
          "versions": ["v1.11"]
        });
      }
      return _json({});
    });
    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), "empty room history test");
    client =
        Client("empty-room-history-test", database: database, httpClient: http);
    await client.init(
      newToken: "token",
      newHomeserver: Uri.parse("https://example.com"),
      newUserID: _me,
      newDeviceID: "DEVICE",
      newDeviceName: "test",
      waitForFirstSync: false,
    );
  });

  tearDown(() => client.dispose(closeDatabase: true));

  /// A joined room sync sent with its state but no events or prev_batch.
  Future<Room> joinWithoutEvents({String? prevBatch}) async {
    await client.handleSync(SyncUpdate(
      nextBatch: "s0",
      rooms: RoomsUpdate(join: {
        _roomId: JoinedRoomUpdate(
          state: [
            MatrixEvent.fromJson(_event("\$member", 1000,
                type: EventTypes.RoomMember,
                sender: _me,
                stateKey: _me,
                content: {"membership": "join"})),
          ],
          timeline: prevBatch == null
              ? null
              : TimelineUpdate(events: [], prevBatch: prevBatch),
        ),
      }),
    ));
    final room = client.getRoomById(_roomId)!;
    expect(room.membership, Membership.join);
    expect(room.prev_batch, prevBatch);
    return room;
  }

  final newest = {
    "chunk": [
      _event("\$m3", 4000),
      _event("\$m2", 3000),
      _event("\$m1", 2000),
    ],
    "start": "head",
    "end": "t1",
  };
  final start = {
    "chunk": [
      _event("\$create", 1000,
          type: EventTypes.RoomCreate, stateKey: "", content: {}),
    ],
    "start": "t1",
    // Synapse sends one more token; the page after it is empty.
    "end": "t2",
  };

  List<String> ids(Timeline timeline) =>
      timeline.events.map((e) => e.eventId).toList();

  test("the SDK alone never loads such a room, yet keeps offering to",
      () async {
    final room = await joinWithoutEvents();
    pages[""] = newest;
    final timeline = await room.getTimeline();

    for (var i = 0; i < 3; i++) {
      expect(timeline.canRequestHistory, isTrue);
      await timeline.requestHistory();
    }
    expect(timeline.events, isEmpty);
    expect(requests, isEmpty);
  });

  test("pages back from the newest event, then on from its token", () async {
    final room = await joinWithoutEvents();
    pages[""] = newest;
    pages["t1"] = start;
    final timeline = await room.getTimeline();
    final history = EmptyRoomHistory();

    expect(history.canRequest(timeline), isTrue);
    history.beforeRequest(timeline);
    await timeline.requestHistory();
    expect(ids(timeline), ["\$m3", "\$m2", "\$m1"]);
    expect(room.prev_batch, "t1");

    expect(history.canRequest(timeline), isTrue);
    history.beforeRequest(timeline);
    await timeline.requestHistory();
    expect(ids(timeline), ["\$m3", "\$m2", "\$m1", "\$create"]);
    expect(requests, ["", "t1"]);
    expect(history.canRequest(timeline), isFalse);

    // Stored: the room opens with them next time.
    final reopened = await room.getTimeline();
    expect(ids(reopened), ["\$m3", "\$m2", "\$m1", "\$create"]);
    expect((await room.refreshLastEvent())?.eventId, "\$m3");
  });

  test("a room the server has nothing for stops asking", () async {
    final room = await joinWithoutEvents();
    final timeline = await room.getTimeline();
    final history = EmptyRoomHistory();

    history.beforeRequest(timeline);
    await timeline.requestHistory();
    expect(timeline.events, isEmpty);
    expect(requests, [""]);
    expect(history.canRequest(timeline), isFalse);

    // The view only asks while history can be loaded; asking anyway goes
    // nowhere.
    history.beforeRequest(timeline);
    await timeline.requestHistory();
    expect(requests, [""]);
  });

  test("a failed request from the newest event is tried again", () async {
    final room = await joinWithoutEvents();
    final timeline = await room.getTimeline();
    final history = EmptyRoomHistory();
    pages[""] = {"errcode": "M_UNKNOWN", "error": "x"};

    history.beforeRequest(timeline);
    await expectLater(timeline.requestHistory(), throwsA(anything));
    expect(history.canRequest(timeline), isTrue);

    pages[""] = newest;
    history.beforeRequest(timeline);
    await timeline.requestHistory();
    expect(ids(timeline), ["\$m3", "\$m2", "\$m1"]);
    expect(requests, ["", ""]);
    // The room's preview is refreshed from the newest event too.
    expect((await room.refreshLastEvent())?.eventId, "\$m3");
  });

  test("a room with a token pages from it as before", () async {
    final room = await joinWithoutEvents(prevBatch: "t1");
    pages["t1"] = start;
    final timeline = await room.getTimeline();
    final history = EmptyRoomHistory();

    history.beforeRequest(timeline);
    await timeline.requestHistory();
    expect(ids(timeline), ["\$create"]);
    expect(requests, ["t1"]);
  });
}
