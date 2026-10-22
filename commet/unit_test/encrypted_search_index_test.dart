// Vommet (issues 602, 611): the encrypted search index: what it keeps of an
// event, its coverage segments (each stretch of history scanned once),
// queries and counts, and the component paging a room through /messages.
import 'dart:convert';

import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_store.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_backend_io.dart';
import 'package:commet/client/matrix/components/event_search/matrix_event_search_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
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

const room = "!r:example.com";
const alice = "@alice:example.com";
const bob = "@bob:example.com";

Map<String, dynamic> msg(String id, int ts, Map<String, dynamic> content,
        {String sender = alice, String type = "m.room.message"}) =>
    {
      "type": type,
      "event_id": id,
      "sender": sender,
      "origin_server_ts": ts,
      "room_id": room,
      "content": content,
    };

Map<String, dynamic> text(String id, int ts, String body,
        {String sender = alice}) =>
    msg(id, ts, {"msgtype": "m.text", "body": body}, sender: sender);

Map<String, dynamic> file(String id, int ts, String msgtype, String mimetype,
        {Map<String, dynamic> extra = const {}}) =>
    msg(id, ts, {
      "msgtype": msgtype,
      "body": "file-$id",
      "url": "mxc://example.com/$id",
      "info": {"mimetype": mimetype},
      ...extra,
    });

Map<String, dynamic> edit(String id, int ts, String target, String body,
        {String sender = alice}) =>
    msg(
        id,
        ts,
        {
          "msgtype": "m.text",
          "body": "* $body",
          "m.new_content": {"msgtype": "m.text", "body": body},
          "m.relates_to": {"rel_type": "m.replace", "event_id": target},
        },
        sender: sender);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group("IndexExtract", () {
    SharedContentKind? kind(Map<String, dynamic> e) =>
        (IndexExtract.of(e) as IndexEventExtract?)?.event.kind;

    test("sorts messages into the Shared kinds", () {
      expect(kind(text("\$1", 1, "hi")), SharedContentKind.text);
      expect(kind(file("\$2", 1, "m.image", "image/png")),
          SharedContentKind.image);
      expect(
          kind(file("\$3", 1, "m.image", "image/gif")), SharedContentKind.gif);
      expect(kind(file("\$4", 1, "m.video", "video/mp4")),
          SharedContentKind.video);
      // A picture sent as a file counts as a photo, as the timeline shows it.
      expect(kind(file("\$5", 1, "m.file", "image/jpeg")),
          SharedContentKind.image);
      expect(kind(file("\$6", 1, "m.file", "application/pdf")),
          SharedContentKind.file);
      expect(
          kind(file("\$7", 1, "m.audio", "audio/ogg",
              extra: {"org.matrix.msc3245.voice": {}})),
          SharedContentKind.voice);
      expect(kind(file("\$8", 1, "m.audio", "audio/mpeg")),
          SharedContentKind.audio);
      expect(
          kind(msg("\$9", 1, {"body": "s", "url": "mxc://x/y"},
              type: "m.sticker")),
          SharedContentKind.sticker);
    });

    test("finds links in text, without trailing punctuation", () {
      final e = (IndexExtract.of(text(
                  "\$1", 1, "see https://example.org/a. and http://x.y/b)"))
              as IndexEventExtract)
          .event;
      expect(e.links, ["https://example.org/a", "http://x.y/b"]);
      expect(e.searchText, contains("see https"));
    });

    test("ignores state, reactions and redacted or encrypted events", () {
      expect(
          IndexExtract.of({...text("\$1", 1, "x"), "state_key": ""}), isNull);
      expect(IndexExtract.of(msg("\$2", 1, {}, type: "m.reaction")), isNull);
      expect(IndexExtract.of(msg("\$3", 1, {})), isNull);
      expect(
          IndexExtract.of(
              msg("\$4", 1, {"ciphertext": "x"}, type: "m.room.encrypted")),
          isNull);
    });

    test("reads edits and redactions", () {
      expect(IndexExtract.of(edit("\$2", 2, "\$1", "New")),
          isA<IndexEditExtract>());
      final r = IndexExtract.of({
        ...msg("\$3", 3, {}, type: "m.room.redaction"),
        "redacts": "\$1",
      });
      expect((r as IndexRedaction).targetId, "\$1");
    });
  });

  group("SearchIndexStore", () {
    late SearchIndexStore store;
    setUp(() => store = SearchIndexStore.openInMemory());
    tearDown(() => store.dispose());

    test("a new room has one backfill segment from the newest message", () {
      expect(store.coverage(room).known, isFalse);
      store.ensureRoom(room);
      store.ensureRoom(room);
      final seg = store.nextSegment(room)!;
      expect(seg.fromToken, isNull);
      expect(seg.stopTs, isNull);
      expect(store.coverage(room).pendingSegments, 1);
    });

    test("the backfill pages back and completes at the start of the room", () {
      store.ensureRoom(room);
      var seg = store.nextSegment(room)!;
      var r = store.applyPage(
          room, seg.id, [text("\$3", 300, "c"), text("\$2", 200, "b")], "t1");
      expect(r.added, 2);
      expect(r.segmentDone, isFalse);
      expect(store.coverage(room).headTs, 300);
      expect(store.coverage(room).oldestTs, 200);

      seg = store.nextSegment(room)!;
      expect(seg.fromToken, "t1");
      r = store.applyPage(room, seg.id, [text("\$1", 100, "a")], null);
      expect(r.segmentDone, isTrue);
      expect(r.coverage.complete, isTrue);
      expect(r.coverage.upToDate, isTrue);
      expect(r.coverage.oldestTs, 100);
      expect(store.nextSegment(room), isNull);
      expect(store.completeCount([room, "!other:x"]), 1);
    });

    test("a top segment stops at what's already covered", () {
      store.ensureRoom(room);
      store.applyPage(
          room, store.nextSegment(room)!.id, [text("\$1", 100, "a")], null);
      store.addTopSegment(room);
      store.addTopSegment(room); // only one waits at a time
      expect(store.coverage(room).pendingSegments, 1);
      expect(store.coverage(room).complete, isTrue);
      expect(store.coverage(room).upToDate, isFalse);

      final seg = store.nextSegment(room)!;
      expect(seg.stopTs, 100);
      final r = store.applyPage(
          room, seg.id, [text("\$3", 300, "c"), text("\$2", 200, "b")], "t9");
      expect(r.segmentDone, isFalse);
      final r2 = store.applyPage(
          room, store.nextSegment(room)!.id, [text("\$1", 100, "a")], "t10");
      expect(r2.segmentDone, isTrue);
      expect(r2.added, 0);
      expect(r2.coverage.upToDate, isTrue);
      expect(r2.coverage.headTs, 300);
    });

    test("a limited sync's gap is scanned before the backfill", () {
      store.ensureRoom(room);
      store.applyPage(
          room, store.nextSegment(room)!.id, [text("\$5", 500, "e")], "old");
      store.addGapSegment(room, "gap");
      final seg = store.nextSegment(room)!;
      expect(seg.fromToken, "gap");
      expect(seg.stopTs, 500);
      expect(store.nextRoom(["!a:x", room]), room);
    });

    test("nextRoom prefers rooms with recent gaps", () {
      store.ensureRoom("!a:x");
      store.ensureRoom("!b:x");
      store.applyPage(
          "!b:x", store.nextSegment("!b:x")!.id, [text("\$b", 1, "x")], "t");
      store.addGapSegment("!b:x", "gap");
      expect(store.nextRoom(["!a:x", "!b:x"]), "!b:x");
      expect(store.nextRoom(["!a:x"]), "!a:x");
      expect(store.nextRoom([]), isNull);
    });

    test("search: half the words, filters, newest first", () {
      store.addLive(room, [
        text("\$1", 100, "Pizza tonight at Luigi's"),
        text("\$2", 200, "no pizza for me", sender: bob),
        text("\$3", 300, "see https://example.org"),
        file("\$4", 400, "m.image", "image/png"),
      ]);
      List<String> ids(IndexQuery q, {int? beforeTs}) => [
            for (final h in store.search(room, q, beforeTs: beforeTs)) h.eventId
          ];

      expect(ids(const IndexQuery(words: ["pizza"])), ["\$2", "\$1"]);
      expect(
          ids(const IndexQuery(words: ["pizza", "luigi's"])), ["\$2", "\$1"]);
      expect(ids(const IndexQuery(words: ["pizza", "luigi's", "tonight"])),
          ["\$1"]);
      expect(ids(const IndexQuery(words: ["pizza"], senderId: bob)), ["\$2"]);
      expect(ids(const IndexQuery(requireLink: true)), ["\$3"]);
      expect(ids(const IndexQuery(requireImage: true)), ["\$4"]);
      expect(ids(const IndexQuery(requireAttachment: true)), ["\$4"]);
      expect(ids(const IndexQuery(type: "m.image")), ["\$4"]);
      expect(ids(const IndexQuery(words: ["pizza"]), beforeTs: 200), ["\$1"]);
      expect(store.search("!other:x", const IndexQuery(words: ["pizza"])),
          isEmpty);
      // Results carry the decrypted event for display.
      expect(
          store
              .search(room, const IndexQuery(words: ["luigi"]))
              .single
              .json["content"]["body"],
          "Pizza tonight at Luigi's");
    });

    test("edits replace the text (own edits only, even when seen first)", () {
      // Backwards paging sees the edit before the original.
      store.addLive(room, [
        edit("\$2", 200, "\$1", "lasagna instead"),
        edit("\$3", 300, "\$1", "hacked", sender: bob),
        text("\$1", 100, "pizza"),
      ]);
      expect(store.search(room, const IndexQuery(words: ["pizza"])), isEmpty);
      final hit =
          store.search(room, const IndexQuery(words: ["lasagna"])).single;
      expect(hit.eventId, "\$1");
      expect(hit.json["content"]["body"], "lasagna instead");
      expect(store.search(room, const IndexQuery(words: ["hacked"])), isEmpty);

      // A newer own edit wins, an older one doesn't.
      store.addLive(room, [edit("\$4", 400, "\$1", "risotto")]);
      store.addLive(room, [edit("\$5", 150, "\$1", "older")]);
      expect(
          store.search(room, const IndexQuery(words: ["risotto"])).length, 1);
      expect(store.search(room, const IndexQuery(words: ["older"])), isEmpty);
    });

    test("redactions remove messages, also ones indexed later", () {
      store.addLive(room, [text("\$1", 100, "secret")]);
      final redaction = {
        ...msg("\$r", 200, {}, type: "m.room.redaction"),
        "redacts": "\$1"
      };
      store.addLive(room, [redaction]);
      expect(store.search(room, const IndexQuery(words: ["secret"])), isEmpty);

      store.addLive(room, [
        {...msg("\$r2", 300, {}, type: "m.room.redaction"), "redacts": "\$9"},
        text("\$9", 50, "also secret"),
      ]);
      expect(store.search(room, const IndexQuery(words: ["secret"])), isEmpty);
    });

    test("counts and lists per kind", () {
      store.addLive(room, [
        file("\$1", 1, "m.image", "image/png"),
        file("\$2", 2, "m.image", "image/gif"),
        file("\$3", 3, "m.video", "video/mp4"),
        file("\$4", 4, "m.file", "application/pdf"),
        file("\$5", 5, "m.audio", "audio/ogg",
            extra: {"org.matrix.msc3245.voice": {}}),
        file("\$6", 6, "m.audio", "audio/mpeg"),
        text("\$7", 7, "https://a.example https://b.example"),
      ]);
      final c = store.counts(room);
      expect(c.photosAndVideos, 2);
      expect(c.gifs, 1);
      expect(c.filesAndAudio, 2);
      expect(c.voice, 1);
      expect(c.links, 2);

      expect([
        for (final h in store.list(room,
            kinds: {SharedContentKind.image, SharedContentKind.video}))
          h.eventId
      ], [
        "\$3",
        "\$1"
      ]);
      final links = store.list(room, linksOnly: true).single;
      expect(links.links, ["https://a.example", "https://b.example"]);
      expect(store.list(room, kinds: {SharedContentKind.gif}, beforeTs: 2),
          isEmpty);
    });

    test("undecrypted events wait, then join once they decrypt", () {
      store.ensureRoom(room);
      final encrypted =
          msg("\$1", 100, {"ciphertext": "x"}, type: "m.room.encrypted");
      store.applyPage(room, store.nextSegment(room)!.id, [], "t",
          undecrypted: [encrypted]);
      expect(store.roomsWithUndecrypted(), [room]);
      expect(store.undecrypted(room).single["event_id"], "\$1");
      store.addDecrypted(room, [text("\$1", 100, "now readable")]);
      expect(store.roomsWithUndecrypted(), isEmpty);
      expect(
          store.search(room, const IndexQuery(words: ["readable"])).length, 1);
    });

    test("deleteRoom and clear forget everything", () {
      store.ensureRoom(room);
      store.addLive(room, [text("\$1", 1, "a")]);
      store.addLive("!b:x", [text("\$2", 1, "a")]);
      store.deleteRoom(room);
      expect(store.coverage(room).known, isFalse);
      expect(store.search(room, const IndexQuery()), isEmpty);
      expect(store.search("!b:x", const IndexQuery()).length, 1);
      store.clear();
      expect(store.search("!b:x", const IndexQuery()), isEmpty);
    });
  });

  test("setting: Always on desktop, Wi-Fi only on phones; unknown = default",
      () {
    expect(EncryptedIndexMode.fromKey("off"), EncryptedIndexMode.off);
    expect(EncryptedIndexMode.fromKey("wifi"), EncryptedIndexMode.wifiOnly);
    expect(EncryptedIndexMode.fromKey("always"), EncryptedIndexMode.always);
    expect(
        EncryptedIndexMode.fromKey("nonsense"), EncryptedIndexMode.defaultMode);
    // Unit tests run as desktop.
    expect(EncryptedIndexMode.defaultMode, EncryptedIndexMode.always);
  });

  test("MatrixSearchParameters.toIndexQuery lowercases words, keeps filters",
      () {
    final q =
        MatrixSearchParameters.parse("Pizza  from:@bob:example.com has:image")
            .toIndexQuery();
    expect(q.words, ["pizza"]);
    expect(q.senderId, bob);
    expect(q.requireImage, isTrue);
  });

  group("component", () {
    late MatrixClient client;
    late MatrixEncryptedSearchIndexComponent index;
    final requests = <String?>[];

    // History of the room, newest first, two pages.
    final page1 = [
      text("\$4", 400, "newest"),
      text("\$3", 300, "pizza later"),
    ];
    final page2 = [
      text("\$2", 200, "pizza first"),
      text("\$1", 100, "oldest"),
    ];

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
          final from = request.url.queryParameters["from"];
          requests.add(from);
          return from == null
              ? json({"start": "s", "end": "t1", "chunk": page1})
              : json({"start": "t1", "chunk": page2});
        }
        if (path.endsWith("/versions")) {
          return json({
            "versions": ["v1.11"]
          });
        }
        return json({});
      });
      final name = "index-test-${n++}";
      final database =
          await MatrixSdkDriftDatabase.init(NativeDatabase.memory(), name);
      client = http.runWithClient(
          () => MatrixClient(identifier: name, database: database),
          () => server);
      final mx = client.getMatrixClient();
      await mx.init(
        newToken: "token",
        newHomeserver: Uri.parse("https://example.com"),
        newUserID: alice,
        newDeviceID: "DEVICE",
        newDeviceName: "test",
        waitForFirstSync: false,
      );
      await mx.handleSync(matrix.SyncUpdate(
          nextBatch: "b0",
          rooms: matrix.RoomsUpdate(join: {
            room: matrix.JoinedRoomUpdate(state: [
              matrix.MatrixEvent(
                  type: "m.room.encryption",
                  content: {"algorithm": "m.megolm.v1.aes-sha2"},
                  stateKey: "",
                  senderId: alice,
                  eventId: "\$enc",
                  originServerTs: DateTime.fromMillisecondsSinceEpoch(1)),
              matrix.MatrixEvent(
                  type: "m.room.member",
                  content: {"membership": "join"},
                  stateKey: alice,
                  senderId: alice,
                  eventId: "\$join",
                  originServerTs: DateTime.fromMillisecondsSinceEpoch(1)),
            ])
          })));
      index = MatrixEncryptedSearchIndexComponent(client,
          backend: WorkerSearchIndexBackend.inProcess(
              SearchIndexStore.openInMemory()),
          startBackground: false);
    });

    tearDown(() async {
      await index.onClientClosed();
      await client.getMatrixClient().dispose(closeDatabase: true);
    });

    test("indexOlder pages the room once, then search needs no network",
        () async {
      expect(index.encryptedRoomIds(), [room]);
      var step = await index.indexOlder(room);
      expect(step.added, 2);
      expect(step.coverage.complete, isFalse);
      step = await index.indexOlder(room);
      expect(step.coverage.upToDate, isTrue);
      expect(requests, [null, "t1"]);

      final hits = await index.search(room, const IndexQuery(words: ["pizza"]));
      expect([for (final h in hits) h.eventId], ["\$3", "\$2"]);

      // Done: another call doesn't fetch anything.
      step = await index.indexOlder(room);
      expect(step.added, 0);
      expect(requests, [null, "t1"]);
    });

    test("the search session pages back while the room isn't indexed",
        () async {
      final timeline = await client.getRoom(room)!.getTimeline();
      final session = MatrixIndexedRoomEventSearchSession(
          timeline as MatrixTimeline, index);
      final results = await session.startSearch("pizza").last;
      expect([for (final e in results) e.eventId], ["\$3", "\$2"]);
      expect(session.canContinueSearch, isFalse);
      expect(session.progress.value.complete, isTrue);
      expect(session.progress.value.found, 2);
      expect(session.progress.value.searchedBackTo,
          DateTime.fromMillisecondsSinceEpoch(100));
    });
  });
}
