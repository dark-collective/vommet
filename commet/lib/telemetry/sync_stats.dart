// Vommet (schema v11): how long the app spends applying each sync response,
// across all accounts. Measured from the SDK's "processing" status to
// "finished": the time between a response arriving and the app being done
// with it (room and event handling plus the database write). Wall time, so
// it includes database waits, not only work on the UI isolate; the loop_lag
// event shows how much of it blocked the UI.
//
// Schema v12 splits that time at the SDK's "cleaningUp" status: "save" is
// the response being applied and written to the database (including any
// wait for startup loads), "followup" what the SDK does before the next
// sync can start: refreshing other users' device keys (a /keys/query that
// can wait on slow remote servers) and sending queued to-device messages.
//
// Schema v17 adds gaps: the time between one finished sync and the next
// while the app is in the foreground. A healthy long-poll finishes within
// the server's 30 s timeout plus the SDK's 10 s margin, so a gap over 90 s
// with no error is a sync that silently stalled (dead connection, server
// lock, a request nobody restarted). Time in the background is left out.
//
// Schema v19 adds sliding sync restarts. Some launches apply a ~6,000-event
// first sync (every room sent again from scratch) and others a handful of
// events. Per window: how many times the server rejected our position
// (M_UNKNOWN_POS), how many rooms rounds sent from scratch, and in how many
// rounds; once per launch, "ss_first_round": whether a stored position
// existed when the first request went out and what that round re-sent.
//
// Schema v21: "first_sync", once per launch (first account to finish): when
// its request went out, when the response arrived and when it was applied,
// counted from launch, and how long the UI isolate was blocked until then.
//
// Schema v32: first_sync also says what that response contained (body bytes
// and counts of rooms and of each kind of event, never ids, types or
// content) and where its apply time went: time to the SDK's "cleaningUp"
// step and the summed time of the database calls made meanwhile. The same
// build applied it in 3 s, 5 s and 30 s on one slow device; these tell a
// bigger response from slower database work.

import 'dart:convert';

import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/telemetry/frame_stats.dart';
import 'package:commet/telemetry/loop_lag.dart';
import 'package:commet/telemetry/resume_telemetry.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/telemetry_http.dart';
import 'package:commet/telemetry/verification_telemetry.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' as matrix;

class SyncStats {
  static final MsHistogram _apply = MsHistogram();
  static final MsHistogram _save = MsHistogram();
  static final MsHistogram _followup = MsHistogram();
  static int _totalMs = 0;
  static int _followupTotalMs = 0;
  static int _rooms = 0;
  static int _events = 0;
  static int _state = 0;
  static int _worstMs = -1;
  static int _worstEvents = 0;
  static int _ssResets = 0;
  static int _ssInitialRooms = 0;
  static int _ssInitialRounds = 0;
  static bool _firstSyncRecorded = false;
  static int _gapWorstMs = 0;
  static int _gaps90 = 0;

  /// A gap beyond this is a suspended app or a debugger, not a stall.
  static const _ignoreGapAboveMs = 3600000;
  static const _gapStallMs = 90000;

  /// Per-account time since the last finished sync, running only in the
  /// foreground. Reset (not read) when the app comes back, so the time
  /// spent away never counts as a gap.
  static final List<Stopwatch> _sinceFinished = [];
  static AppLifecycleListener? _lifecycle;
  static bool _foreground = true;

  static void start() {
    if (_lifecycle != null) return;
    _lifecycle = AppLifecycleListener(
      onResume: _resume,
      onShow: _resume,
      onHide: _pause,
      onPause: _pause,
    );
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  static void stop() {
    _lifecycle?.dispose();
    _lifecycle = null;
    reset();
  }

  static void _resume() {
    _foreground = true;
    for (final w in _sinceFinished) {
      w
        ..reset()
        ..stop();
    }
  }

  static void _pause() {
    _foreground = false;
    for (final w in _sinceFinished) {
      w.stop();
    }
  }

  /// Records the gap one account's finished sync closes, then restarts its
  /// clock. Public for tests.
  static void noteFinished(Stopwatch sinceFinished) {
    if (sinceFinished.isRunning) {
      final gap = sinceFinished.elapsedMilliseconds;
      if (gap <= _ignoreGapAboveMs) {
        if (gap > _gapWorstMs) _gapWorstMs = gap;
        if (gap > _gapStallMs) _gaps90++;
      }
    }
    sinceFinished.reset();
    if (_foreground) sinceFinished.start();
  }

  /// The server name whose accounts count as "own server" in telemetry.
  /// Fixed at build time on purpose, so `own_server: true` always means the
  /// same thing; the name itself is never sent.
  static const ownServerName = "nether.im";

  /// Whether [userId] is an account on [ownServerName]; null when unknown.
  static bool? onOwnServer(String? userId) {
    if (userId == null) return null;
    final colon = userId.indexOf(":");
    if (colon < 0) return null;
    return userId.substring(colon + 1).toLowerCase() == ownServerName;
  }

  /// Counts what a sync response contained: joined, invited and left rooms,
  /// their timeline events and their state events.
  static (int rooms, int events, int state) measure(matrix.SyncUpdate update) {
    final rooms = update.rooms;
    if (rooms == null) return (0, 0, 0);
    var events = 0;
    var state = 0;
    for (final room
        in rooms.join?.values ?? const <matrix.JoinedRoomUpdate>[]) {
      events += room.timeline?.events?.length ?? 0;
      state += room.state?.length ?? 0;
    }
    for (final room in rooms.leave?.values ?? const <matrix.LeftRoomUpdate>[]) {
      events += room.timeline?.events?.length ?? 0;
      state += room.state?.length ?? 0;
    }
    for (final room
        in rooms.invite?.values ?? const <matrix.InvitedRoomUpdate>[]) {
      state += room.inviteState?.length ?? 0;
    }
    final count = (rooms.join?.length ?? 0) +
        (rooms.leave?.length ?? 0) +
        (rooms.invite?.length ?? 0);
    return (count, events, state);
  }

  /// Vommet (v32): the first_sync size fields for one sync response. Counts
  /// only: what kind of thing and how many, never ids, types or content.
  static Map<String, int> firstSyncCounts(matrix.SyncUpdate update) {
    var timelineRooms = 0;
    var timeline = 0;
    var state = 0;
    var ephemeral = 0;
    var roomAccountData = 0;
    final rooms = update.rooms;
    for (final room
        in rooms?.join?.values ?? const <matrix.JoinedRoomUpdate>[]) {
      final n = room.timeline?.events?.length ?? 0;
      if (n > 0) timelineRooms++;
      timeline += n;
      state += room.state?.length ?? 0;
      ephemeral += room.ephemeral?.length ?? 0;
      roomAccountData += room.accountData?.length ?? 0;
    }
    for (final room
        in rooms?.leave?.values ?? const <matrix.LeftRoomUpdate>[]) {
      final n = room.timeline?.events?.length ?? 0;
      if (n > 0) timelineRooms++;
      timeline += n;
      state += room.state?.length ?? 0;
      roomAccountData += room.accountData?.length ?? 0;
    }
    for (final room
        in rooms?.invite?.values ?? const <matrix.InvitedRoomUpdate>[]) {
      state += room.inviteState?.length ?? 0;
    }
    int c(int v) => v.clamp(0, 1000000);
    return {
      "rooms": c((rooms?.join?.length ?? 0) +
          (rooms?.leave?.length ?? 0) +
          (rooms?.invite?.length ?? 0)),
      "timeline_rooms": c(timelineRooms),
      "timeline_events": c(timeline),
      "state_events": c(state),
      "ephemeral_events": c(ephemeral),
      "room_account_data": c(roomAccountData),
      "account_data": c(update.accountData?.length ?? 0),
      "presence": c(update.presence?.length ?? 0),
      "to_device": c(update.toDevice?.length ?? 0),
      "device_lists_changed": c(update.deviceLists?.changed?.length ?? 0),
      "device_lists_left": c(update.deviceLists?.left?.length ?? 0),
    };
  }

  /// Vommet (v32): database calls and their summed milliseconds so far,
  /// from the timers the database wrapper always keeps (both the startup
  /// and the post-load set).
  static (int, int) dbTotals() {
    var calls = 0;
    var ms = 0;
    for (final d in [
      Diagnostics.initialLoadDatabaseDiagnostics,
      Diagnostics.postLoadDatabaseDiagnostics,
    ]) {
      for (final m in d.measurements.values) {
        calls += m.numCalls;
        ms += m.totalDuration.inMilliseconds;
      }
    }
    return (calls, ms);
  }

  /// Follows one account's syncs: their status for the timings, and the
  /// updates themselves for what they contained.
  static void attach(matrix.Client client) {
    ResumeTelemetry.attach(client);
    // Vommet (v34): verification step timings, against these sync rounds.
    VerificationTelemetry.attach(client);
    final status = listener();
    final sinceFinished = Stopwatch();
    _sinceFinished.add(sinceFinished);
    var pending = (0, 0, 0);
    // Vommet (v19): sliding sync restarts, see the comment at the top.
    // `recentResets` counts the last minute, so the difference since the
    // previous round is this round's (rounds come well within a minute).
    bool? hadPosition;
    var positionChecked = false;
    var lastResets = 0;
    var firstRound = true;
    void slidingSyncRound() {
      final round = slidingSyncRoundCounts(client);
      if (round == null) return;
      final (initial, resetsNow) = round;
      final resets = resetsNow > lastResets ? resetsNow - lastResets : 0;
      lastResets = resetsNow;
      _ssResets += resets;
      _ssInitialRooms += initial;
      if (initial > 0) _ssInitialRounds += 1;
      if (!firstRound) return;
      firstRound = false;
      Telemetry.record("ss_first_round", {
        "had_position": hadPosition ?? false,
        "initial_rooms": initial.clamp(0, 1000000),
        "rooms": client.rooms.length.clamp(0, 1000000),
        "resets": resets.clamp(0, 1000000),
      });
    }

    Map<String, int>? firstCounts;
    int? firstBytes;
    int? firstSaveMs;
    (int, int)? dbAtResponse;
    client.onSync.stream.listen((update) {
      if (!Telemetry.enabled) return;
      // Fires while the sync is being applied, before its "finished".
      pending = measure(update);
      if (!_firstSyncRecorded) firstCounts = firstSyncCounts(update);
    });
    int? requestAtMs;
    int? responseAtMs;
    client.onSyncStatus.stream.listen((event) {
      if (!_firstSyncRecorded) {
        switch (event.status) {
          case matrix.SyncStatus.waitingForResponse:
            requestAtMs ??= Telemetry.sinceStart;
          case matrix.SyncStatus.processing:
            if (responseAtMs == null) {
              responseAtMs = Telemetry.sinceStart;
              firstBytes = HttpStats.lastSyncBytes;
              dbAtResponse = dbTotals();
            }
          case matrix.SyncStatus.cleaningUp:
            if (responseAtMs != null) {
              firstSaveMs ??= Telemetry.sinceStart - responseAtMs!;
            }
          case matrix.SyncStatus.finished:
            _firstSyncRecorded = true;
            final lag = LoopLag.takeStartup();
            final db0 = dbAtResponse;
            final db = db0 == null ? null : dbTotals();
            Telemetry.record("first_sync", {
              if (requestAtMs != null) "request_at_ms": requestAtMs!,
              if (responseAtMs != null) "response_at_ms": responseAtMs!,
              "done_at_ms": Telemetry.sinceStart,
              "blocked_ms": lag.blockedMs.clamp(0, 86400000),
              "blocked_worst_ms": lag.worstMs.clamp(0, 86400000),
              "stalls_100ms": lag.stalls100.clamp(0, 1000000),
              if (firstBytes != null)
                "bytes": firstBytes!.clamp(0, 1099511627776),
              ...?firstCounts,
              if (firstSaveMs != null)
                "save_ms": firstSaveMs!.clamp(0, 86400000),
              if (db0 != null && db != null) ...{
                "db_ms": (db.$2 - db0.$2).clamp(0, 86400000),
                "db_calls": (db.$1 - db0.$1).clamp(0, 1000000),
              },
            });
            firstCounts = null;
          default:
            break;
        }
      }
      if (event.status == matrix.SyncStatus.waitingForResponse &&
          !positionChecked) {
        // The first request of this run has just gone out with this token.
        positionChecked = true;
        hadPosition = slidingSyncTokenHasPosition(client.prevBatch);
      }
      if (event.status == matrix.SyncStatus.finished && Telemetry.enabled) {
        slidingSyncRound();
      }
      if (event.status == matrix.SyncStatus.finished) {
        final (rooms, events, state) = pending;
        pending = (0, 0, 0);
        _rooms += rooms;
        _events += events;
        _state += state;
        _lastEvents = events + state;
        noteFinished(sinceFinished);
      }
      status(event);
    });
  }

  /// The event count of the sync whose "finished" is being handled.
  static int _lastEvents = 0;

  /// A listener for one account's sync status stream.
  static void Function(matrix.SyncStatusUpdate) listener() {
    final clock = Stopwatch();
    int? saveMs;
    return (event) {
      if (!Telemetry.enabled) return;
      switch (event.status) {
        case matrix.SyncStatus.processing:
          saveMs = null;
          clock
            ..reset()
            ..start();
        case matrix.SyncStatus.cleaningUp:
          if (!clock.isRunning || saveMs != null) return;
          saveMs = clock.elapsedMilliseconds;
        case matrix.SyncStatus.finished:
          if (!clock.isRunning) return;
          clock.stop();
          final ms = clock.elapsedMilliseconds;
          _apply.add(ms);
          _totalMs += ms;
          if (ms > _worstMs) {
            _worstMs = ms;
            _worstEvents = _lastEvents;
          }
          final save = saveMs;
          if (save != null) {
            _save.add(save);
            _followup.add(ms - save);
            _followupTotalMs += ms - save;
          }
        case matrix.SyncStatus.error:
          clock.stop();
        default:
          return;
      }
    };
  }

  /// Vommet (v19): whether a stored sync token is a sliding sync one with
  /// a position. Null for a /sync v2 token or none. Parsed here, not with the
  /// SDK fork's SlidingSyncToken, so this builds against any SDK: the token
  /// is "ss1:" followed by JSON with the position under "pos".
  static bool? slidingSyncTokenHasPosition(String? token) {
    const prefix = "ss1:";
    if (token == null || !token.startsWith(prefix)) return null;
    try {
      final json = jsonDecode(token.substring(prefix.length));
      return json is Map && json["pos"] is String;
    } catch (_) {
      return false;
    }
  }

  /// Vommet (v19): the rooms the last sliding sync round sent from scratch
  /// and the position resets of the last minute, from the SDK fork's
  /// sliding sync controller; null when not syncing that way or with an SDK
  /// without one (reached dynamically so this builds against either).
  static (int, int)? slidingSyncRoundCounts(matrix.Client client) {
    try {
      final dynamic sdk = client;
      if (sdk.slidingSync != true) return null;
      final dynamic controller = sdk.slidingSyncController;
      final initial = (controller.initialRoomIds as Set).length;
      final resets = controller.recentResets as int;
      return (initial, resets);
    } catch (_) {
      return null;
    }
  }

  static void report() {
    if (_apply.count == 0) return;
    Telemetry.record("sync_stats", {
      "syncs": _apply.count.clamp(0, 1000000),
      "apply_p95_ms": _apply.p95(),
      "apply_worst_ms": _apply.worstMs.clamp(0, 86400000),
      "apply_total_ms": _totalMs.clamp(0, 86400000),
      "rooms_total": _rooms.clamp(0, 1000000),
      "events_total": _events.clamp(0, 1000000),
      "state_total": _state.clamp(0, 1000000),
      "worst_events": _worstEvents.clamp(0, 1000000),
      "gap_worst_ms": _gapWorstMs.clamp(0, 86400000),
      "gaps_90s": _gaps90.clamp(0, 1000000),
      "ss_resets": _ssResets.clamp(0, 1000000),
      "ss_initial_rooms": _ssInitialRooms.clamp(0, 1000000),
      "ss_initial_rounds": _ssInitialRounds.clamp(0, 1000000),
      if (_save.count > 0) ...{
        "save_p95_ms": _save.p95(),
        "save_worst_ms": _save.worstMs.clamp(0, 86400000),
        "followup_p95_ms": _followup.p95(),
        "followup_worst_ms": _followup.worstMs.clamp(0, 86400000),
        "followup_total_ms": _followupTotalMs.clamp(0, 86400000),
      },
    });
    reset();
  }

  static void reset() {
    _apply.reset();
    _save.reset();
    _followup.reset();
    _totalMs = _followupTotalMs = 0;
    _rooms = _events = _state = _worstEvents = _lastEvents = 0;
    _worstMs = -1;
    _gapWorstMs = _gaps90 = 0;
    _ssResets = _ssInitialRooms = _ssInitialRounds = 0;
  }
}
