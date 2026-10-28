// Vommet (issues 602, 611): a search index of the account's ENCRYPTED rooms,
// built in the background so in-chat search and the DM panel's Shared
// counts don't have to page through a room's whole history every time.
// The server can't search or count encrypted messages; unencrypted rooms
// keep using server search.
//
// Where it lives: `<drift dir>/<client>/search_index.db`, beside the
// account's message store `data.db`. The SDK already keeps decrypted
// messages there (the sync's and the history it loads), in the same
// directory with the same protection, so the index adds no new exposure;
// it is deleted with the account on logout and emptied by Clear cache.
// The web version has no index (search pages back live, as before).
//
// Scanning: /messages pages (100 events) are fetched and decrypted here,
// then stored by the index isolate (SearchIndexWorker), which also runs
// every query. Each stretch of history is scanned once (see the segments
// in search_index_store.dart). Messages arriving by sync are added as they
// come. Settings › Privacy › Search › "Index encrypted chats": Off / Wi-Fi
// only / Always (default Always on desktop, Wi-Fi only on phones). When
// Off, nothing runs in the background, but a search still pages back
// through [indexOlder] and keeps what it scanned.
//
// API for the DM panel (counts, Media/Files/Links tabs) and in-chat search:
//   available, progress, onRoomUpdated, coverage(), counts(), search(),
//   list(), indexOlder(), clear().
//
// Vommet Deep Search (index v2): every DM is indexed too, encrypted or not
// (unencrypted group rooms stay with server search: busy public rooms
// would grow the file without bound). DMs are built first, then
// favorites, recent rooms, the rest, low priority last. Adds searchAll()
// (across rooms, ranked, stale searches dropped), coverageTotals(),
// indexSizeBytes(), indexOlderNeedsConfirmation and
// allowMobileDataThisSession(). Phones pause on battery saver or below 20%
// while not charging. Messages that didn't decrypt are tried again as soon
// as their room gets a key (live or from the backup).
import 'dart:async';
import 'dart:io';

import 'package:commet/client/components/component.dart';
import 'package:commet/telemetry/main_spans.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_backend.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart';
import 'package:commet/client/matrix/components/room_media_history/index_media_history.dart'
    show MediaHistoryIndex;
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/app_config.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/encrypted_search_index_setting.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:commet/utils/power_state.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart' show Encryption;
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/msc_extensions/msc_4186_sliding_sync/gaps.dart'
    show SyncGap;
import 'package:path/path.dart' as p;

export 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart'
    show SharedContentKind;
export 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart'
    show
        IndexQuery,
        IndexHit,
        SharedContentCounts,
        RoomCoverage,
        IndexRanking,
        IndexSearchResult,
        IndexCoverageTotals,
        IndexPostedInCache;

enum EncryptedIndexState {
  /// The web version, or the index failed to open.
  unavailable,
  off,
  waitingForWifi,

  /// Phones: battery saver is on, or the battery is low and not charging.
  pausedForBattery,
  running,
  done,
}

/// "Indexed [indexed] of [total] chats" (encrypted chats and DMs).
class EncryptedIndexProgress {
  const EncryptedIndexProgress(
      {this.indexed = 0, this.total = 0, required this.state});
  final int indexed;
  final int total;
  final EncryptedIndexState state;

  double get fraction => total == 0 ? 1 : indexed / total;

  @override
  bool operator ==(Object other) =>
      other is EncryptedIndexProgress &&
      other.indexed == indexed &&
      other.total == total &&
      other.state == state;

  @override
  int get hashCode => Object.hash(indexed, total, state);
}

/// What one [MatrixEncryptedSearchIndexComponent.indexOlder] call did.
class IndexStepResult {
  const IndexStepResult({required this.added, required this.coverage});
  final int added;
  final RoomCoverage coverage;
}

class MatrixEncryptedSearchIndexComponent
    implements
        Component<MatrixClient>,
        NeedsPostLoginInit,
        NeedsCloseOnClientClose,
        MediaHistoryIndex {
  @override
  final MatrixClient client;

  /// [backend] and [startBackground] are for unit tests.
  MatrixEncryptedSearchIndexComponent(this.client,
      {SearchIndexBackend? backend, bool startBackground = true})
      : _startBackground = startBackground {
    if (backend != null) _opening = Future.value(backend);
  }

  static const pageSize = 100;

  /// Pause between pages, so a long backfill stays gentle.
  ///
  /// Vommet: was 250 ms (600 ms on phones), and every sync cut it short. On
  /// a large account the backfill then sent ~1,300 /messages requests and
  /// ~90 MB every 15 minutes for hours, and ~2,800 in the first 15 minutes,
  /// competing with the start for the connection and the main isolate
  /// (each page is decrypted there). Now at least this long, and at least
  /// twice as long as the page itself took ([pauseAfter]).
  static final Duration pagePause = BuildConfig.MOBILE
      ? const Duration(milliseconds: 1500)
      : const Duration(seconds: 1);

  /// Vommet: the background backfill starts this long after sign-in or
  /// app start, so the room list, names and pictures load first. A search
  /// or a tab ([indexOlder]) doesn't wait; new messages are stored as they
  /// arrive.
  static Duration startDelay = BuildConfig.MOBILE
      ? const Duration(seconds: 90)
      : const Duration(seconds: 45);

  /// Vommet: how long the backfill rests after a page that took [took]
  /// (fetching, decrypting and storing it): the background index uses at
  /// most about a third of the time.
  static Duration pauseAfter(Duration took) {
    final twice = took * 2;
    return twice > pagePause ? twice : pagePause;
  }

  final bool _startBackground;
  Future<SearchIndexBackend?>? _opening;
  bool _closed = false;
  bool _started = false;

  final ValueNotifier<EncryptedIndexProgress> progress = ValueNotifier(
      const EncryptedIndexProgress(state: EncryptedIndexState.off));

  final StreamController<String> _roomUpdated = StreamController.broadcast();

  /// A room id each time messages of that room were added to the index
  /// (counts and lists may have changed).
  Stream<String> get onRoomUpdated => _roomUpdated.stream;

  final List<StreamSubscription> _subs = [];
  final Map<String, List<Map<String, dynamic>>> _liveBuffer = {};
  final Map<String, Future<void>> _roomLocks = {};
  final Set<String> _topScanned = {};
  final Set<String> _failedRooms = {};
  Completer<void>? _wake;

  /// Vommet: ends a pacing pause early (closing, the setting changed); a
  /// sync only ends the idle wait ([_wake]).
  Completer<void>? _pauseWake;
  DateTime? _backgroundFrom;
  bool _loopRunning = false;
  MediaNetwork _network = MediaNetwork.wifi;
  Duration _backoff = Duration.zero;
  DateTime? _undecryptedRetryAt;

  /// Deep Search: battery saver or a low battery (phones).
  bool _lowPower = false;
  Timer? _powerTimer;

  /// Deep Search: "Index on mobile data this session".
  bool _mobileDataThisSession = false;

  /// Deep Search: rooms with undecryptable messages, listening for keys.
  final Map<String, StreamSubscription> _keyWatches = {};
  final Set<String> _keyRetryRooms = {};
  Timer? _keyRetryTimer;

  bool _migrating = false;
  DateTime? _keyWatchAt;
  int _searchGeneration = 0;
  Future<void>? _searchRunning;

  /// Deep Search: the rooms the own user posted in ([postedInRoomIds]).
  final IndexPostedInCache _postedIn = IndexPostedInCache();

  matrix.Client get _mx => client.getMatrixClient();

  /// Whether this platform has an index (not the web version).
  bool get available => !kIsWeb;

  // ---- lifecycle ---------------------------------------------------------

  // Vommet: the index's loops and listeners run in a span of their own
  // (opt-in diagnostics).
  @override
  void postLoginInit() => MainSpans.zone("Search_index", _postLoginInit);

  void _postLoginInit() {
    // Not in the push notification process.
    if (_started || !available || isHeadless) return;
    _started = true;
    // Counted from sign-in, not from when the backfill first may run.
    _backgroundFrom ??= DateTime.now().add(startDelay);
    _subs.add(_mx.onTimelineEvent.stream.listen(_onTimelineEvent));
    _subs.add(_mx.onSync.stream.listen(_onSync));
    _subs.add(encryptedIndexModePreference.onChanged.listen((_) {
      _updateProgress();
      _kick(urgent: true);
    }));
    if (BuildConfig.MOBILE) {
      _watchNetwork();
      _watchPower();
    }
    _updateProgress();
    if (_startBackground) {
      _kick();
      unawaited(_migrate());
    }
  }

  /// Checks the battery now and every 2 minutes (phones).
  void _watchPower() {
    Future<void> check() async {
      final state = await PowerState.read();
      final low = state?.lowPower ?? false;
      if (low == _lowPower) return;
      _lowPower = low;
      _updateProgress();
      _kick(urgent: true);
    }

    unawaited(check());
    _powerTimer =
        Timer.periodic(const Duration(minutes: 2), (_) => unawaited(check()));
  }

  /// Fills the v2 columns and full-text tables from rows stored before
  /// (local work, no network), in small steps after the start delay.
  Future<void> _migrate() async {
    if (_migrating) return;
    _migrating = true;
    try {
      final backend = await _backend();
      if (backend == null) return;
      final from = _backgroundFrom ?? DateTime.now();
      final untilStart = from.difference(DateTime.now());
      if (untilStart > Duration.zero) await Future.delayed(untilStart);
      while (!_closed) {
        if (_lowPower) {
          await Future.delayed(const Duration(minutes: 1));
          continue;
        }
        final left = await backend.migrateStep();
        if (left == 0) break;
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Index: upgrading the index failed");
    } finally {
      _migrating = false;
    }
  }

  void _watchNetwork() {
    try {
      final connectivity = Connectivity();
      void onResults(List<ConnectivityResult> results) {
        _network = MediaAutoDownload.networkFrom(results);
        _updateProgress();
        _kick(urgent: true);
      }

      connectivity.checkConnectivity().then(onResults,
          onError: (Object e) => Log.w("Index: connectivity check failed: $e"));
      _subs.add(connectivity.onConnectivityChanged.listen(onResults,
          onError: (Object e) => Log.w("Index: connectivity failed: $e")));
    } catch (e) {
      Log.w("Index: connectivity unavailable, treating as Wi-Fi: $e");
    }
  }

  @override
  Future<void> onClientClosed() async {
    _closed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _stopWatching();
    _kick(urgent: true);
    final backend = await _opening;
    _opening = null;
    await backend?.close();
  }

  Future<SearchIndexBackend?> _backend() {
    if (!available || _closed) return Future.value(null);
    return _opening ??= _open();
  }

  Future<String> _path() async => p.join(await AppConfig.getDriftDatabasePath(),
      _mx.clientName, "search_index.db");

  void _stopWatching() {
    _powerTimer?.cancel();
    _keyRetryTimer?.cancel();
    for (final s in _keyWatches.values) {
      s.cancel();
    }
    _keyWatches.clear();
  }

  Future<SearchIndexBackend?> _open() async {
    try {
      final path = await _path();
      await Directory(p.dirname(path)).create(recursive: true);
      return await openSearchIndexBackend(path,
          ownUserId: _mx.userID, account: _mx.clientName);
    } catch (e, s) {
      Log.onError(e, s, content: "Encrypted search index failed to open");
      progress.value =
          const EncryptedIndexProgress(state: EncryptedIndexState.unavailable);
      return null;
    }
  }

  /// Deletes the index file (logout).
  Future<void> deleteIndex() async {
    _closed = true;
    _stopWatching();
    _kick(urgent: true);
    final backend = await _opening;
    _opening = null;
    await backend?.close();
    if (!available) return;
    try {
      final path = await _path();
      for (final suffix in const ["", "-wal", "-shm"]) {
        final f = File("$path$suffix");
        if (await f.exists()) await f.delete();
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Could not delete the search index");
    }
  }

  // ---- public API ----------------------------------------------------------

  /// Joined rooms the index holds (encrypted rooms and every DM), in the
  /// order they're built: DMs, favorites, rooms active in the last 30
  /// days, the rest, low priority last; most recently active first within
  /// each.
  List<String> encryptedRoomIds() {
    final recent = DateTime.now().subtract(const Duration(days: 30));
    int group(matrix.Room r) {
      if (r.tags.containsKey(matrix.TagType.lowPriority)) return 4;
      if (r.isDirectChat) return 0;
      if (r.isFavourite) return 1;
      if (r.latestEventReceivedTime.isAfter(recent)) return 2;
      return 3;
    }

    final rooms = [
      for (final r in _mx.rooms)
        if (isIndexed(r) && r.membership == matrix.Membership.join) r
    ];
    final order = {for (final (i, r) in rooms.indexed) r.id: i};
    rooms.sort((a, b) {
      final byGroup = group(a).compareTo(group(b));
      return byGroup != 0 ? byGroup : order[a.id]!.compareTo(order[b.id]!);
    });
    return [for (final r in rooms) r.id];
  }

  /// Whether [room]'s messages go in the index: encrypted rooms and every
  /// DM (encrypted or not).
  static bool isIndexed(matrix.Room room) =>
      room.encrypted || room.isDirectChat;

  Future<RoomCoverage> coverage(String roomId) async =>
      await (await _backend())?.coverage(roomId) ?? RoomCoverage.unknown;

  /// Counts of what was shared in [roomId], as far as indexed; check
  /// [coverage] `complete` to tell exact counts from "37+".
  Future<SharedContentCounts> counts(String roomId) async =>
      await (await _backend())?.counts(roomId) ?? const SharedContentCounts();

  /// Indexed messages of [roomId] matching [query], newest first. Doesn't
  /// scan; call [indexOlder] for more history.
  Future<List<IndexHit>> search(String roomId, IndexQuery query,
          {int? beforeTs, int limit = 500}) async =>
      await (await _backend())
          ?.search(roomId, query, beforeTs: beforeTs, limit: limit) ??
      const [];

  /// Indexed messages of [roomId] of the given [kinds] (or with links),
  /// newest first, for the Media/Files/Links tabs.
  @override
  Future<List<IndexHit>> list(String roomId,
          {Set<SharedContentKind> kinds = const {},
          bool linksOnly = false,
          int? beforeTs,
          String? beforeEventId,
          int limit = 100}) async =>
      await (await _backend())?.list(roomId,
          kinds: kinds,
          linksOnly: linksOnly,
          beforeTs: beforeTs,
          beforeEventId: beforeEventId,
          limit: limit) ??
      const [];

  /// Vommet: readies [roomId] for [list] without scanning: once per run it
  /// notes the messages that arrived while the app was closed as a gap to
  /// scan first. Returns what the index covers.
  @override
  Future<RoomCoverage> prepare(String roomId) async {
    final backend = await _backend();
    if (backend == null) return RoomCoverage.unknown;
    await _prepareRoom(backend, roomId);
    return backend.coverage(roomId);
  }

  /// Vommet: whether the Media tab may page this index now: it opened and
  /// [indexOlder] wouldn't need asking first (the setting isn't Off, nor
  /// "Wi-Fi only" on mobile data). A battery pause only stops the
  /// background indexer: the tab's own pages still scan.
  bool get usableNow =>
      available &&
      !_closed &&
      !indexOlderNeedsConfirmation &&
      progress.value.state != EncryptedIndexState.unavailable;

  /// Scans one more page of [roomId] now, whatever the setting (a search or
  /// a tab waiting for results). Messages newer than what's indexed come
  /// first, then older history. Shares the work with the background
  /// indexer, so nothing is scanned twice.
  @override
  Future<IndexStepResult> indexOlder(String roomId) async {
    final backend = await _backend();
    if (backend == null) {
      return const IndexStepResult(added: 0, coverage: RoomCoverage.unknown);
    }
    await _prepareRoom(backend, roomId);
    final result = await _locked(roomId, () => _step(backend, roomId));
    _updateProgress();
    return result;
  }

  /// Vommet Deep Search: messages matching [query] across the indexed rooms
  /// (or [IndexQuery.roomIds]), ranked. Runs on the index's read
  /// connection; when a newer search starts before this one ran, this one
  /// returns null instead of running (typing never queues searches).
  Future<IndexSearchResult?> searchAll(IndexQuery query,
      {IndexRanking ranking = const IndexRanking(), int limit = 200}) async {
    final generation = ++_searchGeneration;
    while (_searchRunning != null) {
      await _searchRunning;
      if (generation != _searchGeneration) return null;
    }
    final backend = await _backend();
    if (backend == null) return IndexSearchResult.empty;
    if (generation != _searchGeneration) return null;
    final done = Completer<void>();
    _searchRunning = done.future;
    try {
      final result =
          await backend.searchAll(query, ranking: ranking, limit: limit);
      return generation == _searchGeneration ? result : null;
    } finally {
      _searchRunning = null;
      done.complete();
    }
  }

  /// Vommet Deep Search: coverage across the indexed rooms (the coverage
  /// line), or of [roomIds].
  Future<IndexCoverageTotals> coverageTotals([List<String>? roomIds]) async {
    final ids = roomIds ?? encryptedRoomIds();
    return await (await _backend())?.coverageTotals(ids) ??
        IndexCoverageTotals(rooms: ids.length);
  }

  /// Vommet Deep Search: the rooms the own user has a message in, for the
  /// "rooms I've posted in" boost. Cached; asked again once the own user's
  /// message is indexed, or after a few minutes.
  Future<Set<String>> postedInRoomIds() async {
    final cached = _postedIn.fresh;
    if (cached != null) return cached;
    final me = _mx.userID;
    final backend = await _backend();
    if (me == null || backend == null) return const {};
    final rooms = (await backend.roomsPostedIn(me)).toSet();
    _postedIn.store(rooms);
    return rooms;
  }

  /// The index's size on disk (Settings › Privacy › Search).
  Future<int> indexSizeBytes() async {
    if (!available) return 0;
    try {
      final path = await _path();
      var size = 0;
      for (final suffix in const ["", "-wal"]) {
        final f = File("$path$suffix");
        if (await f.exists()) size += await f.length();
      }
      return size;
    } catch (_) {
      return 0;
    }
  }

  /// Vommet Deep Search: whether "Look further back" ([indexOlder]) should
  /// ask first: indexing is Off (people pick Off to keep decrypted text off
  /// the disk), or a phone set to Wi-Fi only is on mobile data.
  bool get indexOlderNeedsConfirmation {
    if (!available) return false;
    return switch (encryptedIndexMode) {
      EncryptedIndexMode.off => true,
      EncryptedIndexMode.wifiOnly => BuildConfig.MOBILE &&
          _network != MediaNetwork.wifi &&
          !_mobileDataThisSession,
      EncryptedIndexMode.always => false,
    };
  }

  /// Vommet Deep Search: "Index on mobile data this session" (until the
  /// app restarts).
  void allowMobileDataThisSession() {
    _mobileDataThisSession = true;
    _updateProgress();
    _kick(urgent: true);
  }

  /// Empties the index; it builds again unless indexing is off.
  Future<void> clear() async {
    final backend = await _backend();
    if (backend == null) return;
    await backend.clear();
    _topScanned.clear();
    _failedRooms.clear();
    _liveBuffer.clear();
    _postedIn.invalidate();
    _updateProgress();
    _kick(urgent: true);
  }

  // ---- background ----------------------------------------------------------

  bool get _backgroundAllowed {
    if (_closed || !available) return false;
    return switch (encryptedIndexMode) {
          EncryptedIndexMode.off => false,
          EncryptedIndexMode.wifiOnly => !BuildConfig.MOBILE ||
              _network == MediaNetwork.wifi ||
              _mobileDataThisSession,
          EncryptedIndexMode.always => true,
        } &&
        !_lowPower;
  }

  void _kick({bool urgent = false}) {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
    if (urgent) {
      final pause = _pauseWake;
      _pauseWake = null;
      if (pause != null && !pause.isCompleted) pause.complete();
    }
    if (!_loopRunning && _backgroundAllowed && _startBackground) {
      unawaited(_loop());
    }
  }

  Future<void> _loop() async {
    if (_loopRunning) return;
    _loopRunning = true;
    try {
      final backend = await _backend();
      if (backend == null) return;
      // Vommet: let the start finish first (see [startDelay]).
      // A setting or network change wakes the pause; the start still
      // waits its full time.
      final from = _backgroundFrom ??= DateTime.now().add(startDelay);
      while (_backgroundAllowed) {
        final untilStart = from.difference(DateTime.now());
        if (untilStart <= Duration.zero) break;
        await _pause(untilStart);
      }
      while (_backgroundAllowed) {
        final rooms = encryptedRoomIds();
        for (final id in rooms) {
          await _prepareRoom(backend, id);
        }
        final candidates =
            rooms.where((r) => !_failedRooms.contains(r)).toList();
        final now = DateTime.now();
        if (_keyWatchAt == null || now.isAfter(_keyWatchAt!)) {
          _keyWatchAt = now.add(const Duration(minutes: 2));
          await _watchKeys(backend);
        }
        final next = await backend.nextRoom(candidates);
        _updateProgress(running: next != null);
        if (next == null) {
          await _retryUndecrypted(backend);
          _wake = Completer();
          await _wake!.future;
          continue;
        }
        // Only the page itself, not a wait for a search scanning the room.
        final took = Stopwatch();
        try {
          await _locked(next, () {
            took.start();
            return _step(backend, next);
          });
          _backoff = Duration.zero;
        } catch (e) {
          if (e is matrix.MatrixException &&
              e.error != matrix.MatrixError.M_LIMIT_EXCEEDED) {
            // Left, banned, or a room the server won't page: skip it until
            // the next start.
            Log.w("Index: skipping $next: ${e.errcode}");
            _failedRooms.add(next);
            await _pause(pagePause);
            continue;
          }
          _backoff = _backoff == Duration.zero
              ? const Duration(seconds: 30)
              : _backoff * 2;
          if (_backoff > const Duration(minutes: 10)) {
            _backoff = const Duration(minutes: 10);
          }
          Log.w("Index: page failed ($e), retrying in ${_backoff.inSeconds}s");
          await _pause(_backoff);
          continue;
        }
        await _pause(pauseAfter(took.elapsed));
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Encrypted search index stopped");
    } finally {
      _loopRunning = false;
      _updateProgress();
    }
  }

  /// Waits [d], or less when the index closes or its setting changes
  /// (not when a sync arrives: that used to end every pause early).
  Future<void> _pause(Duration d) {
    final wake = _pauseWake = Completer();
    return Future.any([Future.delayed(d), wake.future]);
  }

  /// Once per run, also scans what arrived while the app was closed.
  ///
  /// Vommet: not when the room's newest message is already in the index
  /// (nothing came in, or the sync brought it). That scan cost one
  /// /messages request per indexed chat on every start and update.
  Future<void> _prepareRoom(SearchIndexBackend backend, String roomId) async {
    if (_topScanned.contains(roomId)) return;
    _topScanned.add(roomId);
    final last = _mx
        .getRoomById(roomId)
        ?.lastEvent
        ?.originServerTs
        .millisecondsSinceEpoch;
    if (last != null) {
      final head = (await backend.coverage(roomId)).headTs;
      if (head != null && last <= head) return;
    }
    await backend.addTopSegment(roomId);
  }

  Future<T> _locked<T>(String roomId, Future<T> Function() body) async {
    while (_roomLocks[roomId] != null) {
      await _roomLocks[roomId];
    }
    final done = Completer<void>();
    _roomLocks[roomId] = done.future;
    try {
      return await body();
    } finally {
      _roomLocks.remove(roomId);
      done.complete();
    }
  }

  Future<IndexStepResult> _step(
      SearchIndexBackend backend, String roomId) async {
    final segment = await backend.nextSegment(roomId);
    if (segment == null) {
      return IndexStepResult(
          added: 0, coverage: await backend.coverage(roomId));
    }
    final mx = _mx;
    final room = mx.getRoomById(roomId);
    if (room == null) {
      return IndexStepResult(
          added: 0, coverage: await backend.coverage(roomId));
    }
    // No token = from the newest message (spec v1.3); the sync position
    // isn't one under sliding sync, nor is the marker of a gap sliding sync
    // left without a token (SyncGap).
    final from = SyncGap.messagesFrom(segment.fromToken);
    final response = await mx.getRoomEvents(roomId, matrix.Direction.b,
        from: from, limit: pageSize);

    final decrypted = <Map<String, dynamic>>[];
    final undecrypted = <Map<String, dynamic>>[];
    for (final raw in response.chunk) {
      var event = matrix.Event.fromMatrixEvent(raw, room);
      final encryption = mx.encryption;
      if (event.type == matrix.EventTypes.Encrypted && encryption != null) {
        event = await encryption.decryptRoomEvent(event);
      }
      if (event.type == matrix.EventTypes.Encrypted) {
        undecrypted.add(raw.toJson());
      } else {
        decrypted.add(event.toJson());
      }
    }
    // A page ending where it started (no end token, or the same one) is the
    // start of the room.
    final end = response.end == from ? null : response.end;
    final result = await backend.applyPage(roomId, segment.id, decrypted, end,
        undecrypted: undecrypted);
    if (result.added > 0) _roomUpdated.add(roomId);
    return IndexStepResult(added: result.added, coverage: result.coverage);
  }

  /// Listens for new keys in the rooms with messages that didn't decrypt,
  /// to try those again soon after (not only every 10 minutes).
  Future<void> _watchKeys(SearchIndexBackend backend) async {
    final rooms = (await backend.roomsWithUndecrypted()).toSet();
    for (final id in _keyWatches.keys.toList()) {
      if (!rooms.contains(id)) _keyWatches.remove(id)?.cancel();
    }
    for (final id in rooms) {
      if (_keyWatches.containsKey(id)) continue;
      final room = _mx.getRoomById(id);
      if (room == null) continue;
      _keyWatches[id] = room.onSessionKeyReceived.stream.listen((_) {
        _keyRetryRooms.add(id);
        // Keys come in bursts (a backup restore): retry once they settle.
        _keyRetryTimer?.cancel();
        _keyRetryTimer = Timer(const Duration(seconds: 3), () {
          final ids = Set.of(_keyRetryRooms);
          _keyRetryRooms.clear();
          unawaited(_retryRooms(ids));
        });
      });
    }
  }

  Future<void> _retryRooms(Set<String> roomIds) async {
    if (_closed || encryptedIndexMode == EncryptedIndexMode.off) return;
    final backend = await _backend();
    final encryption = _mx.encryption;
    if (backend == null || encryption == null) return;
    try {
      for (final roomId in roomIds) {
        await _retryRoom(backend, encryption, roomId);
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Index: retrying undecrypted failed");
    }
  }

  Future<void> _retryRoom(
      SearchIndexBackend backend, Encryption encryption, String roomId) async {
    final room = _mx.getRoomById(roomId);
    if (room == null) return;
    final fixed = <Map<String, dynamic>>[];
    for (final json in await backend.undecrypted(roomId)) {
      final event =
          await encryption.decryptRoomEvent(matrix.Event.fromJson(json, room));
      if (event.type != matrix.EventTypes.Encrypted) {
        fixed.add(event.toJson());
      }
    }
    if (fixed.isEmpty) return;
    if (await backend.addLive(roomId, fixed) > 0) {
      _roomUpdated.add(roomId);
    }
  }

  /// Tries the messages that didn't decrypt again (keys may have arrived
  /// from the backup or another device), at most every 10 minutes.
  Future<void> _retryUndecrypted(SearchIndexBackend backend) async {
    final now = DateTime.now();
    if (_undecryptedRetryAt != null && now.isBefore(_undecryptedRetryAt!)) {
      return;
    }
    _undecryptedRetryAt = now.add(const Duration(minutes: 10));
    final encryption = _mx.encryption;
    if (encryption == null) return;
    for (final roomId in await backend.roomsWithUndecrypted()) {
      await _retryRoom(backend, encryption, roomId);
    }
  }

  // ---- live messages -------------------------------------------------------

  void _onTimelineEvent(matrix.Event event) {
    if (encryptedIndexMode == EncryptedIndexMode.off) return;
    if (!isIndexed(event.room)) return;
    if (event.type == matrix.EventTypes.Encrypted) return;
    _liveBuffer.putIfAbsent(event.room.id, () => []).add(event.toJson());
  }

  /// After each sync: stores its messages and moves each room's covered
  /// head on, or notes the gap a limited sync left.
  Future<void> _onSync(matrix.SyncUpdate sync) async {
    final joined = sync.rooms?.join;
    final left = sync.rooms?.leave;
    final buffered = Map.of(_liveBuffer);
    _liveBuffer.clear();
    final backend = await _backend();
    if (backend == null) return;
    try {
      for (final roomId in left?.keys ?? const <String>[]) {
        await backend.deleteRoom(roomId);
      }
      if (encryptedIndexMode == EncryptedIndexMode.off) {
        // Not stored now: scan these rooms from the top when next needed.
        _topScanned.removeAll(joined?.keys ?? const <String>[]);
        return;
      }
      for (final entry in joined?.entries ??
          const <MapEntry<String, matrix.JoinedRoomUpdate>>[]) {
        final roomId = entry.key;
        final room = _mx.getRoomById(roomId);
        if (room == null || !isIndexed(room)) continue;
        final timeline = entry.value.timeline;
        final events = buffered.remove(roomId) ?? const [];
        int? head;
        if (timeline?.limited == true && timeline?.prevBatch != null) {
          await backend.addGapSegment(roomId, timeline!.prevBatch!);
        }
        // Even after a limited sync the newest messages are now covered:
        // the gap segment scans what's between.
        for (final e in timeline?.events ?? const <matrix.MatrixEvent>[]) {
          final ts = e.originServerTs.millisecondsSinceEpoch;
          if (head == null || ts > head) head = ts;
        }
        if (events.isEmpty && head == null) continue;
        final added = await backend.addLive(roomId, events, headTs: head);
        if (added > 0) _roomUpdated.add(roomId);
        if (added > 0 && events.any((e) => e["sender"] == _mx.userID)) {
          _postedIn.invalidate();
        }
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Index: storing new messages failed");
    }
    _kick();
  }

  // ---- progress ------------------------------------------------------------

  Future<void> _updateProgress({bool? running}) async {
    if (!available) {
      progress.value =
          const EncryptedIndexProgress(state: EncryptedIndexState.unavailable);
      return;
    }
    final backend = await _backend();
    if (backend == null) return;
    final rooms = encryptedRoomIds();
    final indexed = await backend.completeCount(rooms);
    final mode = encryptedIndexMode;
    final EncryptedIndexState state;
    if (mode == EncryptedIndexMode.off) {
      state = EncryptedIndexState.off;
    } else if (_lowPower) {
      state = EncryptedIndexState.pausedForBattery;
    } else if (!_backgroundAllowed) {
      state = EncryptedIndexState.waitingForWifi;
    } else if (indexed >= rooms.length && running != true) {
      state = EncryptedIndexState.done;
    } else {
      state = EncryptedIndexState.running;
    }
    progress.value = EncryptedIndexProgress(
        indexed: indexed, total: rooms.length, state: state);
  }
}
