// Vommet: what one "fake" sync costs the app on an account the size of a
// tester's (1,800 rooms, 1,200 encrypted, 88 spaces). The SDK sends one after
// each batch of key backup sessions it imports (to show the newly decrypted
// last messages); after a fresh sign-in + approval the app stalled ~10 s at a
// time while that import ran. Prints timings; asserts nothing about them.
import 'dart:async';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

const roomCount = 1800;
const encryptedCount = 1200;
const spaceCount = 88;
const roomsPerSpace = 12;

String roomId(int i) => "!room$i:example.com";
String spaceId(int i) => "!space$i:example.com";

class _LoopWatch {
  final _sw = Stopwatch();
  Timer? _timer;
  int _last = 0;
  int worst = 0;

  void start() {
    _sw.start();
    _timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
      final now = _sw.elapsedMilliseconds;
      final gap = now - _last - 2;
      if (gap > worst) worst = gap;
      _last = now;
    });
  }

  int stop() {
    _timer?.cancel();
    return _sw.elapsedMilliseconds;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient("fake-sync-scale");
    final setup = Stopwatch()..start();
    await sync(
      client,
      join: {
        for (var s = 0; s < spaceCount; s++)
          spaceId(s): joined(
            spaceId(s),
            children: [
              for (var r = 0; r < roomsPerSpace; r++)
                roomId((s * roomsPerSpace + r) % roomCount),
            ],
          ),
        for (var r = 0; r < roomCount; r++)
          roomId(r): matrix.JoinedRoomUpdate(
            state: [
              ...roomState(roomId(r), name: "Room $r"),
              if (r < encryptedCount)
                stateEvent("m.room.encryption", {
                  "algorithm": "m.megolm.v1.aes-sha2",
                }),
            ],
          ),
      },
    );
    debugPrint(
      "BENCH setup sync of ${roomCount + spaceCount} rooms: "
      "${setup.elapsedMilliseconds} ms",
    );
  });

  tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

  Future<void> fakeSync(int rooms, String label) async {
    final mx = client.getMatrixClient();
    final watch = _LoopWatch()..start();
    final clock = Stopwatch()..start();
    // What KeyManager._storeDecryptedLastEvents sends.
    await mx.database.transaction(() async {
      await mx.handleSync(
        matrix.SyncUpdate(
          nextBatch: '',
          rooms: matrix.RoomsUpdate(
            join: {
              for (var r = 0; r < rooms; r++)
                roomId(r): matrix.JoinedRoomUpdate(),
            },
          ),
        ),
      );
    });
    final handled = clock.elapsedMilliseconds;
    await Future<void>.delayed(Duration.zero);
    await client.startupLoadsDone;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final total = watch.stop();
    debugPrint(
      "BENCH fake sync $label ($rooms rooms of $roomCount): "
      "handleSync ${handled} ms, settled ${total - 50} ms, "
      "worst loop stall ${watch.worst} ms",
    );
  }

  test("fake syncs at tester scale", () async {
    expect(client.rooms.length, roomCount);
    await fakeSync(1, "warm-up");
    for (final n in [1, 1, 10, 50, 250, 250, 1200]) {
      await fakeSync(n, "");
    }
    // A plain sync with nothing in it, for comparison.
    final watch = _LoopWatch()..start();
    await sync(client);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    debugPrint(
      "BENCH empty real sync: settled ${watch.stop() - 50} ms, "
      "worst loop stall ${watch.worst} ms",
    );
  }, timeout: const Timeout(Duration(minutes: 20)));
}
