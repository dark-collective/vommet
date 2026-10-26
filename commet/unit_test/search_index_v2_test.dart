// Vommet Deep Search: the search index v2: the v1 → v2 migration keeps the
// stored rows, full-text search (FTS5, trigram for CJK) across rooms with
// filters, ranking and caps, reply fallbacks stripped, coverage totals,
// and a speed check on a larger synthetic index.
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const me = "@me:example.com";
const alice = "@alice:example.com";
const bob = "@bob:example.com";
const roomA = "!a:example.com";
const roomB = "!b:example.com";
const dm = "!dm:example.com";

const day = Duration.millisecondsPerDay;
final now = DateTime.utc(2026, 10, 26).millisecondsSinceEpoch;

Map<String, dynamic> msg(String id, String room, int ts, String body,
        {String sender = alice, Map<String, dynamic> extra = const {}}) =>
    {
      "type": "m.room.message",
      "event_id": id,
      "sender": sender,
      "origin_server_ts": ts,
      "room_id": room,
      "content": {"msgtype": "m.text", "body": body, ...extra},
    };

Map<String, dynamic> reply(
        String id, String room, int ts, String quoted, String body) =>
    msg(id, room, ts, "> <@bob:example.com> $quoted\n\n$body", extra: {
      "m.relates_to": {
        "m.in_reply_to": {"event_id": "\$quoted"}
      }
    });

List<String> ids(IndexSearchResult r) => [for (final h in r.hits) h.eventId];

IndexSearchResult find(SearchIndexStore s, String words,
        {List<String>? roomIds,
        IndexRanking ranking = const IndexRanking(newestFirst: true),
        int cap = SearchIndexStore.candidateCap}) =>
    s.searchAll(
        IndexQuery(
            words: words.split(" ").where((w) => w.isNotEmpty).toList(),
            roomIds: roomIds),
        ranking: ranking,
        cap: cap);

/// Writes a version 1 index (as shipped before Deep Search) with [events].
void writeV1(String path, List<Map<String, dynamic>> events) {
  final db = sqlite3.open(path);
  db.execute("""
    CREATE TABLE events(
      event_id TEXT PRIMARY KEY, room_id TEXT NOT NULL,
      sender TEXT NOT NULL, ts INTEGER NOT NULL, type TEXT NOT NULL,
      msgtype TEXT, mimetype TEXT, kind INTEGER NOT NULL,
      search_text TEXT NOT NULL, edit_text TEXT, edit_ts INTEGER,
      edit_content TEXT, links TEXT, link_count INTEGER NOT NULL,
      json TEXT NOT NULL);
    CREATE INDEX events_room_ts ON events(room_id, ts DESC);
    CREATE INDEX events_room_kind ON events(room_id, kind, ts DESC);
    CREATE TABLE edits(
      target_id TEXT NOT NULL, room_id TEXT NOT NULL,
      sender TEXT NOT NULL, ts INTEGER NOT NULL,
      search_text TEXT NOT NULL, content TEXT NOT NULL,
      PRIMARY KEY(target_id, sender));
    CREATE TABLE redacted(event_id TEXT PRIMARY KEY, room_id TEXT NOT NULL);
    CREATE TABLE undecrypted(
      event_id TEXT PRIMARY KEY, room_id TEXT NOT NULL,
      ts INTEGER NOT NULL, json TEXT NOT NULL);
    CREATE INDEX undecrypted_room ON undecrypted(room_id);
    CREATE TABLE rooms(
      room_id TEXT PRIMARY KEY, head_ts INTEGER, oldest_ts INTEGER,
      complete INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE segments(
      id INTEGER PRIMARY KEY AUTOINCREMENT, room_id TEXT NOT NULL,
      from_token TEXT, stop_ts INTEGER,
      started INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX segments_room ON segments(room_id);
    PRAGMA user_version = 1;
  """);
  for (final e in events) {
    final content = e["content"] as Map;
    // v1 kept the whole body, reply fallback included.
    final text = (content["body"] as String).toLowerCase();
    db.execute(
        "INSERT INTO events(event_id, room_id, sender, ts, type, msgtype, "
        "kind, search_text, link_count, json) "
        "VALUES (?, ?, ?, ?, 'm.room.message', 'm.text', 0, ?, 0, ?)",
        [
          e["event_id"],
          e["room_id"],
          e["sender"],
          e["origin_server_ts"],
          text,
          jsonEncode(e),
        ]);
  }
  db.execute("INSERT INTO rooms VALUES (?, ?, ?, 1)", [roomA, now, now - day]);
  db.dispose();
}

void main() {
  group("v1 → v2 migration", () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync("index_v2_"));
    tearDown(() => dir.deleteSync(recursive: true));

    test("keeps every row, then fills the full-text index", () {
      final path = p.join(dir.path, "search_index.db");
      writeV1(path, [
        msg("\$1", roomA, now - 3 * day, "teapot recipe from grandma"),
        reply("\$2", roomA, now - 2 * day, "teapot recipe from grandma",
            "thanks!"),
        msg("\$3", roomB, now - day, "hey @me:example.com look", extra: {
          "m.relates_to": {"rel_type": "m.thread", "event_id": "\$root"}
        }),
      ]);

      final store = SearchIndexStore.open(path, ownUserId: me);
      expect(store.db.select("PRAGMA user_version").first.values.first, 2);
      expect(store.db.select("SELECT count(*) AS n FROM events").first["n"], 3);
      expect(store.coverage(roomA).complete, isTrue);
      expect(store.pendingMigration(), 3);

      // Before the background step: still found (instr), quoted reply too.
      expect(find(store, "teapot").hits.length, 2);

      expect(store.migrateStep(limit: 2), 1);
      expect(store.migrateStep(), 0);
      expect(store.pendingMigration(), 0);

      // After: the reply's quoted fallback no longer matches.
      expect(ids(find(store, "teapot")), ["\$1"]);
      expect(ids(find(store, "thanks")), ["\$2"]);
      final mention = store.searchAll(const IndexQuery(mentionsMe: true));
      expect(ids(mention), ["\$3"]);
      expect(mention.hits.single.threadRoot, "\$root");
      final replyHit =
          store.searchAll(const IndexQuery(words: ["thanks"])).hits.single;
      expect(replyHit.isReply, isTrue);
      store.dispose();

      // Opening again doesn't migrate twice.
      final again = SearchIndexStore.open(path, ownUserId: me);
      expect(again.pendingMigration(), 0);
      expect(ids(find(again, "grandma")), ["\$1"]);
      again.dispose();
    });

    test("a reader connection sees what the writer stored", () {
      final path = p.join(dir.path, "search_index.db");
      final writer = SearchIndexStore.open(path, ownUserId: me);
      writer.addLive(roomA, [msg("\$1", roomA, now, "kettle on")]);
      final reader = SearchIndexStore.openReader(path, ownUserId: me);
      expect(reader.hasFullText, isTrue);
      expect(ids(find(reader, "kettle")), ["\$1"]);
      reader.dispose();
      writer.dispose();
    });
  });

  group("full text", () {
    late SearchIndexStore store;
    setUp(() {
      store = SearchIndexStore.openInMemory(ownUserId: me);
      // Each message goes in under its own room.
      for (final e in [
        msg("\$1", roomA, now - 5 * day, "Meet at the café at noon"),
        msg("\$2", roomA, now - 4 * day, "the teapot is green"),
        msg("\$3", roomB, now - 3 * day, "green tea or black tea?",
            sender: bob),
        msg("\$4", roomB, now - 2 * day, "東京で会いましょう"),
        msg("\$5", dm, now - day, "see https://example.com/teapot",
            sender: bob),
      ]) {
        store.addLive(e["room_id"] as String, [e]);
      }
    });
    tearDown(() => store.dispose());

    test("word prefixes, every word, diacritics folded", () {
      expect(store.hasFullText, isTrue);
      expect(ids(find(store, "tea")), ["\$5", "\$3", "\$2"]);
      expect(ids(find(store, "green tea")), ["\$3", "\$2"]);
      expect(ids(find(store, "green black")), ["\$3"]);
      expect(ids(find(store, "cafe")), ["\$1"]);
      expect(find(store, "coffee").hits, isEmpty);
    });

    test("Chinese, Japanese and Korean by substring", () {
      expect(ids(find(store, "会いま")), ["\$4"]);
      // Two characters: below the trigram length, found by instr().
      expect(ids(find(store, "東京")), ["\$4"]);
    });

    test("across rooms with filters and per-room counts", () {
      final r = find(store, "tea", roomIds: [roomA, roomB]);
      expect(ids(r), ["\$3", "\$2"]);
      expect(r.roomCounts, {roomA: 1, roomB: 1});
      expect(find(store, "tea", roomIds: const []).hits, isEmpty);

      List<String> q(IndexQuery query) =>
          ids(store.searchAll(query, ranking: const IndexRanking()));
      expect(q(const IndexQuery(words: ["tea"], senders: [bob])),
          containsAll(["\$3", "\$5"]));
      expect(
          q(const IndexQuery(words: ["tea"], excludeSenders: [bob])), ["\$2"]);
      expect(q(const IndexQuery(requireLink: true)), ["\$5"]);
      expect(
          q(IndexQuery(
              words: const ["tea"],
              afterTs: now - 3 * day - 1,
              beforeTs: now - day)),
          ["\$3"]);
      // Filters without words: newest first.
      expect(q(const IndexQuery(roomIds: [roomB])), ["\$4", "\$3"]);
    });

    test("edits and redactions update the full-text index", () {
      store.addLive(roomA, [
        {
          "type": "m.room.message",
          "event_id": "\$e",
          "sender": alice,
          "origin_server_ts": now,
          "room_id": roomA,
          "content": {
            "msgtype": "m.text",
            "body": "* the kettle is green",
            "m.new_content": {"msgtype": "m.text", "body": "the kettle is red"},
            "m.relates_to": {"rel_type": "m.replace", "event_id": "\$2"},
          },
        }
      ]);
      expect(ids(find(store, "kettle")), ["\$2"]);
      expect(find(store, "teapot", roomIds: [roomA]).hits, isEmpty);

      store.addLive(roomB, [
        {
          "type": "m.room.redaction",
          "event_id": "\$r",
          "sender": bob,
          "origin_server_ts": now,
          "room_id": roomB,
          "redacts": "\$3",
          "content": {},
        }
      ]);
      expect(ids(find(store, "black")), isEmpty);

      store.deleteRoom(dm);
      expect(find(store, "example").hits, isEmpty);
      store.clear();
      expect(find(store, "green").hits, isEmpty);
    });

    test("mentions me by id, @room or display name", () {
      store.addLive(roomA, [
        msg("\$m1", roomA, now, "ping", extra: {
          "m.mentions": {
            "user_ids": [me]
          }
        }),
        msg("\$m2", roomA, now - 1, "everyone!", extra: {
          "m.mentions": {"room": true}
        }),
        msg("\$m3", roomA, now - 2, "ask Moss about it"),
      ]);
      List<String> mentions(List<String> names) =>
          ids(store.searchAll(IndexQuery(mentionsMe: true, myNames: names),
              ranking: const IndexRanking(newestFirst: true)));
      expect(mentions(const []), ["\$m1", "\$m2"]);
      expect(mentions(const ["Moss"]), ["\$m1", "\$m2", "\$m3"]);
    });
  });

  group("ranking and caps", () {
    test("best match: recency, DM and exact phrase boosts", () {
      final store = SearchIndexStore.openInMemory();
      store.addLive(roomA, [
        msg("\$old", roomA, now - 200 * day, "teapot recipe"),
        msg("\$new", roomA, now - day, "teapot recipe"),
        msg("\$apart", roomA, now - day, "recipe for a teapot"),
      ]);
      store.addLive(dm, [msg("\$dm", dm, now - 2 * day, "teapot recipe")]);
      final r = store.searchAll(const IndexQuery(words: ["teapot", "recipe"]),
          ranking: IndexRanking(now: now, dmRoomIds: const {dm}));
      expect(ids(r).first, "\$dm");
      expect(ids(r).indexOf("\$new"), lessThan(ids(r).indexOf("\$apart")));
      expect(ids(r).last, "\$old");
      expect(r.hits.first.score, greaterThan(r.hits.last.score));
      store.dispose();
    });

    test("the candidate set keeps the newest matches up to the cap", () {
      final store = SearchIndexStore.openInMemory();
      store.addLive(roomA, [
        for (var i = 0; i < 30; i++)
          msg("\$$i", roomA, now - i * 1000, "ok number $i"),
      ]);
      final r = find(store, "ok", cap: 10);
      expect(r.capped, isTrue);
      expect(r.candidates, 10);
      expect(r.roomCounts[roomA], 10);
      expect(ids(r).first, "\$0");
      expect(ids(r).last, "\$9");
      store.dispose();
    });

    test("rank score halves with age down to the floor", () {
      final fresh = SearchIndexStore.rankScore(relevance: 1, ageMs: 0);
      final month = SearchIndexStore.rankScore(relevance: 1, ageMs: 30 * day);
      final ancient =
          SearchIndexStore.rankScore(relevance: 1, ageMs: 3650 * day);
      expect(fresh, closeTo(1, 1e-9));
      expect(month, closeTo(0.6, 1e-9));
      expect(ancient, closeTo(IndexRanking.recencyFloor, 1e-6));
    });
  });

  test("reply fallbacks are stripped from the search text", () {
    expect(
        IndexExtract.stripReplyFallback(
            "> <@bob:example.com> what time?\n> second line\n\nat noon"),
        "at noon");
    expect(IndexExtract.stripReplyFallback("> not a reply"), "");
    expect(IndexExtract.stripReplyFallback("plain\n> quote"), "plain\n> quote");
    final e = IndexExtract.of(reply("\$r", roomA, now, "teapot", "Sure"))
        as IndexEventExtract;
    expect(e.event.searchText, "sure");
    expect(e.event.isReply, isTrue);
  });

  test("coverage totals: complete, started, undecrypted, history limit", () {
    final store = SearchIndexStore.openInMemory();
    store.ensureRoom(roomA);
    store.ensureRoom(roomB);
    store.ensureRoom(dm);
    final a = store.nextSegment(roomA)!;
    store.applyPage(
        roomA,
        a.id,
        [
          msg("\$1", roomA, now, "hi"),
          {
            "type": "m.room.create",
            "event_id": "\$c",
            "sender": alice,
            "origin_server_ts": now - day,
            "state_key": "",
            "content": {},
          }
        ],
        null);
    final b = store.nextSegment(roomB)!;
    store.applyPage(roomB, b.id, [msg("\$2", roomB, now, "hi")], null,
        undecrypted: [
          {
            "type": "m.room.encrypted",
            "event_id": "\$u",
            "sender": bob,
            "origin_server_ts": now - 5,
            "content": {},
          }
        ]);
    final d = store.nextSegment(dm)!;
    store.applyPage(dm, d.id, [msg("\$3", dm, now, "hi")], "more");

    final t = store.coverageTotals([roomA, roomB, dm, "!other:example.com"]);
    expect(t.rooms, 4);
    expect(t.complete, 2);
    expect(t.started, 1);
    expect(t.notStarted, 1);
    expect(t.undecrypted, 1);
    expect(t.historyLimited, 1);
    expect(store.coverage(roomB).historyLimited, isTrue);
    expect(store.coverage(roomB).undecrypted, 1);
    expect(store.coverage(roomA).historyLimited, isFalse);
    store.dispose();
  });

  test("speed: a 40,000-message index across 400 rooms", () {
    final store = SearchIndexStore.openInMemory();
    const words = [
      "tea", "pot", "recipe", "ok", "hello", "world", "kettle", "green", //
      "black", "milk", "sugar", "water", "meeting", "tomorrow", "lunch",
    ];
    var n = 0;
    String sentence(int i) => [
          for (var k = 0; k < 8; k++) words[(i * 7 + k * 13) % words.length]
        ].join(" ");
    for (var r = 0; r < 400; r++) {
      final room = "!r$r:example.com";
      store.addLive(room, [
        for (var i = 0; i < 100; i++)
          msg("\$${n++}", room, now - n * 60000, sentence(n)),
      ]);
    }
    final watch = Stopwatch()..start();
    final common = store.searchAll(const IndexQuery(words: ["ok"]),
        ranking: IndexRanking(now: now));
    final two = store.searchAll(const IndexQuery(words: ["green", "kettle"]),
        ranking: IndexRanking(now: now));
    watch.stop();
    expect(common.capped, isTrue);
    expect(common.hits.length, 200);
    expect(two.hits, isNotEmpty);
    // Generous for slow CI machines; locally it's tens of milliseconds.
    expect(watch.elapsedMilliseconds, lessThan(3000));
    store.dispose();
  });
}
