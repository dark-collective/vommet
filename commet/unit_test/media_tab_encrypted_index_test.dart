// Vommet: the Media and Files tabs of an encrypted room page the encrypted
// search index (one local query a screenful) instead of the timeline,
// scanning older history into the index where it hasn't reached yet, and
// fall back to the timeline where there's no index or it's Off.
import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/room_media_history/room_media_history_component.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_store.dart';
import 'package:commet/client/matrix/components/room_media_history/index_media_history.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/encrypted_search_index_setting.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart' show roomState, signedInClient, stateEvent, sync;

const plain = "!plain:example.com";
const secret = "!secret:example.com";
const alice = "@alice:example.com";

Map<String, dynamic> msg(String id, int ts, Map<String, dynamic> content,
        {String type = "m.room.message"}) =>
    {
      "type": type,
      "event_id": id,
      "sender": alice,
      "origin_server_ts": ts,
      "room_id": secret,
      "content": content,
    };

/// A decrypted encrypted picture, as the index keeps it.
Map<String, dynamic> picture(String id, int ts, {String? body}) => msg(id, ts, {
      "msgtype": "m.image",
      "body": body ?? "$id.png",
      "file": {
        "url": "mxc://example.com/$id",
        "v": "v2",
        "key": {"k": "x"},
        "iv": "x",
        "hashes": {"sha256": "x"},
      },
      "info": {"mimetype": "image/png"},
    });

Map<String, dynamic> document(String id, int ts) => msg(id, ts, {
      "msgtype": "m.file",
      "body": "$id.pdf",
      "file": {
        "url": "mxc://example.com/$id",
        "v": "v2",
        "key": {"k": "x"},
        "iv": "x",
        "hashes": {"sha256": "x"},
      },
      "info": {"mimetype": "application/pdf"},
    });

Map<String, dynamic> text(String id, int ts) =>
    msg(id, ts, {"msgtype": "m.text", "body": "hi $id"});

Map<String, dynamic> redaction(String id, int ts, String target) =>
    {...msg(id, ts, {}, type: "m.room.redaction"), "redacts": target};

Map<String, dynamic> rename(String id, int ts, String target, String body) =>
    msg(id, ts, {
      "msgtype": "m.image",
      "body": "* $body",
      "m.new_content": {
        ...(picture(target, ts)["content"] as Map<String, dynamic>),
        "body": body,
      },
      "m.relates_to": {"rel_type": "m.replace", "event_id": target},
    });

/// The index over an in-memory store; [server] is the room's history,
/// newest first, scanned [pageSize] messages a step the way the component
/// pages /messages (tokens are offsets into [server]).
class FakeIndex implements MediaHistoryIndex {
  FakeIndex(this.server, {this.pageSize = 4});

  final SearchIndexStore store = SearchIndexStore.openInMemory();
  final List<Map<String, dynamic>> server;
  final int pageSize;
  int scans = 0;
  bool stalled = false;

  @override
  Future<RoomCoverage> prepare(String roomId) async {
    store.ensureRoom(roomId);
    return store.coverage(roomId);
  }

  @override
  Future<List<IndexHit>> list(String roomId,
          {Set<SharedContentKind> kinds = const {},
          bool linksOnly = false,
          int? beforeTs,
          String? beforeEventId,
          int limit = 100}) async =>
      store.list(roomId,
          kinds: kinds,
          linksOnly: linksOnly,
          beforeTs: beforeTs,
          beforeEventId: beforeEventId,
          limit: limit);

  @override
  Future<IndexStepResult> indexOlder(String roomId) async {
    scans++;
    final segment = store.nextSegment(roomId);
    if (segment == null || stalled) {
      return IndexStepResult(added: 0, coverage: store.coverage(roomId));
    }
    final from = int.parse(segment.fromToken ?? "0");
    final page = server.skip(from).take(pageSize).toList();
    final to = from + page.length;
    final result = store.applyPage(
        roomId, segment.id, page, to >= server.length ? null : "$to");
    return IndexStepResult(added: result.added, coverage: result.coverage);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test("tokens: the last message given out, ties by event id", () {
    final hit = IndexHit(
        eventId: r"$a:b", ts: 5, kind: SharedContentKind.image, json: const {});
    expect(IndexMediaHistory.tokenOf(hit), r"idx:5:$a:b");
    expect(IndexMediaHistory.parse(r"idx:5:$a:b"), (5, r"$a:b"));
    expect(IndexMediaHistory.parse("idx:"), isNull);
    expect(IndexMediaHistory.parse(null), isNull);
    expect(IndexMediaHistory.parse("t1"), isNull);
  });

  test("the store lists past messages sharing a timestamp", () {
    final store = SearchIndexStore.openInMemory();
    store.ensureRoom(secret);
    store.addLive(secret, [
      picture(r"$a", 10),
      picture(r"$b", 10),
      picture(r"$c", 10),
      picture(r"$d", 9),
    ]);
    List<String> ids(List<IndexHit> hits) => [for (final h in hits) h.eventId];
    expect(ids(store.list(secret, limit: 2)), [r"$c", r"$b"]);
    expect(
        ids(store.list(secret, beforeTs: 10, beforeEventId: r"$b", limit: 2)),
        [r"$a", r"$d"]);
    expect(ids(store.list(secret, beforeTs: 10)), [r"$d"]);
  });

  group("index pages", () {
    late MatrixClient client;
    var n = 0;

    setUp(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
      client = await signedInClient("media-index-${n++}");
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

    IndexMediaHistory pagerOver(FakeIndex index) {
      final r = room(secret);
      return IndexMediaHistory(index, secret,
          convert: (json) =>
              r.convertEvent(matrix.Event.fromJson(json, r.matrixRoom)));
    }

    /// Every page until the start of the room.
    Future<List<RoomMediaPage>> walk(IndexMediaHistory pager,
        {String? from, int limit = 2}) async {
      final pages = <RoomMediaPage>[];
      do {
        final page = await pager.loadPage(from, limit: limit);
        pages.add(page);
        from = page.next;
        expect(pages.length, lessThan(50), reason: "never reaches the start");
      } while (from != null);
      return pages;
    }

    List<String> idsOf(Iterable<RoomMediaPage> pages) =>
        [for (final p in pages) ...p.events.map((e) => e.eventId)];

    test("newest first; scans older history when the index runs out", () async {
      final index = FakeIndex([
        picture(r"$p9", 900),
        text(r"$t8", 800),
        document(r"$f7", 700),
        text(r"$t6", 600),
        picture(r"$p5", 500),
        text(r"$t4", 400),
        text(r"$t3", 300),
        picture(r"$p2", 200),
        picture(r"$p1", 100),
      ]);
      final pager = pagerOver(index);

      final first = await pager.loadPage(null, limit: 2);
      expect(first.events.map((e) => e.eventId), [r"$p9", r"$f7"]);
      expect(first.events.first, isA<TimelineEventMessage>());
      expect(first.next, r"idx:700:$f7");
      // One step of 4 messages held both.
      expect(index.scans, 1);

      final rest = await walk(pager, from: first.next);
      expect(idsOf([first, ...rest]), [r"$p9", r"$f7", r"$p5", r"$p2", r"$p1"]);
      expect(rest.last.next, isNull);
      expect(index.store.coverage(secret).upToDate, isTrue);
    });

    test("a long stretch without files: an empty page that carries on",
        () async {
      final index = FakeIndex(
          [for (var i = 20; i > 0; i--) text("\$t$i", i * 10)]
            ..add(picture(r"$p0", 1)),
          pageSize: 2);
      final pager = pagerOver(index);

      final first = await pager.loadPage(null, limit: 5);
      expect(first.events, isEmpty);
      expect(first.next, "idx:", reason: "not the start of the room");
      expect(index.scans, IndexMediaHistory.maxScansPerPage);

      final pages = await walk(pager, limit: 5);
      expect(idsOf(pages), [r"$p0"]);
      expect(pages.last.next, isNull);
    });

    test("an index that stops getting further falls back (throws)", () async {
      final index = FakeIndex([text(r"$t1", 10), picture(r"$p0", 1)])
        ..stalled = true;
      await expectLater(pagerOver(index).loadPage(null),
          throwsA(isA<IndexMediaHistoryStalled>()));
    });

    test("files that arrived while closed are scanned first, from the top",
        () async {
      final server = [
        picture(r"$p3", 300),
        picture(r"$p2", 200),
        picture(r"$p1", 100),
      ];
      final index = FakeIndex(server, pageSize: 10);
      final pager = pagerOver(index);
      final first = await pager.loadPage(null, limit: 1);
      expect(first.events.single.eventId, r"$p3");
      expect(index.store.coverage(secret).upToDate, isTrue);

      // The app was closed while a picture arrived; on start the index
      // adds a scan from the newest down to what it covers.
      server.insert(0, picture(r"$p4", 400));
      index.store.addTopSegment(secret);

      final next = await pager.loadPage(first.next, limit: 2);
      expect(next.events.map((e) => e.eventId), [r"$p4", r"$p3"],
          reason: "started over from the newest");
      final rest = await walk(pager, from: next.next);
      final seen = {
        ...idsOf([first, next, ...rest])
      };
      expect(seen, {r"$p4", r"$p3", r"$p2", r"$p1"});
    });

    test("deleted files drop out; renamed files show the new name", () async {
      final index = FakeIndex([
        redaction(r"$r", 500, r"$p2"),
        rename(r"$e", 400, r"$p3", "holiday.png"),
        picture(r"$p3", 300),
        picture(r"$p2", 200),
        picture(r"$p1", 100),
      ]);
      final pages = await walk(pagerOver(index), limit: 10);
      expect(idsOf(pages), [r"$p3", r"$p1"]);
      final renamed = pages.first.events.first as TimelineEventMessage;
      expect(renamed.attachments!.single.name, "holiday.png");
    });

    test("merged with the timeline: one entry per file, newest first",
        () async {
      final index = FakeIndex([
        picture(r"$p3", 300),
        document(r"$f2", 200),
        picture(r"$p1", 100),
      ]);
      final paged = [
        for (final page in await walk(pagerOver(index)))
          ...page.events.cast<TimelineEventMessage>()
      ];
      final r = room(secret);
      final inTimeline = r.convertEvent(
              matrix.Event.fromJson(picture(r"$p3", 300), r.matrixRoom))
          as TimelineEventMessage;
      (List<RoomAttachment>, List<RoomAttachment>) entriesOf(
              TimelineEventMessage event) =>
          (
            [
              for (final a in event.attachments ?? const [])
                if (a is ImageAttachment) (event, a)
            ],
            [
              for (final a in event.attachments ?? const [])
                if (a is FileAttachment && a is! ImageAttachment) (event, a)
            ],
          );
      final (media, files) = entriesOf(inTimeline);
      // ignore: invalid_use_of_visible_for_testing_member
      RoomAttachmentFeed.mergePaged(
          media: media,
          files: files,
          paged: paged,
          skip: {r"$p3"},
          entriesOf: entriesOf);
      expect(media.map((e) => e.$1.eventId), [r"$p3", r"$p1"]);
      expect(files.map((e) => e.$1.eventId), [r"$f2"]);
    });

    test("encrypted rooms use the index unless it's Off", () async {
      final history = room(secret).getComponent<RoomMediaHistoryComponent>()!;
      await encryptedIndexModePreference.set(EncryptedIndexMode.always.key);
      expect(history.available, isTrue);

      await encryptedIndexModePreference.set(EncryptedIndexMode.off.key);
      expect(history.available, isFalse, reason: "the tabs page the timeline");
      await expectLater(history.loadPage(null), throwsStateError);

      // Unencrypted rooms keep the server's filtered pages either way.
      expect(room(plain).getComponent<RoomMediaHistoryComponent>()!.available,
          isTrue);
    });
  });
}
