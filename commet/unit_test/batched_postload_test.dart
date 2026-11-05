// Vommet: MatrixClient.postLoadRooms loads several rooms' deferred state with
// one query at startup; it must leave each room as Room.postLoad would.
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test("batched deferred state load matches Room.postLoad", () async {
    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), "batched postload test");
    final client = Client("batched-postload-test", database: database);
    final ids = ["!a:example.com", "!b:example.com", "!c:example.com"];
    for (final (i, id) in ids.indexed) {
      await database.storeRoomUpdate(id, JoinedRoomUpdate(), null, client);
      // m.room.topic isn't preloaded, so it waits for the deferred load.
      // The last room has none.
      if (i == ids.length - 1) continue;
      await database.storeEventUpdate(
        id,
        MatrixEvent.fromJson({
          "type": EventTypes.RoomTopic,
          "content": {"topic": "topic $i"},
          "event_id": "\$topic$i:example.com",
          "sender": "@bob:example.org",
          "state_key": "",
          "origin_server_ts": DateTime.now().millisecondsSinceEpoch,
        }),
        EventUpdateType.timeline,
        client,
      );
    }

    final batched = [for (final id in ids) Room(id: id, client: client)];
    final single = [for (final id in ids) Room(id: id, client: client)];
    expect(await MatrixClient.postLoadRooms(client, batched), ids.length);
    for (final room in single) {
      await room.postLoad();
    }

    for (var i = 0; i < ids.length; i++) {
      expect(batched[i].partial, isFalse);
      expect(batched[i].topic, single[i].topic, reason: ids[i]);
    }
    expect(batched[1].topic, "topic 1");
    expect(batched[2].topic, "");
  });
}
