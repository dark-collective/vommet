// Vommet: a signed-in MatrixClient whose homeserver is a stub, for tests that
// drive the room list with sync updates the way a server would. Shared by
// roomlist_index_test.dart and roomlist_benchmark_test.dart.
import 'dart:async';
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

/// What `/rooms/{id}/context/{eventId}` returns for an event id; null (the
/// default) answers with an empty context. Vommet issue 1057's far jump test
/// sets it to serve the history around a message the timeline hasn't loaded.
Map<String, Object?>? Function(String eventId)? contextResponse;

/// What `/search` returns for a request's url (its `next_batch` query
/// parameter); null (the default) answers with no results.
FutureOr<Map<String, Object?>?> Function(Uri url)? searchResponse;

/// What `/rooms/{id}/messages` returns for a request's url (its `from`
/// query parameter); null (the default, also as an answer) leaves it to the
/// generic `{}`.
FutureOr<Map<String, Object?>?> Function(Uri url)? messagesResponse;

/// Answers a request before the defaults below; null (the default, also as
/// an answer) leaves it to them. The voice message send test uses it for the
/// media upload.
FutureOr<http.Response?> Function(http.Request request)? stubResponse;

http.Client stubServer(
        [FutureOr<http.Response?> Function(http.Request)? respond]) =>
    MockClient((request) async {
      final response = await respond?.call(request);
      if (response != null) return response;
      final custom = await stubResponse?.call(request);
      if (custom != null) return custom;
      final path = request.url.path;
      final messages = messagesResponse;
      if (messages != null && path.endsWith("/messages")) {
        return _json(await messages(request.url) ?? {});
      }
      if (path.endsWith("/search")) {
        return _json(await searchResponse?.call(request.url) ?? {});
      }
      if (path.contains("/context/")) {
        final id = Uri.decodeComponent(path.split("/").last);
        return _json(contextResponse?.call(id) ?? {});
      }
      if (path.endsWith("/sync")) {
        // Keep the background sync loop idle.
        await Future.delayed(const Duration(seconds: 5));
        return _json({"next_batch": "idle"});
      }
      if (path.endsWith("/filter")) return _json({"filter_id": "f"});
      if (path.contains("/send/")) {
        final id = path.split("/").last;
        return _json({"event_id": "\$sent-$id", "delay_id": "delay-$id"});
      }
      if (path.endsWith("/hierarchy")) return _json({"rooms": []});
      if (path.endsWith("/versions")) {
        return _json({
          "versions": ["v1.11"]
        });
      }
      return _json({});
    });

Future<MatrixClient> signedInClient(String name,
    {FutureOr<http.Response?> Function(http.Request)? respond}) async {
  final database =
      await MatrixSdkDriftDatabase.init(NativeDatabase.memory(), name);
  final client = http.runWithClient(
      () => MatrixClient(identifier: name, database: database),
      () => stubServer(respond));
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
