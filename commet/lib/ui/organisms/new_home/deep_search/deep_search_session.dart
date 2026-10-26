// Vommet (Deep Search, stage 2): the state behind the Deep Search page, the
// card and the results bar in a chat. One per app: it keeps the query,
// filters, results, scroll and the ✓ seen marks while a result is open, so
// "‹ Results" (or back) finds the list as it was.
//
// Searching (Decision 5): the index is asked 200 ms after the last change
// (at once on Enter) and paints first; the homeserver's section follows
// through one DeepSearchServerController per account (600 ms or Enter).
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/encrypted_search_index_setting.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_coverage.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_query.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_recent.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_results.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_server.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_server_matrix.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_view_model.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';
import 'package:commet/ui/organisms/new_home/new_home_search_index.dart';
import 'package:commet/ui/organisms/new_home/new_home_search_view.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

/// The homeserver section across the accounts searched.
class DeepSearchServerSummary {
  const DeepSearchServerSummary(
      {this.loading = false,
      this.loadingMore = false,
      this.failed = false,
      this.skipped = true,
      this.canLoadMore = false});
  final bool loading;
  final bool loadingMore;
  final bool failed;

  /// No account searched the server for this query.
  final bool skipped;
  final bool canLoadMore;
}

class DeepSearchSession extends ChangeNotifier {
  DeepSearchSession._();

  static final DeepSearchSession instance = DeepSearchSession._();

  static const localDebounce = Duration(milliseconds: 200);

  /// Desktop: Home's main page shows Deep Search (the side list stays).
  bool isOpen = false;

  /// The field should take the focus when the page shows next.
  bool wantsFocus = false;

  DeepSearchQuery<Space> query = const DeepSearchQuery();
  bool newestFirst = false;
  DeepSearchResults results = DeepSearchResults.empty;
  bool searchingLocal = false;

  /// "+N more here" groups opened, by their first hit's event id.
  final Set<String> expanded = {};

  /// The list's scroll offset, restored when it shows again.
  double scrollOffset = 0;

  final DeepSearchMarks marks = DeepSearchMarks();

  /// The last search run (the card's "Last search: …").
  DeepSearchQuery<Space>? lastSearch;

  // The results bar (Mockup 4b): the list a result was opened from.
  List<DeepSearchResult> openList = const [];
  int? openIndex;
  String? _expectedRoomId;

  DeepSearchResult? get openHit {
    final i = openIndex;
    if (i == null || i < 0 || i >= openList.length) return null;
    return openList[i];
  }

  ClientManager? _manager;
  Client? _filter;
  bool _attachedBus = false;

  final Map<String, IndexSearchResult?> _local = {};
  final Map<String, List<DeepSearchResult>> _timeline = {};
  final Map<String, DeepSearchServerController<Space>> _servers = {};
  final Map<String, Set<String>> _fullyIndexed = {};
  final Map<String, IndexCoverageTotals> _totals = {};
  final Map<String, EncryptedIndexState> _states = {};
  final Map<String, VoidCallback> _progressListeners = {};
  RoomCoverage? scopedCoverage;

  /// Renders and widget tests: the index state and totals shown, in place
  /// of the accounts' (null: the accounts' own).
  @visibleForTesting
  ({EncryptedIndexState state, IndexCoverageTotals totals})? debugCoverage;

  /// Renders and widget tests: the homeserver section's state, in place of
  /// the accounts' controllers' (null: theirs).
  @visibleForTesting
  DeepSearchServerSummary? debugServerSummary;
  Timer? _localTimer;
  Timer? _coverageTimer;
  int _generation = 0;

  late final DeepSearchRecentStore<Space> recent = DeepSearchRecentStore(
      spaceIdOf: (space) => "${space.client.identifier}|${space.identifier}",
      resolveSpace: _resolveSpace);

  late final DeepSearchParser<Space> parser =
      DeepSearchParser(resolveIn: resolveIn, resolveFrom: resolveFrom);

  // ---------------------------------------------------------------- accounts

  /// The accounts searched: the account filter's one, else all.
  List<Client> get clients {
    final manager = _manager;
    if (manager == null) return const [];
    final filter = _filter;
    if (filter != null) return [filter];
    return manager.clients;
  }

  bool get multiAccount => _filter == null && clients.length > 1;

  ClientManager? get manager => _manager;

  /// Follows the New Home account filter.
  void attach(ClientManager manager, Client? filter) {
    if (!_attachedBus) {
      _attachedBus = true;
      EventBus.onSelectedRoomChanged.stream.listen(_onSelectedRoom);
      EventBus.setFilterClient.stream.listen((c) {
        final m = _manager;
        if (m != null) attach(m, c);
      });
    }
    if (identical(manager, _manager) && identical(filter, _filter)) return;
    _manager = manager;
    _filter = filter;
    final ids = {for (final c in clients) c.identifier};
    for (final id in _servers.keys.toList()) {
      if (!ids.contains(id)) _servers.remove(id)?.dispose();
    }
    _local.removeWhere((id, _) => !ids.contains(id));
    _timeline.removeWhere((id, _) => !ids.contains(id));
    _watchProgress();
    refreshCoverage();
    _loadFullyIndexed();
    if (!query.isEmpty) _schedule(immediate: true);
  }

  SearchIndex<Room, Space>? get nameIndex {
    final manager = _manager;
    if (manager == null) return null;
    return NewHomeSearchIndex.of(manager, _filter);
  }

  Client? clientOf(String accountId) => _manager?.getClient(accountId);

  Room? roomOf(String accountId, String roomId) =>
      clientOf(accountId)?.getRoom(roomId);

  /// The account a room of the scope belongs to (first match).
  Room? anyRoom(String roomId) {
    for (final c in clients) {
      final room = c.getRoom(roomId);
      if (room != null) return room;
    }
    return null;
  }

  // ------------------------------------------------------------- resolving

  /// A room's `in:` scope: "#name", or the person's name for a DM.
  SearchScope<Space> roomScope(Room room) {
    final dm = nameIndex?.docOf(room)?.isDirectMessage ?? false;
    return SearchScope.room(
        room.identifier, dm ? room.displayName : "#${room.displayName}");
  }

  SearchScope<Space>? resolveIn(String value) {
    final index = nameIndex;
    if (index == null) return null;
    final v = value.startsWith("#") ? value.substring(1) : value;
    if (v.trim().isEmpty) return null;
    final found = index.search(v);
    final folded = searchFold(v);
    final exactSpace =
        found.spaces.firstWhereOrNull((s) => s.foldedName == folded);
    if (exactSpace != null) {
      return NewHomeSearchView.spaceScope(index, exactSpace.space);
    }
    final room = found.names.firstOrNull?.room;
    if (room != null) return roomScope(room);
    final space = found.spaces.firstOrNull;
    if (space != null) return NewHomeSearchView.spaceScope(index, space.space);
    return null;
  }

  /// People for a `from:` value: DM partners, then the senders of the
  /// results shown.
  List<({String userId, String name})> fromCandidates(String value,
      {int limit = 8}) {
    final folded =
        searchFold(value.startsWith("@") ? value.substring(1) : value);
    final out = <({String userId, String name})>[];
    final seen = <String>{};
    void add(String userId, String name) {
      if (out.length >= limit || !seen.add(userId)) return;
      if (folded.isNotEmpty &&
          !searchFold(name).contains(folded) &&
          !searchFold(userId).contains(folded)) {
        return;
      }
      out.add((userId: userId, name: name));
    }

    final index = nameIndex;
    if (index != null) {
      for (final doc in index.docs) {
        if (!doc.isDirectMessage) continue;
        final room = doc.room;
        if (room is! MatrixRoom) continue;
        final partner = room.matrixRoom.directChatMatrixID;
        if (partner == null) continue;
        add(partner, doc.partner ?? doc.name);
      }
    }
    for (final r in [...results.local, ...results.server]) {
      final member = roomOf(r.accountId, r.roomId)?.getMember(r.senderId);
      add(r.senderId, member?.displayName ?? r.senderId);
    }
    return out;
  }

  ({String userId, String name})? resolveFrom(String value) =>
      fromCandidates(value, limit: 1).firstOrNull;

  SearchScope<Space>? _resolveSpace(String id) {
    final cut = id.indexOf("|");
    if (cut < 0) return null;
    final space =
        clientOf(id.substring(0, cut))?.getSpace(id.substring(cut + 1));
    final index = nameIndex;
    if (space == null || index == null) return null;
    return NewHomeSearchView.spaceScope(index, space);
  }

  /// A room and the rooms it replaced (its upgrade chain), newest first.
  List<String> chainOf(String roomId) {
    final out = <String>[];
    var room = anyRoom(roomId);
    while (room != null && out.length < 10) {
      out.add(room.identifier);
      final previous = room.replacement?.predecessor?.roomId;
      if (previous == null || out.contains(previous)) break;
      room = room.client.getRoom(previous);
    }
    return out;
  }

  /// Whether a result is from an earlier version of the scoped room.
  bool isOldVersion(DeepSearchResult r) {
    final scoped = query.scope?.roomId;
    return scoped != null && r.roomId != scoped;
  }

  // ----------------------------------------------------------------- query

  /// The page shows; [q] (when given) replaces the query.
  /// [page]: the desktop's Home page shows it (the phone pushes a route).
  void show({DeepSearchQuery<Space>? q, bool focus = true, bool page = true}) {
    if (page) isOpen = true;
    wantsFocus = focus;
    if (q != null) {
      setQuery(q, immediate: true);
    } else {
      notifyListeners();
    }
    refreshCoverage();
  }

  void hide() {
    if (!isOpen) return;
    isOpen = false;
    notifyListeners();
  }

  void setQuery(DeepSearchQuery<Space> q, {bool immediate = false}) {
    final changed = q.normalized != query.normalized ||
        q.scope?.roomId != query.scope?.roomId;
    query = q;
    if (changed) {
      expanded.clear();
      scrollOffset = 0;
      _scopedCoverage();
    }
    notifyListeners();
    if (changed || immediate) _schedule(immediate: immediate);
  }

  void setNewestFirst(bool value) {
    if (newestFirst == value) return;
    newestFirst = value;
    notifyListeners();
    _schedule(immediate: true);
  }

  /// Enter: commit the last typed token, search now, remember it.
  void submit() {
    final q = parser.parse(query.text, onto: query, commitLast: true);
    query = q;
    _schedule(immediate: true, submit: true);
    if (!q.isEmpty) recent.remember(q);
    notifyListeners();
  }

  /// The words worth highlighting in a row.
  List<String> get highlightWords => [
        for (final w in query.words)
          if (w.isNotEmpty) w.toLowerCase()
      ];

  /// Whether the field holds too little to search (Decision 5: no search
  /// on one character).
  bool get tooShort =>
      query.tokens.isEmpty && query.words.join().runes.length < 2;

  void _schedule({bool immediate = false, bool submit = false}) {
    _localTimer?.cancel();
    final gen = ++_generation;
    if (query.isEmpty || tooShort) {
      _local.clear();
      _timeline.clear();
      for (final s in _servers.values) {
        s.update(query, null, const DeepSearchServerContext());
      }
      results = DeepSearchResults.empty;
      searchingLocal = false;
      notifyListeners();
      return;
    }
    lastSearch = query;
    searchingLocal = true;
    void run() => _run(gen, submit: submit);
    if (immediate) {
      run();
    } else {
      _localTimer = Timer(localDebounce, run);
    }
  }

  Future<void> _run(int gen, {bool submit = false}) async {
    final q = query;
    final index = nameIndex;
    for (final client in clients) {
      if (gen != _generation) return;
      final id = client.identifier;
      List<String>? roomIds;
      if (index != null) {
        roomIds = deepSearchScopeRoomIds<Room, Space>(
            q.scope, index, (r) => r.identifier,
            chainOf: chainOf);
      }
      final comp = client.getComponent<MatrixEncryptedSearchIndexComponent>();
      final mx = client is MatrixClient ? client.getMatrixClient() : null;
      final ignored = mx?.ignoredUsers ?? const <String>[];
      final names = [
        if (client.self?.displayName case final String n)
          if (n.isNotEmpty) n
      ];
      try {
        if (comp != null && comp.available && mx != null) {
          final local = await deepSearchTimeLocal(() => comp.searchAll(
              q.toIndexQuery(
                  roomIds: roomIds, ignoredUsers: ignored, myNames: names),
              ranking: _ranking(mx)));
          if (gen != _generation) return;
          if (local == null) return; // a newer search took over
          _local[id] = local;
          _timeline[id] = const [];
        } else {
          _local[id] = null;
          _timeline[id] = _timelineHits(client, q, roomIds, ignored);
        }
      } catch (e, s) {
        Log.onError(e, s, content: "Deep Search: local search failed");
        _local[id] = null;
        _timeline[id] = const [];
      }

      if (mx != null) {
        final server = _serverOf(id, mx);
        List<String>? rooms;
        if (roomIds != null) {
          final covered = deepSearchMatrixContext(mx,
                  fullyIndexed: _fullyIndexed[id] ?? const {})
              .coveredRoomIds;
          rooms = [
            for (final r in roomIds)
              if (!covered.contains(r)) r
          ];
        }
        final filter = q.toServerFilter(rooms: rooms, ignoredUsers: ignored);
        final ctx = deepSearchMatrixContext(mx,
            fullyIndexed: _fullyIndexed[id] ?? const {}, myNames: names);
        if (submit) {
          server.submit(q, filter, ctx);
        } else {
          server.update(q, filter, ctx);
        }
      }
    }
    if (gen != _generation) return;
    searchingLocal = false;
    _merge();
  }

  IndexRanking _ranking(matrix.Client mx) => IndexRanking(
        dmRoomIds: {
          for (final r in mx.rooms)
            if (r.isDirectChat) r.id
        },
        favoriteRoomIds: {
          for (final r in mx.rooms)
            if (r.isFavourite) r.id
        },
        newestFirst: newestFirst,
      );

  /// Without an index (the web): what's loaded in the chats' timelines.
  List<DeepSearchResult> _timelineHits(Client client, DeepSearchQuery<Space> q,
      List<String>? roomIds, List<String> ignored) {
    final words = [for (final w in q.words) searchFold(w)];
    final from = q.fromUserIds;
    final before = q.beforeTs;
    final after = q.afterTs;
    final has = q.has;
    final me = client.self?.identifier;
    final rooms = roomIds == null
        ? client.rooms.toList()
        : [
            for (final id in roomIds)
              if (client.getRoom(id) case final Room r) r
          ];
    final out = <DeepSearchResult>[];
    for (final room in rooms) {
      final events = room.timeline?.events ?? const [];
      for (final e in events) {
        if (e is! TimelineEventMessage) continue;
        if (ignored.contains(e.senderId)) continue;
        if (from.isNotEmpty && !from.contains(e.senderId)) continue;
        final ts = e.originServerTs.millisecondsSinceEpoch;
        if (before != null && ts >= before) continue;
        if (after != null && ts <= after) continue;
        if (q.mentionsMe && (me == null || !e.mentions.contains(me))) {
          continue;
        }
        final body = e.body ?? e.plainTextBody;
        if (has.contains(DeepSearchHas.link) &&
            !RegExp(r"https?://", caseSensitive: false).hasMatch(body)) {
          continue;
        }
        // Other has: kinds need the index's kinds; the web has none.
        if (has.any((h) => h != DeepSearchHas.link)) continue;
        final folded = searchFold(body);
        if (!words.every(folded.contains)) continue;
        out.add(DeepSearchResult(
            accountId: client.identifier,
            roomId: room.identifier,
            eventId: e.eventId,
            senderId: e.senderId,
            ts: ts,
            source: DeepSearchSource.timeline,
            content: {"body": body}));
        if (out.length >= 200) break;
      }
    }
    out.sort((a, b) => b.ts.compareTo(a.ts));
    return out;
  }

  DeepSearchServerController<Space> _serverOf(String id, matrix.Client mx) {
    final existing = _servers[id];
    if (existing != null) return existing;
    final controller =
        DeepSearchServerController<Space>(fetch: deepSearchMatrixFetch(mx));
    controller.state.addListener(_merge);
    _servers[id] = controller;
    return controller;
  }

  void _merge() {
    final accounts = [
      for (final c in clients)
        DeepSearchAccountHits(
          accountId: c.identifier,
          index: _local[c.identifier],
          timeline: _timeline[c.identifier] ?? const [],
          server: _serverHits(c.identifier),
        )
    ];
    results = query.isEmpty || tooShort
        ? DeepSearchResults.empty
        : DeepSearchResults.merge(query, accounts, newestFirst: newestFirst);
    marks.forSearch(query.normalized);
    notifyListeners();
  }

  List<DeepSearchServerHit> _serverHits(String id) {
    final state = _servers[id]?.state.value;
    if (state == null || state.key != query.normalized) return const [];
    return state.hits;
  }

  DeepSearchServerSummary get server {
    if (debugServerSummary case final s?) return s;
    final states = [
      for (final c in clients)
        if (_servers[c.identifier]?.state.value case final s?)
          if (s.key == query.normalized) s
    ];
    if (states.isEmpty) return const DeepSearchServerSummary();
    return DeepSearchServerSummary(
      loading: states.any((s) => s.loading),
      loadingMore: states.any((s) => s.loadingMore),
      failed: states.any((s) => s.error != null),
      skipped: states.every((s) => s.skipped),
      canLoadMore: states.any((s) => s.canLoadMore),
    );
  }

  void loadMoreFromServer() {
    for (final s in _servers.values) {
      if (s.state.value.canLoadMore) s.loadMore();
    }
  }

  /// Retry after a failed server search.
  void retryServer() {
    for (final s in _servers.values) {
      s.clearCache();
    }
    _schedule(immediate: true, submit: true);
  }

  /// Unencrypted DMs the index holds fully: the server needn't search them.
  Future<void> _loadFullyIndexed() async {
    for (final client in clients) {
      if (client is! MatrixClient) continue;
      final comp = client.getComponent<MatrixEncryptedSearchIndexComponent>();
      if (comp == null || !comp.available) continue;
      final out = <String>{};
      try {
        for (final r in client.getMatrixClient().rooms) {
          if (!r.isDirectChat || r.encrypted) continue;
          if ((await comp.coverage(r.id)).complete) out.add(r.id);
        }
      } catch (e, s) {
        Log.onError(e, s, content: "Deep Search: DM coverage failed");
      }
      _fullyIndexed[client.identifier] = out;
    }
  }

  // -------------------------------------------------------------- coverage

  void _watchProgress() {
    for (final client in clients) {
      final id = client.identifier;
      if (_progressListeners.containsKey(id)) continue;
      final comp = client.getComponent<MatrixEncryptedSearchIndexComponent>();
      if (comp == null) continue;
      void listener() {
        _states[id] = comp.progress.value.state;
        // Totals are a query; at most every few seconds.
        _coverageTimer ??= Timer(const Duration(seconds: 5), () {
          _coverageTimer = null;
          refreshCoverage();
        });
        notifyListeners();
      }

      comp.progress.addListener(listener);
      _progressListeners[id] = listener;
    }
  }

  Future<void> refreshCoverage() async {
    for (final client in clients) {
      final id = client.identifier;
      final comp = client.getComponent<MatrixEncryptedSearchIndexComponent>();
      if (comp == null || !comp.available) {
        _states[id] = EncryptedIndexState.unavailable;
        continue;
      }
      _states[id] = comp.progress.value.state;
      try {
        _totals[id] = await comp.coverageTotals();
      } catch (e, s) {
        Log.onError(e, s, content: "Deep Search: coverage failed");
      }
    }
    await _scopedCoverage(notify: false);
    notifyListeners();
  }

  Future<void> _scopedCoverage({bool notify = true}) async {
    final roomId = query.scope?.roomId;
    scopedCoverage = null;
    if (roomId == null) return;
    final room = anyRoom(roomId);
    final comp =
        room?.client.getComponent<MatrixEncryptedSearchIndexComponent>();
    if (comp == null || !comp.available) return;
    try {
      scopedCoverage = await comp.coverage(roomId);
    } catch (e, s) {
      Log.onError(e, s, content: "Deep Search: room coverage failed");
    }
    if (notify) notifyListeners();
  }

  /// The index state shown: the first account with an index (All
  /// accounts sums the totals; the state is the first account's).
  EncryptedIndexState get indexState {
    if (debugCoverage case final d?) return d.state;
    for (final c in clients) {
      final s = _states[c.identifier];
      if (s != null && s != EncryptedIndexState.unavailable) return s;
    }
    return EncryptedIndexState.unavailable;
  }

  bool get indexAvailable =>
      debugCoverage != null ||
      clients.any((c) =>
          c.getComponent<MatrixEncryptedSearchIndexComponent>()?.available ??
          false);

  IndexCoverageTotals get totals =>
      debugCoverage?.totals ??
      deepSearchSumTotals([
        for (final c in clients)
          if (_totals[c.identifier] case final t?) t
      ]);

  MatrixEncryptedSearchIndexComponent? get _firstIndex {
    for (final c in clients) {
      final comp = c.getComponent<MatrixEncryptedSearchIndexComponent>();
      if (comp != null && comp.available) return comp;
    }
    return null;
  }

  bool get wifiOnly => encryptedIndexMode == EncryptedIndexMode.wifiOnly;

  static int? _createdTs(Room? room) {
    if (room is! MatrixRoom) return null;
    final create = room.matrixRoom.getState(matrix.EventTypes.RoomCreate);
    return create is matrix.Event
        ? create.originServerTs.millisecondsSinceEpoch
        : null;
  }

  /// The coverage lines (Mockup 5), most limiting first.
  List<DeepSearchCoverageLine> coverageLines() {
    final roomId = query.scope?.roomId;
    DeepSearchRoomCoverageInput? room;
    if (roomId != null) {
      final r = anyRoom(roomId);
      final indexed = r is MatrixRoom &&
          MatrixEncryptedSearchIndexComponent.isIndexed(r.matrixRoom);
      room = DeepSearchRoomCoverageInput(
          name: query.scope?.label ?? roomId,
          indexed: indexed,
          coverage: scopedCoverage ?? RoomCoverage.unknown,
          createdTs: _createdTs(r));
    }
    final server = this.server;
    return deepSearchCoverage(DeepSearchCoverageInput(
      state: indexState,
      totals: totals,
      indexAvailable: indexAvailable,
      online: true,
      serverWanted: !server.skipped,
      serverFailed: server.failed,
      mobileDataNeedsConfirmation:
          _firstIndex?.indexOlderNeedsConfirmation ?? false,
      room: room,
    ));
  }

  /// Mockup 2B's line under the bar.
  String get coverageSummary =>
      deepSearchCoverageSummary(indexState, totals, wifiOnly: wifiOnly);

  void allowMobileData() {
    for (final c in clients) {
      c
          .getComponent<MatrixEncryptedSearchIndexComponent>()
          ?.allowMobileDataThisSession();
    }
    refreshCoverage();
  }

  /// "Look further back" in the scoped room.
  Future<void> lookFurtherBack() async {
    final roomId = query.scope?.roomId;
    if (roomId == null) return;
    final comp = anyRoom(roomId)
        ?.client
        .getComponent<MatrixEncryptedSearchIndexComponent>();
    if (comp == null) return;
    try {
      final step = await comp.indexOlder(roomId);
      scopedCoverage = step.coverage;
    } catch (e, s) {
      Log.onError(e, s, content: "Deep Search: indexing older failed");
    }
    _schedule(immediate: true);
  }

  // ------------------------------------------------------------ opening

  /// Opens [r] at its message (a thread reply in the thread view). False
  /// when its room is gone ("You left this room").
  bool open(DeepSearchResult r) {
    final room = roomOf(r.accountId, r.roomId);
    if (room == null ||
        (room is MatrixRoom &&
            room.matrixRoom.membership == matrix.Membership.leave)) {
      return false;
    }
    final list = deepSearchOpenOrder(results);
    if (list.isNotEmpty) {
      openList = list;
      openIndex = list.indexWhere((e) => e.key == r.key);
      if (openIndex! < 0) openIndex = null;
    }
    marks.forSearch(query.normalized);
    marks.opened(r);
    if (!query.isEmpty) recent.remember(query);
    isOpen = false;
    _expectedRoomId = r.roomId;
    notifyListeners();

    final thread = r.threadRoot;
    EventBus.doOpenRoom(r.roomId,
        clientId: r.accountId, eventId: thread ?? r.eventId);
    if (thread != null && thread != r.eventId) {
      // The room opens first; then its thread, beside it.
      Future.delayed(const Duration(milliseconds: 400), () {
        EventBus.openThread.add((r.accountId, r.roomId, thread));
      });
    }
    return true;
  }

  /// The results bar's ↑ (-1) / ↓ (+1): the previous or next result,
  /// across chats. False when there is none, or its room is gone.
  bool step(int delta) {
    final next = deepSearchStep(openIndex, openList.length, delta);
    if (next == null) return false;
    final r = openList[next];
    final ok = open(r);
    if (!ok) {
      // Skip past it next time.
      openIndex = next;
      notifyListeners();
    }
    return ok;
  }

  /// × on the bar, or a chat opened from elsewhere.
  void endRun() {
    if (openIndex == null && openList.isEmpty) return;
    openIndex = null;
    openList = const [];
    _expectedRoomId = null;
    notifyListeners();
  }

  void _onSelectedRoom(Room? room) {
    if (room == null) return;
    if (room.identifier == _expectedRoomId) {
      _expectedRoomId = null;
      return;
    }
    final hit = openHit;
    if (hit != null && room.identifier != hit.roomId) endRun();
  }
}
