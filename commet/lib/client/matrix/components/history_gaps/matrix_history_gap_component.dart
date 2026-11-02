import 'dart:async';

import 'package:commet/client/components/history_reload/history_reload_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart' show clientManager;
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet (#102): finds and repairs holes in a room's stored history.
///
/// A homeserver that joins a room on another server with "faster joins"
/// (Synapse) backfills the room's history in the background. A client that
/// pages back before that finishes can get an incomplete page whose `end`
/// token already points at the room's start. The SDK stores that page as
/// the complete history: the oldest stored event is `m.room.create`, so it
/// never asks again, and the invite and the messages sent before the join
/// stay missing for good.
///
/// When the timeline's history reaches the start of a room we joined
/// recently, or whose stored history lacks our own invite although our join
/// says we were invited, this asks the server again a few times (with
/// backoff, while it may still be backfilling) for the events from before
/// our join. If the server has some we don't, the stored timeline is thrown
/// away and loaded again ([reloadHistory], also in the room menu).
class MatrixHistoryGapComponent
    extends HistoryReloadComponent<MatrixClient, MatrixRoom> {
  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  MatrixHistoryGapComponent(this.client, this.room) {
    room.onTimelineLoaded.stream.listen((_) => _watchTimeline());
  }

  StreamSubscription<void>? _timelineSub;

  /// Watches the room's open timeline: whenever its history has reached the
  /// start of the room, check that it is complete.
  void _watchTimeline() {
    final timeline = room.timeline;
    if (timeline is! MatrixTimeline) return;
    void reachedStart() {
      if (!timeline.canLoadHistory) historyReachedStart();
    }

    _timelineSub?.cancel();
    _timelineSub = timeline.onLoadingStatusChanged.listen((_) {
      if (!timeline.isLoadingHistory) reachedStart();
    });
    reachedStart();
  }

  /// A join this recent may still be backfilling on our server.
  static const recentJoin = Duration(minutes: 10);

  /// While the join is this fresh, keep checking even after the server
  /// agreed with what we have.
  static const freshJoin = Duration(minutes: 2);

  static const checkDelays = [
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  static const _pageSize = 100;
  static const _maxPages = 5;
  static const _maxReloads = 2;

  /// Off in tests that need a gap to stay (to exercise [reloadHistory]).
  @visibleForTesting
  static bool autoCheck = true;

  bool _checking = false;
  bool _checked = false;
  bool _reloading = false;
  int _reloads = 0;

  @override
  bool get isReloading => _reloading;

  matrix.Room get _mxRoom => room.matrixRoom;
  matrix.Client get _mx => _mxRoom.client;

  /// Called by the timeline when its history reached the start of the room.
  /// Checks (once per session) whether that history is really complete.
  void historyReachedStart() {
    if (!autoCheck || _checking || _checked) return;
    _checking = true;
    unawaited(_check().catchError((Object e, StackTrace s) {
      Log.w("History gap check for ${_mxRoom.id} failed: $e");
    }).whenComplete(() {
      _checking = false;
      _checked = true;
    }));
  }

  matrix.MatrixEvent? _ownJoin() {
    final me = _mx.userID;
    if (me == null) return null;
    final state = _mxRoom.getState(matrix.EventTypes.RoomMember, me);
    if (state is! matrix.MatrixEvent) return null;
    if (state.content['membership'] != 'join') return null;
    return state;
  }

  static Map<String, Object?>? _prevContent(matrix.MatrixEvent event) {
    final prev = event.prevContent ?? event.unsigned?['prev_content'];
    return prev is Map<String, Object?> ? prev : null;
  }

  /// Our join says we were invited, the stored history reaches the room's
  /// start, and the invite isn't in it.
  Future<bool> _inviteMissing(matrix.MatrixEvent join) async {
    if (_prevContent(join)?['membership'] != 'invite') return false;
    final me = _mx.userID;
    final events = await _mx.database.getEventList(_mxRoom);
    final reachedStart =
        events.any((e) => e.type == matrix.EventTypes.RoomCreate);
    final hasInvite = events.any((e) =>
        e.type == matrix.EventTypes.RoomMember &&
        e.stateKey == me &&
        e.content['membership'] == 'invite');
    return reachedStart && !hasInvite;
  }

  /// How many events from before our join the server has that our stored
  /// timeline lacks, if that timeline claims to reach the room's start
  /// (otherwise paging back will still fetch them: 0); null if the room is
  /// too long to tell cheaply.
  Future<int?> _missingFromServer(matrix.MatrixEvent join) async {
    final events = await _mx.database.getEventList(_mxRoom);
    if (!events.any((e) => e.type == matrix.EventTypes.RoomCreate)) return 0;
    final stored = events.map((e) => e.eventId).toSet();
    var missing = 0;
    String? from;
    for (var page = 0; page < _maxPages; page++) {
      final resp = await _mx.getRoomEvents(_mxRoom.id, matrix.Direction.b,
          from: from, limit: _pageSize);
      for (final e in resp.chunk) {
        if (e.originServerTs.isAfter(join.originServerTs)) continue;
        if (!stored.contains(e.eventId)) missing++;
      }
      final end = resp.end;
      if (end == null ||
          resp.chunk.isEmpty ||
          resp.chunk.any((e) => e.type == matrix.EventTypes.RoomCreate)) {
        return missing;
      }
      from = end;
    }
    return null;
  }

  Future<void> _check() async {
    final join = _ownJoin();
    if (join == null) return;
    Duration age() => DateTime.now().difference(join.originServerTs);
    final recent = age() < recentJoin;
    final inviteMissing = await _inviteMissing(join);
    if (!recent && !inviteMissing) return;
    Log.i("History gap check for ${_mxRoom.id}: joined ${age().inSeconds} s "
        "ago, invite missing: $inviteMissing");

    for (final delay in checkDelays) {
      await Future.delayed(delay);
      // Stop if the account was closed (logout, app relaunch) meanwhile.
      if (clientManager?.clients.contains(client) != true ||
          !_mx.isLogged() ||
          _mxRoom.membership != matrix.Membership.join) {
        return;
      }
      final missing = await _missingFromServer(join);
      Log.i("History gap check for ${_mxRoom.id}: the server has "
          "${missing ?? "too many to count"} pre-join events we don't");
      if (missing == null) return;
      if (missing > 0) {
        if (_reloads >= _maxReloads) return;
        _reloads++;
        await reloadHistory();
        continue;
      }
      // Complete as far as the server knows; it may still be backfilling a
      // very fresh join, so look again, otherwise we're done.
      if (age() > freshJoin) return;
    }
  }

  @override
  Future<void> reloadHistory() async {
    if (_reloading) return;
    _reloading = true;
    try {
      // The position "now", from /messages itself: a sync token isn't
      // usable as `from` everywhere (sliding sync positions aren't, and
      // Synapse paged from a stale point with one in our tests), while a
      // request without `from` starts at the room's latest event on both
      // Synapse and Tuwunel.
      final head =
          await _mx.getRoomEvents(_mxRoom.id, matrix.Direction.b, limit: 1);
      await _mx.database.transaction(() async {
        // What the SDK does on a limited sync: forget the stored timeline
        // (the events themselves stay cached) and page again from here.
        await _mx.database.deleteTimelineForRoom(_mxRoom.id);
        _mxRoom.prev_batch = head.start;
        await _mx.database.setRoomPrevBatch(head.start, _mxRoom.id, _mx);
      });
      Log.i("Reloading the history of ${_mxRoom.id}");
      final timeline = room.timeline;
      if (timeline is MatrixTimeline) await timeline.reload();
    } finally {
      _reloading = false;
    }
  }
}
