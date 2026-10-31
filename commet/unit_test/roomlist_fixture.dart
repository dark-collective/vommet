// Vommet: a signed-in MatrixClient whose homeserver is a stub, for tests that
// drive the room list with sync updates the way a server would. Shared by
// roomlist_index_test.dart and roomlist_benchmark_test.dart.
import 'dart:convert';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

const me = "@me:example.com";

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {"content-type": "application/json"});

http.Client stubServer() => MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith("/sync")) {
        // Keep the background sync loop idle.
        await Future.delayed(const Duration(seconds: 5));
        return _json({"next_batch": "idle"});
      }
      if (path.endsWith("/filter")) return _json({"filter_id": "f"});
      if (path.endsWith("/hierarchy")) return _json({"rooms": []});
      if (path.endsWith("/versions")) {
        return _json({
          "versions": ["v1.11"]
        });
      }
      return _json({});
    });

Future<MatrixClient> signedInClient(String name) async {
  final database =
      await MatrixSdkDriftDatabase.init(NativeDatabase.memory(), name);
  final client = http.runWithClient(
      () => MatrixClient(identifier: name, database: database), stubServer);
  await client.getMatrixClient().init(
        newToken: "token",
        newHomeserver: Uri.parse("https://example.com"),
        newUserID: me,
        newDeviceID: "DEVICE",
        newDeviceName: "test",
        waitForFirstSync: false,
      );
  return client;
}

int _n = 0;

matrix.MatrixEvent stateEvent(String type, Map<String, Object?> content,
        {String stateKey = "", String sender = me}) =>
    matrix.MatrixEvent(
      type: type,
      content: content,
      stateKey: stateKey,
      senderId: sender,
      eventId: "\$e${_n++}",
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1700000000000 + _n),
    );

/// State for a room we're joined to; a space when [children] is given.
List<matrix.MatrixEvent> roomState(String id,
        {List<String>? children, String? name}) =>
    [
      stateEvent("m.room.create", {
        "creator": me,
        if (children != null) "type": "m.space",
      }),
      stateEvent("m.room.member", {"membership": "join"}, stateKey: me),
      if (name != null) stateEvent("m.room.name", {"name": name}),
      for (final child in children ?? const <String>[])
        stateEvent(
            "m.space.child",
            {
              "via": ["example.com"]
            },
            stateKey: child),
    ];

matrix.JoinedRoomUpdate joined(String id,
        {List<String>? children, String? name}) =>
    matrix.JoinedRoomUpdate(
        state: roomState(id, children: children, name: name));

/// Our membership leaving the room: "leave" or "ban".
matrix.LeftRoomUpdate left(String membership) => matrix.LeftRoomUpdate(
        timeline: matrix.TimelineUpdate(events: [
      stateEvent("m.room.member", {"membership": membership},
          stateKey: me, sender: "@mod:example.com"),
    ]));

int _batch = 0;

Future<void> sync(
  MatrixClient client, {
  Map<String, matrix.JoinedRoomUpdate>? join,
  Map<String, matrix.LeftRoomUpdate>? leave,
  Map<String, matrix.InvitedRoomUpdate>? invite,
  List<matrix.BasicEvent>? accountData,
}) async {
  await client.getMatrixClient().handleSync(matrix.SyncUpdate(
        nextBatch: "b${_batch++}",
        rooms: matrix.RoomsUpdate(join: join, leave: leave, invite: invite),
        accountData: accountData,
      ));
  // The client reacts to the SDK's onSync event, which is delivered later.
  await Future<void>.delayed(Duration.zero);
  // New rooms load their remaining state in the background; let that land
  // so it can't race the next update.
  await client.startupLoadsDone;
}

matrix.BasicEvent directChats(Map<String, List<String>> byUser) =>
    matrix.BasicEvent(type: "m.direct", content: byUser);
