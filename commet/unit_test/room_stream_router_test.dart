// Vommet: RoomStreamRouter hands each client stream item to its room only.
import 'package:commet/client/matrix/room_stream_router.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Client client;
  setUp(() async {
    client = Client("router-test",
        database: await MatrixSdkDriftDatabase.init(
            NativeDatabase.memory(), "router test"));
  });

  StrippedStateEvent topic(String text) => StrippedStateEvent(
      type: EventTypes.RoomTopic,
      content: {"topic": text},
      senderId: "@bob:example.org",
      stateKey: "");

  test("state changes reach their own room only, in order", () async {
    final router = RoomStreamRouter.of(client);
    expect(identical(RoomStreamRouter.of(client), router), isTrue);
    final a = <String>[];
    final b = <String>[];
    router
        .roomState("!a:x")
        .listen((u) => a.add(u.state.content["topic"] as String));
    router
        .roomState("!b:x")
        .listen((u) => b.add(u.state.content["topic"] as String));

    client.onRoomState.add((roomId: "!a:x", state: topic("a1")));
    client.onRoomState.add((roomId: "!b:x", state: topic("b1")));
    client.onRoomState.add((roomId: "!c:x", state: topic("nobody")));
    client.onRoomState.add((roomId: "!a:x", state: topic("a2")));
    await Future.delayed(Duration.zero);
    await Future.delayed(Duration.zero);

    expect(a, ["a1", "a2"]);
    expect(b, ["b1"]);
  });

  test("a sync reaches every joined room it carries, and only those", () async {
    final router = RoomStreamRouter.of(client);
    final got = <String, int>{};
    for (final id in ["!a:x", "!b:x", "!c:x"]) {
      router.joinedSyncs(id).listen((_) => got[id] = (got[id] ?? 0) + 1);
    }
    client.onSync.add(SyncUpdate(
        nextBatch: "1",
        rooms: RoomsUpdate(join: {
          "!a:x": JoinedRoomUpdate(),
          "!b:x": JoinedRoomUpdate(),
        })));
    client.onSync.add(SyncUpdate(nextBatch: "2"));
    await Future.delayed(Duration.zero);
    await Future.delayed(Duration.zero);

    expect(got, {"!a:x": 1, "!b:x": 1});
  });
}
