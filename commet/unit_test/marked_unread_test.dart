// Vommet issue 366: "mark as unread" is room account data that nothing
// cleared when the room was read, so a room marked unread in another client
// kept its unread dot after reading it, across restarts too.
import 'dart:convert';

import 'package:commet/client/matrix/matrix_marked_unread.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

const roomId = "!room:example.com";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Client client;
  late List<http.Request> accountDataWrites;

  setUp(() async {
    accountDataWrites = [];
    final http = MockClient((request) async {
      if (request.url.path.contains("/account_data/")) {
        accountDataWrites.add(request);
      }
      if (request.url.path.endsWith("/sync")) {
        // Keep the background sync loop idle.
        await Future.delayed(const Duration(seconds: 5));
        return _json({"next_batch": "s1"});
      }
      if (request.url.path.endsWith("/filter")) {
        return _json({"filter_id": "f"});
      }
      if (request.url.path.endsWith("/versions")) {
        return _json({
          "versions": ["v1.11"]
        });
      }
      return _json({});
    });
    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), "marked unread test");
    client = Client("marked-unread-test", database: database, httpClient: http);
    await client.init(
      newToken: "token",
      newHomeserver: Uri.parse("https://example.com"),
      newUserID: "@me:example.com",
      newDeviceID: "DEVICE",
      newDeviceName: "test",
      waitForFirstSync: false,
    );
  });

  tearDown(() => client.dispose(closeDatabase: true));

  Future<Room> joinRoom({Map<String, Object?>? accountData}) async {
    await client.handleSync(SyncUpdate(
      nextBatch: "s0",
      rooms: RoomsUpdate(join: {
        roomId: JoinedRoomUpdate(accountData: [
          for (final entry in (accountData ?? {}).entries)
            BasicEvent(
                type: entry.key, content: {"unread": entry.value as bool}),
        ]),
      }),
    ));
    return client.getRoomById(roomId)!;
  }

  test("reading a room marked unread in another client clears the mark",
      () async {
    final room = await joinRoom(accountData: {"m.marked_unread": true});
    expect(room.markedUnread, isTrue);

    // The read marker and receipt alone leave the mark set: the dot stayed.
    await room.setReadMarker(r"$last", mRead: r"$last");
    expect(room.markedUnread, isTrue);
    accountDataWrites.clear();

    await clearMarkedUnread(room);

    expect(room.markedUnread, isFalse);
    expect(room.isUnread, isFalse);
    final write = accountDataWrites.single;
    expect(write.method, "PUT");
    expect(Uri.decodeComponent(write.url.path),
        endsWith("/rooms/$roomId/account_data/m.marked_unread"));
    expect(jsonDecode(write.body), {"unread": false});
  });

  test("FluffyChat's older flag is cleared too", () async {
    final room =
        await joinRoom(accountData: {"com.famedly.marked_unread": true});
    expect(room.markedUnread, isTrue);

    await clearMarkedUnread(room);

    expect(room.markedUnread, isFalse);
    expect(accountDataWrites, hasLength(1));
  });

  test("a room that isn't marked unread sends nothing", () async {
    final room = await joinRoom(accountData: {"m.marked_unread": false});

    await clearMarkedUnread(room);
    await clearMarkedUnread(await joinRoom());

    expect(room.markedUnread, isFalse);
    expect(accountDataWrites, isEmpty);
  });
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {"content-type": "application/json"});
