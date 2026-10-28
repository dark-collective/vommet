// Vommet (Deep Search, stage 2): the non-UI core: the query parser and
// its chips, scopes, the server search's post-processing and controller,
// merging and deduping (multi-account too), the coverage line, recent
// searches, the Deep Search card and the sidebar's hand-off row.
import 'dart:async';
import 'dart:io' show SocketException;

import 'package:commet/client/client.dart' show ClientConnectionStatus;
import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/config/deep_search_setting.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_coverage.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_handoff.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_query.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_recent.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_results.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_server.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _mira = "@mira:example.org";
const _tobias = "@tobias:example.org";

SearchDoc<String, String> _doc(String room,
        {List<String> path = const [],
        List<String> tags = const [],
        bool dm = false}) =>
    SearchDoc(
      room: room,
      name: room,
      path: path,
      pathNames: path,
      tags: tags,
      tagNames: tags,
      isDirectMessage: dm,
    );

final _index = SearchIndex<String, String>([
  _doc("!dm-mira", dm: true),
  _doc("!general", path: ["Fox Den"]),
  _doc("!builds", path: ["Fox Den", "Infra"]),
  _doc("!recipes", tags: ["u.food"]),
  _doc("!lounge"),
], const []);

DeepSearchParser<String> _parser() => DeepSearchParser<String>(
      resolveIn: (v) {
        final lower = v.toLowerCase().replaceFirst("#", "");
        if (lower == "fox den") {
          return const SearchScope.space("Fox Den", ["Fox Den"], "Fox Den");
        }
        if (lower == "general")
          return const SearchScope.room("!general", "#general");
        return null;
      },
      resolveFrom: (v) =>
          v.toLowerCase() == "mira" ? (userId: _mira, name: "Mira") : null,
      now: () => DateTime(2026, 10, 26, 15),
    );

Map<String, Object?> _event(String id,
        {String room = "!lounge",
        String sender = _tobias,
        int ts = 1000,
        String body = "tea time",
        String type = "m.room.message",
        Map<String, Object?> extra = const {},
        Map<String, Object?>? unsigned}) =>
    {
      "event_id": id,
      "room_id": room,
      "sender": sender,
      "origin_server_ts": ts,
      "type": type,
      "content": {"msgtype": "m.text", "body": body, ...extra},
      if (unsigned != null) "unsigned": unsigned,
    };

Map<String, Object?> _edit(String id, String target, String body,
        {int ts = 2000, String room = "!lounge"}) =>
    _event(id, room: room, ts: ts, body: "* $body", extra: {
      "m.new_content": {"msgtype": "m.text", "body": body},
      "m.relates_to": {"rel_type": "m.replace", "event_id": target},
    });

List<DeepSearchServerEvent> _page(List<Map<String, Object?>> events) =>
    [for (final e in events) DeepSearchServerEvent(e)];

DeepSearchResult _local(String account, String room, String id,
        {int ts = 0,
        DeepSearchSource source = DeepSearchSource.indexed,
        String body = "tea"}) =>
    DeepSearchResult(
        accountId: account,
        roomId: room,
        eventId: id,
        senderId: _mira,
        ts: ts,
        source: source,
        content: {"body": body});

IndexHit _hit(String room, String id, {int ts = 0, String body = "tea"}) =>
    IndexHit(
        eventId: id,
        ts: ts,
        kind: SharedContentKind.text,
        json: {
          "content": {"body": body}
        },
        roomId: room,
        senderId: _mira);

void main() {
  group("Query parser", () {
    test("committed tokens become chips, the rest stays text", () {
      final q = _parser()
          .parse('from:mira has:links is:dm mentions:me "green tea" recipe ');
      expect(q.text, '"green tea" recipe ');
      expect(q.fromUserIds, [_mira]);
      expect(q.has, {DeepSearchHas.link});
      expect(q.scope, const SearchScope<String>.kind(true));
      expect(q.mentionsMe, isTrue);
      expect(q.phrases, ["green tea"]);
      expect(q.words, ["green", "tea", "recipe"]);
      expect([for (final t in q.tokens) t.label],
          ["From: Mira", "Has: link", "DMs", "Mentions me"]);
    });

    test("the word being typed stays text until a space or Enter", () {
      final typing = _parser().parse("tea from:mira");
      expect(typing.tokens, isEmpty);
      expect(typing.text, "tea from:mira");
      expect(DeepSearchParser.pendingOf(typing.text),
          (key: "from", value: "mira"));
      final entered = _parser().parse("tea from:mira", commitLast: true);
      expect(entered.fromUserIds, [_mira]);
      expect(entered.text, "tea");
    });

    test("unknown keys and values that don't resolve stay text", () {
      final q = _parser()
          .parse("ratio:16:9 from:nobody has:spreadsheet in:nowhere x ");
      expect(q.tokens, isEmpty);
      expect(q.text, startsWith("ratio:16:9 from:nobody"));
    });

    test("a full user id needs no resolver; in: takes rooms and spaces", () {
      final q = _parser().parse('from:$_tobias in:"Fox Den" ');
      expect(q.fromUserIds, [_tobias]);
      expect(q.scope?.space, "Fox Den");
      final room = _parser().parse("in:#general ");
      expect(room.scope?.roomId, "!general");
      expect(room.tokens.single.label, "In: #general");
    });

    test("before: and after: take years, months, days, today", () {
      final p = _parser();
      final q = p.parse("before:2024-03 after:2023 ");
      expect(q.beforeTs, DateTime(2024, 3).millisecondsSinceEpoch);
      expect(q.afterTs, DateTime(2024).millisecondsSinceEpoch - 1);
      final day = p.parse("after:2024-03-05 ");
      expect(day.afterTs, DateTime(2024, 3, 6).millisecondsSinceEpoch - 1);
      final today = p.parse("before:today ");
      expect(today.beforeTs, DateTime(2026, 10, 26).millisecondsSinceEpoch);
      expect(p.parse("before:2024-02-31 ").tokens, isEmpty);
      expect(p.parse("before:2024-13 ").tokens, isEmpty);
    });

    test("Backspace on an empty text removes the last chip", () {
      var q = _parser().parse("from:mira has:file ").withText("");
      expect(q.canBackspace, isTrue);
      q = q.backspace();
      expect([for (final t in q.tokens) t.kind], [DeepSearchTokenKind.from]);
      q = q.backspace();
      expect(q.tokens, isEmpty);
      expect(q.canBackspace, isFalse);
      final typed = _parser().parse("from:mira tea");
      expect(typed.canBackspace, isFalse);
      expect(typed.backspace().tokens.length, 1);
    });

    test("one scope and one date of each kind; from: and has: add up", () {
      var q = const DeepSearchQuery<String>();
      q = q.withToken(DeepSearchToken.scope(const SearchScope.kind(true)));
      q = q
          .withToken(DeepSearchToken.scope(const SearchScope.room("!a", "#a")));
      q = q.withToken(const DeepSearchToken.from(_mira, "Mira"));
      q = q.withToken(const DeepSearchToken.from(_tobias, "Tobias"));
      q = q.withToken(const DeepSearchToken.from(_mira, "Mira"));
      q = q.withToken(DeepSearchToken.beforeDay(DateTime(2024, 1, 1)));
      q = q.withToken(DeepSearchToken.beforeDay(DateTime(2025, 1, 1)));
      expect(q.scope?.roomId, "!a");
      expect(q.fromUserIds, [_mira, _tobias]);
      expect(q.beforeTs, DateTime(2025).millisecondsSinceEpoch);
      expect(q.tokens.length, 4);
      q = q.withoutToken(const DeepSearchToken.from(_tobias, "Tobias"));
      expect(q.fromUserIds, [_mira]);
    });

    test("the index query and the server filter", () {
      final q = _parser().parse(
          "from:mira has:image has:voice before:2025 tea ",
          commitLast: true);
      final iq = q.toIndexQuery(
          roomIds: ["!a"],
          ignoredUsers: ["@spam:example.org"],
          myNames: ["Mira"]);
      expect(iq.words, ["tea"]);
      expect(iq.senders, [_mira]);
      expect(iq.excludeSenders, ["@spam:example.org"]);
      expect(iq.roomIds, ["!a"]);
      expect(iq.requireImage, isTrue);
      expect(iq.kinds, {SharedContentKind.voice});
      expect(iq.beforeTs, DateTime(2025).millisecondsSinceEpoch);
      expect(iq.myNames, ["mira"]);

      final f = q.toServerFilter(ignoredUsers: ["@spam:example.org"]);
      expect(f?.searchTerm, "tea");
      expect(f?.senders, [_mira]);
      expect(f?.notSenders, ["@spam:example.org"]);
      expect(f?.rooms, isNull);
      // Filter-only, DMs only, or nothing uncovered: no server search.
      expect(_parser().parse("has:file ").toServerFilter(), isNull);
      expect(_parser().parse("is:dm tea ").toServerFilter(), isNull);
      expect(q.toServerFilter(rooms: const []), isNull);
      // contains_url keeps media (a `url` in the content): has:link alone
      // can't use it, the media kinds can.
      expect(_parser().parse("has:link tea ").toServerFilter()?.containsUrl,
          isFalse);
      expect(_parser().parse("has:image tea ").toServerFilter()?.containsUrl,
          isTrue);
      expect(
          _parser()
              .parse("has:link has:voice tea ")
              .toServerFilter()
              ?.containsUrl,
          isTrue);
    });

    test("the cache key ignores case, spacing and chip order", () {
      final a = _parser().parse("from:mira has:file  Green   TEA ");
      final b = _parser().parse("has:file from:mira green tea");
      expect(a.normalized, b.normalized);
      expect(
          a.normalized == _parser().parse('"green tea"').normalized, isFalse);
    });

    test("quoted phrases are checked on the text", () {
      final q = _parser().parse('"green tea" pot');
      expect(q.matchesPhrases("A pot of Green  tea"), isTrue);
      expect(q.matchesPhrases("tea is green"), isFalse);
    });
  });

  group("Scopes", () {
    test("a space takes its subspaces' rooms; a room takes its chain", () {
      String id(String r) => r;
      expect(deepSearchScopeRoomIds<String, String>(null, _index, id), isNull);
      expect(
          deepSearchScopeRoomIds(
              const SearchScope<String>.space(
                  "Fox Den", ["Fox Den"], "Fox Den"),
              _index,
              id),
          ["!general", "!builds"]);
      expect(
          deepSearchScopeRoomIds(
              const SearchScope<String>.tag("u.food", "food"), _index, id),
          ["!recipes"]);
      expect(
          deepSearchScopeRoomIds(
              const SearchScope<String>.kind(true), _index, id),
          ["!dm-mira"]);
      expect(
          deepSearchScopeRoomIds(
              const SearchScope<String>.room("!new", "#tea"), _index, id,
              chainOf: (_) => ["!old", "!older"]),
          ["!new", "!old", "!older"]);
    });

    test("a room scope doesn't narrow the name search", () {
      const scope = SearchScope<String>.room("!general", "#general");
      expect(_index.docs.every((d) => scope.takes(d)), isTrue);
      expect(scope == const SearchScope<String>.room("!general", "x"), isTrue);
      expect(scope == const SearchScope<String>.room("!other", "#general"),
          isFalse);
    });
  });

  group("Server post-processing", () {
    final tea = _parser().parse("tea", commitLast: true);

    test("edits show their latest text; the edit events are dropped", () {
      final hits = deepSearchPostProcess(
          tea,
          _page([
            _event("\$a", ts: 1000, body: "tea at 5"),
            _edit("\$a-edit1", "\$a", "tea at 6", ts: 2000),
            _edit("\$a-edit2", "\$a", "tea at 7", ts: 3000),
            _event("\$b", ts: 1500, body: "old tea", unsigned: {
              "m.relations": {
                "m.replace": {
                  "content": {
                    "m.new_content": {"msgtype": "m.text", "body": "new tea"}
                  }
                }
              }
            }),
          ]));
      expect([for (final h in hits) h.eventId], ["\$b", "\$a"]);
      expect(hits[1].body, "tea at 7");
      expect(hits[1].edited, isTrue);
      expect(hits[0].body, "new tea");
    });

    test("an edit without its original stands in for it", () {
      final hits = deepSearchPostProcess(
          tea, _page([_edit("\$e", "\$orig", "tea now")]));
      expect(hits.single.eventId, "\$orig");
      expect(hits.single.body, "tea now");
    });

    test("an original whose edit dropped the words is dropped", () {
      final hits = deepSearchPostProcess(
          tea,
          _page([
            _event("\$a", body: "tea"),
            _edit("\$a-edit", "\$a", "coffee"),
          ]));
      expect(hits, isEmpty);
    });

    test("redactions, redacted events, covered rooms, ignored users", () {
      final hits = deepSearchPostProcess(
          tea,
          _page([
            _event("\$keep", ts: 10),
            _event("\$gone", ts: 20),
            {
              "event_id": "\$red",
              "room_id": "!lounge",
              "sender": _tobias,
              "type": "m.room.redaction",
              "redacts": "\$gone",
              "origin_server_ts": 30,
              "content": <String, Object?>{},
            },
            _event("\$was", ts: 40, unsigned: {
              "redacted_because": {"type": "m.room.redaction"}
            }),
            _event("\$known", ts: 45),
            _event("\$enc", ts: 50, room: "!encrypted"),
            _event("\$spam", ts: 60, sender: "@spam:example.org"),
            _event("\$state", ts: 70, type: "m.room.topic"),
          ]),
          context: const DeepSearchServerContext(
              coveredRoomIds: {"!encrypted"},
              ignoredUsers: {"@spam:example.org"},
              redactedIds: {"\$known"}));
      expect([for (final h in hits) h.eventId], ["\$keep"]);
    });

    test("chips the server can't filter are applied here", () {
      final images = _parser().parse("has:image tea ");
      final hits = deepSearchPostProcess(
          images,
          _page([
            _event("\$text", body: "tea"),
            _event("\$img", body: "tea.png", extra: {"msgtype": "m.image"}),
          ]));
      expect([for (final h in hits) h.eventId], ["\$img"]);

      final mentions = _parser().parse("mentions:me tea ");
      final mine = deepSearchPostProcess(
          mentions,
          _page([
            _event("\$1", ts: 1, body: "tea?"),
            _event("\$2", ts: 2, body: "tea?", extra: {
              "m.mentions": {
                "user_ids": [_mira]
              }
            }),
            _event("\$3", ts: 3, body: "mira, tea?"),
          ]),
          context: const DeepSearchServerContext(
              myUserId: _mira, myNames: ["Mira"]));
      expect([for (final h in mine) h.eventId], ["\$3", "\$2"]);

      final phrase = _parser().parse('"green tea"');
      expect(
          deepSearchPostProcess(
              phrase,
              _page([
                _event("\$x", body: "green and black tea"),
                _event("\$y", body: "Green tea!"),
              ])).map((h) => h.eventId),
          ["\$y"]);
    });
  });

  group("Server controller", () {
    final tea = _parser().parse("tea", commitLast: true);
    final cake = _parser().parse("cake", commitLast: true);
    DeepSearchServerFilter? filterOf(DeepSearchQuery<String> q) =>
        q.toServerFilter();
    const ctx = DeepSearchServerContext();

    test("a stale response is dropped", () async {
      final pending = <String, Completer<DeepSearchServerPage>>{};
      final c = DeepSearchServerController<String>(fetch: (f, next) {
        final done = Completer<DeepSearchServerPage>();
        pending[f.searchTerm] = done;
        return done.future;
      });
      c.submit(tea, filterOf(tea), ctx);
      c.submit(cake, filterOf(cake), ctx);
      expect(c.state.value.loading, isTrue);
      pending["cake"]?.complete(
          DeepSearchServerPage(_page([_event("\$c", body: "cake")])));
      await Future<void>.delayed(Duration.zero);
      pending["tea"]
          ?.complete(DeepSearchServerPage(_page([_event("\$t", body: "tea")])));
      await Future<void>.delayed(Duration.zero);
      expect(c.state.value.key, cake.normalized);
      expect([for (final h in c.state.value.hits) h.eventId], ["\$c"]);
      c.dispose();
    });

    test("pages are cached per query; Load more follows next_batch", () async {
      final calls = <String?>[];
      final c = DeepSearchServerController<String>(fetch: (f, next) async {
        calls.add(next);
        if (next == null) {
          return DeepSearchServerPage(
              _page([_event("\$1", ts: 20), _event("\$2", ts: 10)]),
              nextBatch: "b2");
        }
        return DeepSearchServerPage(
            _page([_event("\$2", ts: 10), _event("\$3", ts: 5)]));
      });
      c.submit(tea, filterOf(tea), ctx);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.value.canLoadMore, isTrue);
      await c.loadMore();
      expect([for (final h in c.state.value.hits) h.eventId],
          ["\$1", "\$2", "\$3"]);
      expect(c.state.value.nextBatch, isNull);
      // Back to the same query: from the cache, no request.
      c.submit(cake, null, ctx);
      expect(c.state.value.skipped, isTrue);
      c.submit(tea, filterOf(tea), ctx);
      expect(c.state.value.hits.length, 3);
      expect(calls, [null, "b2"]);
      c.dispose();
    });

    test("typing waits for the pause; a failure is an error state", () async {
      var calls = 0;
      final c = DeepSearchServerController<String>(
          debounce: const Duration(milliseconds: 20),
          fetch: (f, next) async {
            calls++;
            throw StateError("offline");
          });
      c.update(tea, filterOf(tea), ctx);
      c.update(cake, filterOf(cake), ctx);
      expect(calls, 0);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(calls, 1);
      expect(c.state.value.error, isNotNull);
      expect(c.state.value.key, cake.normalized);
      c.dispose();
    });
  });

  group("Merge and dedupe", () {
    test("lists interleave by rank position; first copy wins", () {
      final merged = deepSearchMerge([
        [
          _local("a", "!r", "\$1"),
          _local("a", "!r", "\$2"),
          _local("a", "!r", "\$3")
        ],
        [
          _local("a", "!r", "\$2", source: DeepSearchSource.timeline),
          _local("a", "!r", "\$9", source: DeepSearchSource.timeline),
        ],
      ]);
      // \$2 keeps the index's copy, at the index's position.
      expect([for (final r in merged) r.eventId], ["\$1", "\$2", "\$9", "\$3"]);
      expect(merged[1].source, DeepSearchSource.indexed);
    });

    test("one account: local section, separate server section", () {
      final q = _parser().parse("tea", commitLast: true);
      final results = DeepSearchResults.merge(q, [
        DeepSearchAccountHits(
          accountId: "a",
          index: IndexSearchResult(
              hits: [_hit("!dm", "\$1", ts: 5), _hit("!enc", "\$2", ts: 9)],
              roomCounts: {"!dm": 4, "!enc": 1}),
          timeline: [
            _local("a", "!dm", "\$1", source: DeepSearchSource.timeline),
            _local("a", "!new", "\$t", source: DeepSearchSource.timeline),
          ],
          server: [
            DeepSearchServerHit(
                eventId: "\$s",
                roomId: "!lounge",
                senderId: _tobias,
                ts: 7,
                content: {"body": "tea"}),
            DeepSearchServerHit(
                eventId: "\$t",
                roomId: "!new",
                senderId: _tobias,
                ts: 8,
                content: {"body": "tea"}),
          ],
        ),
      ]);
      expect([for (final r in results.local) r.eventId], ["\$1", "\$2", "\$t"]);
      expect([for (final r in results.server) r.eventId], ["\$s"]);
      expect(results.roomCounts[("a", "!dm")], 4);
      expect(results.roomCounts[("a", "!new")], 1);
      expect(results.roomCounts[("a", "!lounge")], 1);
      expect(results.total, 7);
      final strip = results.mostMatches(limit: 2);
      expect([for (final r in strip) r.roomId], ["!dm", "!enc"]);
      expect(results.moreRooms(limit: 2), 2);
    });

    test("All accounts: deduped by room and event, each with its account", () {
      final q = _parser().parse("tea", commitLast: true);
      final results = DeepSearchResults.merge(q, [
        DeepSearchAccountHits(
            accountId: "work",
            index: IndexSearchResult(hits: [
              _hit("!shared", "\$1", ts: 3),
              _hit("!w", "\$2", ts: 2)
            ])),
        DeepSearchAccountHits(
            accountId: "home",
            index: IndexSearchResult(hits: [
              _hit("!shared", "\$1", ts: 3),
              _hit("!h", "\$3", ts: 9)
            ])),
      ]);
      expect([
        for (final r in results.local) (r.accountId, r.eventId)
      ], [
        ("work", "\$1"),
        ("work", "\$2"),
        ("home", "\$3"),
      ]);
      final newest = DeepSearchResults.merge(
          q,
          [
            DeepSearchAccountHits(
                accountId: "work",
                index: IndexSearchResult(hits: [_hit("!w", "\$2", ts: 2)])),
            DeepSearchAccountHits(
                accountId: "home",
                index: IndexSearchResult(hits: [_hit("!h", "\$3", ts: 9)])),
          ],
          newestFirst: true);
      expect([for (final r in newest.local) r.eventId], ["\$3", "\$2"]);
    });

    test("index hits without the quoted phrase are left out", () {
      final q = _parser().parse('"green tea"');
      final results = DeepSearchResults.merge(q, [
        DeepSearchAccountHits(
            accountId: "a",
            index: IndexSearchResult(hits: [
              _hit("!r", "\$1", body: "green tea"),
              _hit("!r", "\$2", body: "tea, green"),
            ])),
      ]);
      expect([for (final r in results.local) r.eventId], ["\$1"]);
    });
  });

  group("Coverage line", () {
    const totals = IndexCoverageTotals(rooms: 480, complete: 412, started: 60);
    List<DeepSearchCoverageKind> kinds(DeepSearchCoverageInput i) =>
        [for (final l in deepSearchCoverage(i)) l.kind];

    test("building", () {
      final lines = deepSearchCoverage(const DeepSearchCoverageInput(
          state: EncryptedIndexState.running, totals: totals));
      expect(lines.single.title, "Searched 412 of 480 encrypted chats fully");
      expect(lines.single.detail,
          "68 still indexing: their older messages aren’t searched yet.");
    });

    test("percent rounds but stays below 100 until done", () {
      expect(deepSearchPercent(412, 480), 86);
      expect(deepSearchPercent(999, 1000), 99);
      expect(deepSearchPercent(480, 480), 100);
      expect(deepSearchPercent(0, 0), 0);
    });

    test("first run", () {
      expect(
          kinds(const DeepSearchCoverageInput(
              state: EncryptedIndexState.running,
              totals: IndexCoverageTotals(rooms: 480, started: 3))),
          [DeepSearchCoverageKind.firstRun]);
    });

    test("paused states come first, each with at most one action", () {
      final wifi = deepSearchCoverage(const DeepSearchCoverageInput(
          state: EncryptedIndexState.waitingForWifi, totals: totals));
      expect(wifi.first.kind, DeepSearchCoverageKind.wifiPaused);
      expect(
          wifi.first.detail, "Searching what’s indexed so far (86% of chats).");
      expect(wifi.first.action, DeepSearchCoverageAction.indexOnMobileData);
      final off = deepSearchCoverage(const DeepSearchCoverageInput(
          state: EncryptedIndexState.off, totals: totals));
      expect(off.first.title, "Indexing is off");
      expect(off.last.detail,
          "68 not indexed: their older messages aren’t searched.");
      expect(off.first.actionLabel, "Turn on in Settings ›");
      expect(
          kinds(const DeepSearchCoverageInput(
              state: EncryptedIndexState.pausedForBattery, totals: totals)),
          [
            DeepSearchCoverageKind.batteryPaused,
            DeepSearchCoverageKind.building
          ]);
    });

    test("web, offline and missing keys", () {
      expect(
          kinds(const DeepSearchCoverageInput(
              state: EncryptedIndexState.unavailable,
              totals: IndexCoverageTotals(),
              indexAvailable: false,
              online: false)),
          [DeepSearchCoverageKind.web, DeepSearchCoverageKind.offline]);
      final keys = deepSearchCoverage(const DeepSearchCoverageInput(
          state: EncryptedIndexState.done,
          totals: IndexCoverageTotals(rooms: 2, complete: 2, undecrypted: 3),
          online: false));
      expect([
        for (final l in keys) l.kind
      ], [
        DeepSearchCoverageKind.offline,
        DeepSearchCoverageKind.complete,
        DeepSearchCoverageKind.keysMissing,
      ]);
      expect(keys.last.title, "3 messages can’t be decrypted yet");
      expect(keys.last.actionLabel, "Details ›");
      // Offline only matters when the query searches the server.
      expect(
          kinds(const DeepSearchCoverageInput(
              state: EncryptedIndexState.done,
              totals: IndexCoverageTotals(rooms: 1, complete: 1),
              online: false,
              serverWanted: false)),
          [DeepSearchCoverageKind.complete]);
    });

    test("scoped to one room", () {
      DeepSearchCoverageLine room(RoomCoverage c,
              {EncryptedIndexState state = EncryptedIndexState.running,
              bool indexed = true}) =>
          deepSearchCoverage(DeepSearchCoverageInput(
                  state: state,
                  totals: totals,
                  room: DeepSearchRoomCoverageInput(
                      name: "#tea-garden",
                      indexed: indexed,
                      coverage: c,
                      createdTs: DateTime(2021, 5).millisecondsSinceEpoch)))
              .last;
      final partial = room(RoomCoverage(
          known: true,
          complete: false,
          oldestTs: DateTime(2024, 3, 9).millisecondsSinceEpoch));
      expect(partial.title, "Indexed back to Mar 2024 (room since 2021)");
      expect(partial.actionLabel, "Look further back ›");
      expect(partial.confirm, isFalse);
      final off = deepSearchCoverage(DeepSearchCoverageInput(
          state: EncryptedIndexState.off,
          totals: totals,
          room: const DeepSearchRoomCoverageInput(
              name: "#tea-garden",
              indexed: true,
              coverage: RoomCoverage(known: true, complete: false))));
      expect(off.first.kind, DeepSearchCoverageKind.off);
      expect(off.last.confirm, isTrue);
      expect(
          deepSearchConfirmSheet("#tea-garden", EncryptedIndexState.off).title,
          "Search further back in #tea-garden?");
      expect(
          room(const RoomCoverage(
                  known: true, complete: true, historyLimited: true))
              .title,
          "Indexed back to when you joined");
      expect(room(RoomCoverage.unknown).kind,
          DeepSearchCoverageKind.roomNotIndexed);
      expect(room(RoomCoverage.unknown, indexed: false).kind,
          DeepSearchCoverageKind.roomServerOnly);
    });

    test("summary, counts and All accounts totals", () {
      expect(
          deepSearchCoverageSummary(EncryptedIndexState.running, totals,
              wifiOnly: true),
          "Encrypted chats: 412 of 480 fully indexed · building on Wi-Fi");
      expect(deepSearchCount(1700), "1,700");
      expect(deepSearchCount(999), "999");
      final sum = deepSearchSumTotals(const [
        IndexCoverageTotals(rooms: 2, complete: 1, undecrypted: 1),
        IndexCoverageTotals(rooms: 3, complete: 3, migrating: true),
      ]);
      expect(sum.rooms, 5);
      expect(sum.complete, 4);
      expect(sum.undecrypted, 1);
      expect(sum.migrating, isTrue);
    });
  });

  group("Offline (follow-ups)", () {
    DeepSearchServerState failed(Object e) =>
        DeepSearchServerState(key: "tea", error: e);

    test("network errors are told from server errors", () {
      expect(deepSearchIsNetworkError(TimeoutException("slow")), isTrue);
      expect(
          deepSearchIsNetworkError(http.ClientException("no route")), isTrue);
      expect(deepSearchIsNetworkError(const SocketException("down")), isTrue);
      expect(deepSearchIsNetworkError(StateError("500")), isFalse);
      expect(deepSearchIsNetworkError(null), isFalse);
    });

    test("offline: a network failure, or no connection and no answer", () {
      const loading = DeepSearchServerState(key: "tea", loading: true);
      const done = DeepSearchServerState(key: "tea");
      expect(
          deepSearchServerOffline(failed(TimeoutException("slow")),
              ClientConnectionStatus.connected),
          isTrue);
      // A server error while connected: the retry row, not Offline.
      expect(
          deepSearchServerOffline(
              failed(StateError("500")), ClientConnectionStatus.connected),
          isFalse);
      expect(
          deepSearchServerOffline(
              failed(StateError("500")), ClientConnectionStatus.disconnected),
          isTrue);
      expect(
          deepSearchServerOffline(loading, ClientConnectionStatus.disconnected),
          isTrue);
      expect(
          deepSearchServerOffline(loading, ClientConnectionStatus.connecting),
          isFalse);
      // Results came back while sync blipped: still online.
      expect(deepSearchServerOffline(done, ClientConnectionStatus.disconnected),
          isFalse);
      // No server search for this query: never offline.
      expect(
          deepSearchServerOffline(
              DeepSearchServerState.idle, ClientConnectionStatus.disconnected),
          isFalse);
    });

    test("the Offline line (Mockup 5)", () {
      final lines = deepSearchCoverage(const DeepSearchCoverageInput(
          state: EncryptedIndexState.done,
          totals: IndexCoverageTotals(rooms: 2, complete: 2),
          online: false));
      expect(lines.first.kind, DeepSearchCoverageKind.offline);
      expect(lines.first.title, "Offline");
      expect(lines.first.detail,
          "Showing this device only. Unencrypted rooms are searched again when you reconnect.");
      expect(lines.first.action, isNull);
    });
  });

  group("All accounts coverage (follow-ups)", () {
    const complete = IndexCoverageTotals(rooms: 10, complete: 10);
    const partial = IndexCoverageTotals(rooms: 10, complete: 4, started: 3);

    test("severity: off > Wi-Fi > battery > running > done > no index", () {
      final order = [
        EncryptedIndexState.off,
        EncryptedIndexState.waitingForWifi,
        EncryptedIndexState.pausedForBattery,
        EncryptedIndexState.running,
        EncryptedIndexState.done,
        EncryptedIndexState.unavailable,
      ];
      for (var i = 1; i < order.length; i++) {
        expect(deepSearchStateSeverity(order[i - 1]),
            greaterThan(deepSearchStateSeverity(order[i])));
      }
    });

    test("totals summed, the worst state of the accounts still indexing", () {
      final merged = deepSearchMergeCoverage(const [
        (state: EncryptedIndexState.running, totals: partial),
        (state: EncryptedIndexState.waitingForWifi, totals: partial),
        (state: EncryptedIndexState.done, totals: complete),
      ]);
      expect(merged.state, EncryptedIndexState.waitingForWifi);
      expect(merged.totals.rooms, 30);
      expect(merged.totals.complete, 18);
      expect(merged.totals.started, 6);
      final lines = deepSearchCoverage(
          DeepSearchCoverageInput(state: merged.state, totals: merged.totals));
      expect(lines.first.kind, DeepSearchCoverageKind.wifiPaused);
      expect(lines.last.title, "Searched 18 of 30 encrypted chats fully");
    });

    test("an account fully indexed limits nothing", () {
      // Indexing turned off after everything was indexed: not shown.
      expect(
          deepSearchMergeCoverage(const [
            (state: EncryptedIndexState.off, totals: complete),
            (state: EncryptedIndexState.running, totals: partial),
          ]).state,
          EncryptedIndexState.running);
      // Every account complete: the worst of them (the lines skip it).
      expect(
          deepSearchMergeCoverage(const [
            (state: EncryptedIndexState.off, totals: complete),
            (state: EncryptedIndexState.done, totals: complete),
          ]).state,
          EncryptedIndexState.off);
      // Totals not loaded yet count as still indexing.
      expect(
          deepSearchMergeCoverage(const [
            (state: EncryptedIndexState.pausedForBattery, totals: null),
            (state: EncryptedIndexState.running, totals: partial),
          ]).state,
          EncryptedIndexState.pausedForBattery);
    });

    test("no index anywhere is the web; one index wins over none", () {
      expect(
          deepSearchMergeCoverage(const [
            (state: EncryptedIndexState.unavailable, totals: null),
          ]).state,
          EncryptedIndexState.unavailable);
      expect(
          deepSearchMergeCoverage(const [
            (state: EncryptedIndexState.unavailable, totals: null),
            (state: EncryptedIndexState.done, totals: complete),
          ]).state,
          EncryptedIndexState.done);
      expect(deepSearchMergeCoverage(const []).state,
          EncryptedIndexState.unavailable);
    });
  });

  group("has: without an index (follow-ups)", () {
    Map<String, Object?> media(String type, {bool voice = false}) => {
          "msgtype": type,
          "body": "file.bin",
          "url": "mxc://example.org/abc",
          if (voice) "org.matrix.msc3245.voice": <String, Object?>{},
        };

    test("kinds from the msgtype, voice from its flag", () {
      expect(deepSearchHasMatches({DeepSearchHas.image}, media("m.image")),
          isTrue);
      expect(deepSearchHasMatches({DeepSearchHas.image}, media("m.video")),
          isFalse);
      expect(deepSearchHasMatches({DeepSearchHas.video}, media("m.video")),
          isTrue);
      expect(
          deepSearchHasMatches({DeepSearchHas.file}, media("m.file")), isTrue);
      expect(deepSearchHasMatches({DeepSearchHas.voice}, media("m.audio")),
          isFalse);
      expect(
          deepSearchHasMatches(
              {DeepSearchHas.voice}, media("m.audio", voice: true)),
          isTrue);
      expect(
          deepSearchHasMatches({DeepSearchHas.voice},
              {"msgtype": "m.audio", "m.voice": <String, Object?>{}}),
          isTrue);
    });

    test("kinds are any-of, a link is required on top", () {
      final kinds = {DeepSearchHas.image, DeepSearchHas.file};
      expect(deepSearchHasMatches(kinds, media("m.file")), isTrue);
      expect(deepSearchHasMatches(kinds, {"msgtype": "m.text", "body": "hi"}),
          isFalse);
      final text = {"msgtype": "m.text", "body": "see https://example.org"};
      expect(deepSearchHasMatches({DeepSearchHas.link}, text), isTrue);
      expect(
          deepSearchHasMatches(
              {DeepSearchHas.link}, {"msgtype": "m.text", "body": "no link"}),
          isFalse);
      expect(
          deepSearchHasMatches(
              {DeepSearchHas.link, DeepSearchHas.image}, media("m.image")),
          isFalse);
      // The shown body (e.g. the latest edit) wins over the content's.
      expect(deepSearchHasMatches({DeepSearchHas.link}, text, body: "edited"),
          isFalse);
      expect(deepSearchHasMatches(const {}, const {}), isTrue);
    });
  });

  group("Recent searches", () {
    setUp(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      Preference.preferences = await SharedPreferences.getInstance();
    });

    DeepSearchRecentStore<String> store() => DeepSearchRecentStore<String>(
        spaceIdOf: (s) => s,
        resolveSpace: (id) => SearchScope.space(id, [id], id));

    test("the last five, newest first, the same search moved up", () async {
      final s = store();
      expect(deepSearchRecentPreference.value, isTrue);
      for (final w in ["one", "two", "three", "four", "five", "six"]) {
        await s.remember(DeepSearchQuery<String>(text: w));
      }
      await s.remember(const DeepSearchQuery<String>(text: " Four "));
      expect([for (final e in s.entries) e.text],
          ["Four", "six", "five", "three", "two"]);
      await s.remember(const DeepSearchQuery<String>());
      expect(s.entries.length, DeepSearchRecentStore.max);
    });

    test("chips are kept and restored", () async {
      final s = store();
      final q = _parser()
          .parse('from:mira in:"Fox Den" has:file before:2024 tea ')
          .withToken(const DeepSearchToken.mentionsMe());
      await s.remember(q);
      final entry = s.entries.single;
      expect(entry.summary,
          "from: Mira · in: Fox Den · has: file · before: 2024 · mentions: me");
      final back = s.queryOf(entry);
      expect(back.normalized, q.normalized);
    });

    test("Clear, and the setting off forgets them", () async {
      final s = store();
      await s.remember(const DeepSearchQuery<String>(text: "tea"));
      await s.clear();
      expect(s.entries, isEmpty);
      await s.remember(const DeepSearchQuery<String>(text: "tea"));
      await s.setEnabled(false);
      expect(deepSearchRecentListPreference.value, isEmpty);
      await s.remember(const DeepSearchQuery<String>(text: "cake"));
      expect(deepSearchRecentListPreference.value, isEmpty);
    });
  });

  group("Deep Search card", () {
    test("under Invites on the default Overview, first in the library", () {
      expect(HomeTabs.overviewCards.take(2),
          [HomeLayout.invites, HomeLayout.deepSearch]);
      expect(HomeLayout.knownTypes.first, HomeLayout.deepSearch);
      final info = CardInfo.all.first;
      expect(info.label, "Deep Search");
      expect(info.short, "Search messages, files and links");
      expect(HomeLayout.multiTypes.contains(HomeLayout.deepSearch), isFalse);
    });

    test("a customized layout gets it once, at the top", () {
      final tabs = HomeTabs.parse({
        "version": HomeTabs.version,
        "tabs": [
          {
            "id": HomeTabs.overview,
            "name": "Overview",
            "cards": [
              {"id": "favourites"},
              {"id": "recent"},
            ],
          },
        ],
      });
      final once = tabs.withDeepSearchOnce();
      final main = once.tab(HomeTabs.overview)?.main;
      expect([for (final c in main?.cards ?? <HomeCard>[]) c.type],
          ["deep_search", "favourites", "recent"]);
      expect(once.extra[HomeTabs.deepSearchAddedKey], isTrue);
      expect(once.toJson()[HomeTabs.deepSearchAddedKey], isTrue);

      // Removed: it stays removed after a save and a new read.
      final overview = once.tab(HomeTabs.overview);
      final removed = once.replaceTab(overview!
          .copyWith(main: overview.main.remove(HomeLayout.deepSearch)));
      final again = HomeTabs.parse(removed.toJson()).withDeepSearchOnce();
      expect(again.tab(HomeTabs.overview)!.main.shows(HomeLayout.deepSearch),
          isFalse);
    });

    test("defaults and Reset aren't given a second one", () {
      final tabs = HomeTabs.parse(null).withDeepSearchOnce();
      final cards = tabs.tab(HomeTabs.overview)!.main.cards;
      expect(cards.where((c) => c.type == HomeLayout.deepSearch).length, 1);
      expect(cards[1].type, HomeLayout.deepSearch);
      final reset = tabs.reset();
      expect(reset.extra[HomeTabs.deepSearchAddedKey], isTrue);
      expect(reset.tab(HomeTabs.overview)!.main.cards[1].type,
          HomeLayout.deepSearch);
    });

    List<String> overviewTypes(HomeTabs tabs) =>
        [for (final c in tabs.tab(HomeTabs.overview)!.main.cards) c.type];

    test("Invites moves above the Deep Search insert once", () {
      final tabs = HomeTabs.parse({
        "version": HomeTabs.version,
        "tabs": [
          {
            "id": HomeTabs.overview,
            "name": "Overview",
            "cards": [
              {"id": "invites"},
              {"id": "recent"},
            ],
          },
        ],
      }).withDeepSearchOnce().withInvitesFirstOnce();
      expect(overviewTypes(tabs), ["invites", "deep_search", "recent"]);
      expect(tabs.toJson()[HomeTabs.invitesFirstKey], isTrue);

      // Moved back above Invites by hand: it stays there.
      final overview = tabs.tab(HomeTabs.overview)!;
      final mine = tabs.replaceTab(overview.copyWith(
          main: overview.main.move(HomeLayout.deepSearch, -1)));
      final again = HomeTabs.parse(mine.toJson())
          .withDeepSearchOnce()
          .withInvitesFirstOnce();
      expect(overviewTypes(again), ["deep_search", "invites", "recent"]);
    });

    test("a saved Deep Search-first default gets Invites first", () {
      final tabs = HomeTabs.parse({
        "version": HomeTabs.version,
        HomeTabs.deepSearchAddedKey: true,
        "tabs": [
          {
            "id": HomeTabs.overview,
            "name": "Overview",
            "cards": [
              {"id": "deep_search"},
              {"id": "invites"},
              {"id": "recent"},
              {"id": "other_rooms"},
            ],
          },
        ],
      }).withDeepSearchOnce().withInvitesFirstOnce();
      expect(overviewTypes(tabs),
          ["invites", "deep_search", "recent", "other_rooms"]);
    });

    test("other orders are left alone", () {
      final tabs = HomeTabs.parse({
        "version": HomeTabs.version,
        HomeTabs.deepSearchAddedKey: true,
        "tabs": [
          {
            "id": HomeTabs.overview,
            "name": "Overview",
            "cards": [
              {"id": "deep_search"},
              {"id": "recent"},
              {"id": "invites"},
            ],
          },
        ],
      }).withInvitesFirstOnce();
      expect(overviewTypes(tabs), ["deep_search", "recent", "invites"]);
      expect(tabs.extra[HomeTabs.invitesFirstKey], isTrue);
    });

    test("defaults are already Invites first", () {
      final tabs =
          HomeTabs.parse(null).withDeepSearchOnce().withInvitesFirstOnce();
      expect(overviewTypes(tabs).take(2), ["invites", "deep_search"]);
    });

    test("no Overview tab: only the flag", () {
      final tabs = HomeTabs.parse({
        "version": HomeTabs.version,
        "tabs": [
          {"id": "mine", "name": "Mine", "cards": []}
        ],
      }).withDeepSearchOnce();
      expect(tabs.tab("mine")!.main.cards, isEmpty);
      expect(tabs.extra[HomeTabs.deepSearchAddedKey], isTrue);
    });

    test("the library can add it back once", () {
      const empty = HomeLayout([], inTab: true);
      expect(empty.canAdd(HomeLayout.deepSearch), isTrue);
      final added = empty.add(HomeLayout.deepSearch);
      expect(added.canAdd(HomeLayout.deepSearch), isFalse);
    });
  });

  group("Sidebar hand-off row", () {
    test("always the last row while there's text", () {
      expect(DeepSearchHandoff.of<String>("  "), isNull);
      final row = DeepSearchHandoff.of<String>(" tea ");
      expect(row?.label, "Search messages for “tea” ›");
      expect(row?.query.text, "tea");
      expect(row?.query.tokens, isEmpty);
    });

    test("the sidebar's scope becomes an in: chip", () {
      final row = DeepSearchHandoff.of<String>("tea",
          scope: const SearchScope.space("Fox Den", ["Fox Den"], "Fox Den"));
      expect(row?.query.scope?.space, "Fox Den");
      expect(row?.query.tokens.single.label, "In: Fox Den");
    });

    test("long text is cut", () {
      final row = DeepSearchHandoff.of<String>("a" * 60);
      expect(row?.label, "Search messages for “${"a" * 40}…” ›");
    });
  });
}
