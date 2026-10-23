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
import 'dart:async';
import 'dart:io';

import 'package:commet/client/components/component.dart';
import 'package:commet/telemetry/main_spans.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_backend.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/app_config.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/encrypted_search_index_setting.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:path/path.dart' as p;

export 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart'
    show SharedContentKind;
export 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart'
    show IndexQuery, IndexHit, SharedContentCounts, RoomCoverage;

enum EncryptedIndexState {
  /// The web version, or the index failed to open.
  unavailable,
  off,
  waitingForWifi,
  running,
  done,
}

/// "Indexed [indexed] of [total] encrypted chats".
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
        NeedsCloseOnClientClose {
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
  static final Duration pagePause = BuildConfig.MOBILE
      ? const Duration(milliseconds: 600)
      : const Duration(milliseconds: 250);

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
  bool _loopRunning = false;
  MediaNetwork _network = MediaNetwork.wifi;
  Duration _backoff = Duration.zero;
  DateTime? _undecryptedRetryAt;

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
    _subs.add(_mx.onTimelineEvent.stream.listen(_onTimelineEvent));
    _subs.add(_mx.onSync.stream.listen(_onSync));
    _subs.add(encryptedIndexModePreference.onChanged.listen((_) {
      _updateProgress();
      _kick();
    }));
    if (BuildConfig.MOBILE) _watchNetwork();
    _updateProgress();
    if (_startBackground) _kick();
  }

  void _watchNetwork() {
    try {
      final connectivity = Connectivity();
      void onResults(List<ConnectivityResult> results) {
        _network = MediaAutoDownload.networkFrom(results);
        _updateProgress();
        _kick();
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
    _kick();
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

  Future<SearchIndexBackend?> _open() async {
    try {
      final path = await _path();
      await Directory(p.dirname(path)).create(recursive: true);
      return await openSearchIndexBackend(path);
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
    _kick();
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

  /// Joined encrypted rooms, most recently active first.
  List<String> encryptedRoomIds() => [
        for (final r in _mx.rooms)
          if (r.encrypted && r.membership == matrix.Membership.join) r.id
      ];

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
  Future<List<IndexHit>> list(String roomId,
          {Set<SharedContentKind> kinds = const {},
          bool linksOnly = false,
          int? beforeTs,
          int limit = 100}) async =>
      await (await _backend())?.list(roomId,
          kinds: kinds,
          linksOnly: linksOnly,
          beforeTs: beforeTs,
          limit: limit) ??
      const [];

  /// Scans one more page of [roomId] now, whatever the setting (a search or
  /// a tab waiting for results). Messages newer than what's indexed come
  /// first, then older history. Shares the work with the background
  /// indexer, so nothing is scanned twice.
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

  /// Empties the index; it builds again unless indexing is off.
  Future<void> clear() async {
    final backend = await _backend();
    if (backend == null) return;
    await backend.clear();
    _topScanned.clear();
    _failedRooms.clear();
    _liveBuffer.clear();
    _updateProgress();
    _kick();
  }

  // ---- background ----------------------------------------------------------

  bool get _backgroundAllowed {
    if (_closed || !available) return false;
    return switch (encryptedIndexMode) {
      EncryptedIndexMode.off => false,
      EncryptedIndexMode.wifiOnly =>
        !BuildConfig.MOBILE || _network == MediaNetwork.wifi,
      EncryptedIndexMode.always => true,
    };
  }

  void _kick() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
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
      while (_backgroundAllowed) {
        final rooms = encryptedRoomIds();
        for (final id in rooms) {
          await _prepareRoom(backend, id);
        }
        final candidates =
            rooms.where((r) => !_failedRooms.contains(r)).toList();
        final next = await backend.nextRoom(candidates);
        _updateProgress(running: next != null);
        if (next == null) {
          await _retryUndecrypted(backend);
          _wake = Completer();
          await _wake!.future;
          continue;
        }
        try {
          await _locked(next, () => _step(backend, next));
          _backoff = Duration.zero;
        } catch (e) {
          if (e is matrix.MatrixException &&
              e.error != matrix.MatrixError.M_LIMIT_EXCEEDED) {
            // Left, banned, or a room the server won't page: skip it until
            // the next start.
            Log.w("Index: skipping $next: ${e.errcode}");
            _failedRooms.add(next);
            await _sleep(pagePause);
            continue;
          }
          _backoff = _backoff == Duration.zero
              ? const Duration(seconds: 30)
              : _backoff * 2;
          if (_backoff > const Duration(minutes: 10)) {
            _backoff = const Duration(minutes: 10);
          }
          Log.w("Index: page failed ($e), retrying in ${_backoff.inSeconds}s");
          await _sleep(_backoff);
          continue;
        }
        await _sleep(pagePause);
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Encrypted search index stopped");
    } finally {
      _loopRunning = false;
      _updateProgress();
    }
  }

  /// Waits [d], or less when something wakes the loop.
  Future<void> _sleep(Duration d) {
    final wake = _wake = Completer();
    return Future.any([Future.delayed(d), wake.future]);
  }

  /// Once per run, also scans what arrived while the app was closed.
  Future<void> _prepareRoom(SearchIndexBackend backend, String roomId) async {
    if (_topScanned.contains(roomId)) return;
    _topScanned.add(roomId);
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
    // isn't one under sliding sync.
    final from = segment.fromToken;
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
      final room = _mx.getRoomById(roomId);
      if (room == null) continue;
      final fixed = <Map<String, dynamic>>[];
      for (final json in await backend.undecrypted(roomId)) {
        final event = await encryption
            .decryptRoomEvent(matrix.Event.fromJson(json, room));
        if (event.type != matrix.EventTypes.Encrypted) {
          fixed.add(event.toJson());
        }
      }
      if (fixed.isEmpty) continue;
      if (await backend.addLive(roomId, fixed) > 0) {
        _roomUpdated.add(roomId);
      }
    }
  }

  // ---- live messages -------------------------------------------------------

  void _onTimelineEvent(matrix.Event event) {
    if (encryptedIndexMode == EncryptedIndexMode.off) return;
    if (!event.room.encrypted) return;
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
        if (room == null || !room.encrypted) continue;
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
