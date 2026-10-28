// Vommet issue 581: a sync saves a partial room's deferred state (here its
// m.room.topic) to the database only and leaves it to the deferred state
// load. A load started while that sync is still being saved has to see it,
// or the room is marked loaded without its topic until the next start.
// MatrixSdkDatabase's sqflite store behaves like the web build's IndexedDB
// store here: writes in a transaction are held until it ends, and reads made
// outside it don't wait for it.
import 'dart:async';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("deferred state load waits for the sync being saved", () async {
    final database = await MatrixSdkDatabase.init(
      "postload during sync test",
      database: await databaseFactoryFfi.openDatabase(":memory:",
          options: OpenDatabaseOptions(singleInstance: false)),
      sqfliteFactory: databaseFactoryFfi,
    );
    final client = Client("postload-during-sync-test", database: database);
    const roomId = "!new:example.com";
    // A room the sync just added: its deferred state isn't loaded yet.
    final room = Room(id: roomId, client: client);
    expect(room.partial, isTrue);

    final written = Completer<void>();
    final finishSync = Completer<void>();
    final sync = database.transaction(() async {
      await database.storeRoomUpdate(roomId, JoinedRoomUpdate(), null, client);
      await database.storeEventUpdate(
        roomId,
        MatrixEvent.fromJson({
          "type": EventTypes.RoomTopic,
          "content": {"topic": "Fresh topic"},
          "event_id": "\$topic:example.com",
          "sender": "@bob:example.org",
          "state_key": "",
          "origin_server_ts": DateTime.now().millisecondsSinceEpoch,
        }),
        EventUpdateType.state,
        client,
      );
      written.complete();
      await finishSync.future;
    });

    await written.future;
    // The app queues the load as soon as it sees the new room, while the
    // sync is still being saved.
    final load = MatrixClient.postLoadRooms(client, [room]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    finishSync.complete();
    await sync;
    expect(await load, 1);

    expect(room.partial, isFalse);
    expect(room.topic, "Fresh topic");
    await database.close();
  });
}
