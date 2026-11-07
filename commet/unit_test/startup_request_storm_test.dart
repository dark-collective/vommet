// Vommet: a large account's start sent thousands of background requests:
// the encrypted search index paged /messages every 250 ms from the first
// second (and each sync cut that pause short). See also
// matrix_http_client_test.dart.
import 'dart:convert';

import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_store.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_backend_io.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _room = "!storm:example.com";
const _alice = "@alice:example.com";

Map<String, dynamic> _text(String id, int ts) => {
      "type": "m.room.message",
      "event_id": id,
      "sender": _alice,
      "origin_server_ts": ts,
      "room_id": _room,
      "content": {"msgtype": "m.text", "body": "message $id"},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group("search index pacing", () {
    test("rests at least the pause, and twice what a page took", () {
      final pause = MatrixEncryptedSearchIndexComponent.pagePause;
      expect(pause, greaterThanOrEqualTo(const Duration(seconds: 1)));
      expect(
          MatrixEncryptedSearchIndexComponent.pauseAfter(
              const Duration(milliseconds: 50)),
          pause);
      expect(
          MatrixEncryptedSearchIndexComponent.pauseAfter(
              const Duration(seconds: 3)),
          const Duration(seconds: 6));
    });

    late MatrixClient client;
    late MatrixEncryptedSearchIndexComponent index;
    final requests = <DateTime>[];
    final startDelay = MatrixEncryptedSearchIndexComponent.startDelay;

    http.Response json(Object body) => http.Response(jsonEncode(body), 200,
        headers: {"content-type": "application/json"});

    var n = 0;
    setUp(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
      requests.clear();
      final server = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith("/sync")) {
          await Future.delayed(const Duration(seconds: 5));
          return json({"next_batch": "idle"});
        }
        if (path.endsWith("/messages")) {
          requests.add(DateTime.now());
          final page = requests.length;
          // Endless history: each page leads to an older one.
          return json({
            "start": "t$page",
            "end": "t${page + 1}",
            "chunk": [
              _text("\$a$page", 100000 - page * 2),
              _text("\$b$page", 100000 - page * 2 - 1),
            ],
          });
        }
        if (path.endsWith("/versions")) {
          return json({
            "versions": ["v1.11"]
          });
        }
        return json({});
      });
      final name = "storm-test-${n++}";
      final database =
          await MatrixSdkDriftDatabase.init(NativeDatabase.memory(), name);
      client = http.runWithClient(
          () => MatrixClient(identifier: name, database: database),
          () => server);
      final mx = client.getMatrixClient();
      await mx.init(
        newToken: "token",
        newHomeserver: Uri.parse("https://example.com"),
        newUserID: _alice,
        newDeviceID: "DEVICE",
        newDeviceName: "test",
        waitForFirstSync: false,
      );
      await mx.handleSync(matrix.SyncUpdate(
          nextBatch: "b0",
          rooms: matrix.RoomsUpdate(join: {
            _room: matrix.JoinedRoomUpdate(state: [
              matrix.MatrixEvent(
                  type: "m.room.encryption",
                  content: {"algorithm": "m.megolm.v1.aes-sha2"},
                  stateKey: "",
                  senderId: _alice,
                  eventId: "\$enc",
                  originServerTs: DateTime.fromMillisecondsSinceEpoch(1)),
              matrix.MatrixEvent(
                  type: "m.room.member",
                  content: {"membership": "join"},
                  stateKey: _alice,
                  senderId: _alice,
                  eventId: "\$join",
                  originServerTs: DateTime.fromMillisecondsSinceEpoch(1)),
            ])
          })));
      index = MatrixEncryptedSearchIndexComponent(client,
          backend: WorkerSearchIndexBackend.inProcess(
              SearchIndexStore.openInMemory()));
    });

    var wasHeadless = isHeadless;

    tearDown(() async {
      MatrixEncryptedSearchIndexComponent.startDelay = startDelay;
      isHeadless = wasHeadless;
      await index.onClientClosed();
      await client.getMatrixClient().dispose(closeDatabase: true);
    });

    test("the background backfill waits for the start, then paces itself",
        () async {
      MatrixEncryptedSearchIndexComponent.startDelay =
          const Duration(milliseconds: 600);
      final started = DateTime.now();
      wasHeadless = isHeadless;
      isHeadless = false;
      index.postLoginInit();

      // Syncs keep coming meanwhile; they must not hurry the backfill.
      final mx = client.getMatrixClient();
      for (var i = 0; i < 25; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        mx.onSync.add(matrix.SyncUpdate(nextBatch: "s$i"));
      }

      expect(requests, isNotEmpty);
      expect(requests.first.difference(started),
          greaterThanOrEqualTo(const Duration(milliseconds: 500)));
      for (var i = 1; i < requests.length; i++) {
        expect(requests[i].difference(requests[i - 1]),
            greaterThanOrEqualTo(const Duration(milliseconds: 900)));
      }
      // ~2.5 s: the first page after 0.6 s, then one a second at most.
      expect(requests.length, lessThanOrEqualTo(4));
    });
  });

  test("thumbnails download a few at a time", () {
    expect(MatrixMxcImage.maxThumbnailRequests, 6);
  });
}
