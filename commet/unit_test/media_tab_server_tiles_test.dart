// Vommet: the Media tab's tiles in unencrypted rooms are the server's
// thumbnail of the original at the tile's size (a picture without a sender
// thumbnail used to download the whole original for a ~300 px tile), and
// its Media/Files history comes from server-filtered /messages pages.
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/room_media_history/room_media_history_component.dart';
import 'package:commet/client/matrix/components/room_media_history/matrix_room_media_history_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_media_failures.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/encrypted_search_index_setting.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart' show me, roomState, stateEvent, sync;

const plain = "!plain:example.com";
const secret = "!secret:example.com";

final png = Uint8List.fromList(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D]);

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {"content-type": "application/json"});

Map<String, Object?> picture(String id,
        {Map<String, Object?>? info, bool encrypted = false, int ts = 1}) =>
    {
      "type": "m.room.message",
      "event_id": id,
      "sender": me,
      "origin_server_ts": 1700000000000 + ts,
      "content": {
        "msgtype": "m.image",
        "body": "$id.png",
        if (encrypted)
          "file": {
            "url": "mxc://example.com/$id",
            "v": "v2",
            "key": {"k": "x"},
            "iv": "x",
            "hashes": {"sha256": "x"},
          }
        else
          "url": "mxc://example.com/${id.substring(1)}",
        "info": {"mimetype": "image/png", ...?info},
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group("tile sources", () {
    test("a picture with a sender thumbnail: server, then sender", () {
      expect(
          MatrixServerTileImage.steps(
              mimetype: "image/jpeg",
              hasSenderThumbnail: true,
              fileSize: 1600000),
          [TileSource.server, TileSource.sender]);
    });

    test("no sender thumbnail, big original: server only, never the original",
        () {
      expect(
          MatrixServerTileImage.steps(
              mimetype: "image/png", hasSenderThumbnail: false, fileSize: null),
          [TileSource.server]);
      expect(
          MatrixServerTileImage.steps(
              mimetype: "image/png",
              hasSenderThumbnail: false,
              fileSize: 2 * 1024 * 1024),
          [TileSource.server]);
    });

    test("a small original is the last resort", () {
      expect(
          MatrixServerTileImage.steps(
              mimetype: "image/png",
              hasSenderThumbnail: true,
              fileSize: 200 * 1024),
          [TileSource.server, TileSource.sender, TileSource.smallOriginal]);
    });

    test("small GIFs stay animated; SVG skips the server", () {
      expect(
          MatrixServerTileImage.steps(
              mimetype: "image/gif", hasSenderThumbnail: false, fileSize: 1000),
          [TileSource.smallOriginal, TileSource.server]);
      expect(
          MatrixServerTileImage.steps(
              mimetype: "image/gif",
              hasSenderThumbnail: false,
              fileSize: 4000000),
          [TileSource.server]);
      expect(
          MatrixServerTileImage.steps(
              mimetype: "image/svg+xml",
              hasSenderThumbnail: false,
              fileSize: 3000),
          [TileSource.smallOriginal]);
    });
  });

  group("matrix", () {
    late MatrixClient client;
    late List<http.Request> requests;
    late http.Response Function(http.Request) thumbnailAnswer;
    late List<http.Response> messagePages;
    var n = 0;

    setUp(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
      MatrixMediaFailures.instance = MatrixMediaFailures();
      requests = [];
      messagePages = [];
      thumbnailAnswer = (_) =>
          http.Response.bytes(png, 200, headers: {"content-type": "image/png"});
      final server = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith("/sync")) {
          await Future.delayed(const Duration(seconds: 5));
          return _json({"next_batch": "idle"});
        }
        if (path.contains("/media/thumbnail/")) {
          requests.add(request);
          return thumbnailAnswer(request);
        }
        if (path.contains("/media/download/")) {
          requests.add(request);
          return http.Response.bytes(png, 200,
              headers: {"content-type": "image/png"});
        }
        if (path.endsWith("/messages")) {
          requests.add(request);
          return messagePages.removeAt(0);
        }
        if (path.endsWith("/filter")) return _json({"filter_id": "f"});
        if (path.endsWith("/versions")) {
          return _json({
            "versions": ["v1.11"]
          });
        }
        return _json({});
      });
      final name = "media-tiles-${n++}";
      final database =
          await MatrixSdkDriftDatabase.init(NativeDatabase.memory(), name);
      client = http.runWithClient(
          () => MatrixClient(identifier: name, database: database),
          () => server);
      await client.getMatrixClient().init(
            newToken: "token",
            newHomeserver: Uri.parse("https://example.com"),
            newUserID: me,
            newDeviceID: "DEVICE",
            newDeviceName: "test",
            waitForFirstSync: false,
          );
      await sync(client, join: {
        plain: matrix.JoinedRoomUpdate(state: roomState(plain)),
        secret: matrix.JoinedRoomUpdate(state: [
          ...roomState(secret),
          stateEvent(
              "m.room.encryption", {"algorithm": "m.megolm.v1.aes-sha2"}),
        ]),
      });
    });

    tearDown(() => client.getMatrixClient().dispose(closeDatabase: true));

    MatrixRoom room(String id) => client.getRoom(id) as MatrixRoom;

    ImageAttachment attachmentOf(String roomId, Map<String, Object?> json) {
      final r = room(roomId);
      final event = r.convertEvent(matrix.Event.fromJson(json, r.matrixRoom))
          as TimelineEventMessage;
      return event.attachments!.single as ImageAttachment;
    }

    test("unencrypted picture: the tile is the server's cropped thumbnail",
        () async {
      final image = attachmentOf(plain, picture(r"$a")).image;
      final tile = (image as MatrixMxcImage).forTile(300);
      expect(tile, isA<MatrixServerTileImage>());
      final serverTile = tile as MatrixServerTileImage;
      expect(serverTile.size, 384);
      expect(serverTile.autoLoadFullRes, isFalse);

      final bytes = await serverTile.loadThumbnail!();
      expect(bytes, png);
      final thumb = requests.single.url;
      expect(thumb.path, "/_matrix/client/v1/media/thumbnail/example.com/a");
      expect(thumb.queryParameters,
          {"width": "384", "height": "384", "method": "crop"});
      // Only ever a cached original: nothing is downloaded for the tile.
      expect(await serverTile.loadFullRes!(), isNull);
      expect(requests, hasLength(1));
      // The viewer still gets the original.
      expect(serverTile.forViewer(), isNot(isA<MatrixServerTileImage>()));
    });

    test("server refuses, no sender thumbnail, big original: blurhash stays",
        () async {
      thumbnailAnswer = (_) =>
          _json({"errcode": "M_UNKNOWN", "error": "Cannot thumbnail"}, 400);
      final tile = (attachmentOf(plain, picture(r"$b", info: {"size": 1600000}))
              .image as MatrixMxcImage)
          .forTile(300) as MatrixServerTileImage;
      expect(await tile.loadThumbnail!(), isNull);
      expect(requests.where((r) => r.url.path.contains("/download/")), isEmpty);
    });

    test("server refuses: the sender's thumbnail, then a small original",
        () async {
      thumbnailAnswer = (request) => request.url.path.endsWith("/c")
          ? _json({"errcode": "M_NOT_FOUND", "error": "x"}, 404)
          : http.Response.bytes(png, 200,
              headers: {"content-type": "image/png"});
      final withThumb = (attachmentOf(
              plain,
              picture(r"$c", info: {
                "size": 1600000,
                "thumbnail_url": "mxc://example.com/cthumb",
                "thumbnail_info": {"mimetype": "image/png"},
              })).image as MatrixMxcImage)
          .forTile(300) as MatrixServerTileImage;
      expect(await withThumb.loadThumbnail!(), png);
      expect(requests.last.url.path, endsWith("/cthumb"));

      thumbnailAnswer =
          (_) => _json({"errcode": "M_NOT_FOUND", "error": "x"}, 404);
      requests.clear();
      final small = (attachmentOf(plain, picture(r"$d", info: {"size": 40000}))
              .image as MatrixMxcImage)
          .forTile(300) as MatrixServerTileImage;
      expect(await small.loadThumbnail!(), png);
      expect(requests.last.url.path,
          "/_matrix/client/v1/media/download/example.com/d");
    });

    test("encrypted pictures keep the shared tile (no server thumbnail)", () {
      final image = attachmentOf(secret, picture(r"$e", encrypted: true)).image;
      expect((image as MatrixMxcImage).tileEvent, isNull);
      expect(image.forTile(300), isNot(isA<MatrixServerTileImage>()));
    });

    test("filtered pages: contains_url filter, tokens, start of the room",
        () async {
      final pager = room(plain).getComponent<RoomMediaHistoryComponent>()!;
      expect(pager.available, isTrue);
      // Encrypted rooms page the search index instead
      // (media_tab_encrypted_index_test.dart), or the timeline when it's Off.
      await encryptedIndexModePreference.set(EncryptedIndexMode.off.key);
      expect(room(secret).getComponent<RoomMediaHistoryComponent>()!.available,
          isFalse);

      messagePages = [
        _json({
          "start": "s0",
          "end": "t1",
          "chunk": [picture(r"$p2", ts: 2), picture(r"$p1", ts: 1)]
        }),
        _json({"start": "t1", "chunk": []}),
      ];
      final first = await pager.loadPage(null, limit: 50);
      expect(first.events.map((e) => e.eventId), [r"$p2", r"$p1"]);
      expect(first.events.first, isA<TimelineEventMessage>());
      expect(first.next, "t1");
      final query = requests.single.url.queryParameters;
      expect(query["dir"], "b");
      expect(query["limit"], "50");
      expect(query.containsKey("from"), isFalse);
      expect(jsonDecode(query["filter"]!), {
        "contains_url": true,
        "types": ["m.room.message"],
        "lazy_load_members": true,
      });
      expect(MatrixRoomMediaHistoryComponent.filter, query["filter"]);

      final second = await pager.loadPage("t1");
      expect(second.events, isEmpty);
      expect(second.next, isNull);
      expect(requests.last.url.queryParameters["from"], "t1");
    });
  });
}
