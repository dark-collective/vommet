// Vommet (schema v16): how long new messages take to arrive after the app
// comes back to the foreground. A long-poll /sync request left open while
// the device slept may sit on a dead connection until the SDK gives up on it
// (the server's 30 s timeout plus 10 s); this records whether a request was
// already in flight at resume, how old it was, and how long each account
// took to finish its first sync afterwards. Only resumes after at least
// [_minAwayS] in the background are recorded, and only while telemetry is on.

import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/telemetry_errors.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' as matrix;

class _Account {
  final Stopwatch inFlight = Stopwatch();
  int? syncedMs;
}

class ResumeTelemetry {
  static const _minAwayS = 30;

  /// Give up waiting for every account after this long and record what we
  /// have; an account that never synced is left out of `last_sync_ms`.
  static const _giveUpMs = 120000;

  static final List<_Account> _accounts = [];
  static final Stopwatch _away = Stopwatch();
  static final Stopwatch _sinceResume = Stopwatch();
  static AppLifecycleListener? _lifecycle;
  static bool _waiting = false;
  static int _staleMs = 0;
  static int _inFlight = 0;
  static int _errors = 0;
  static int _timeouts = 0;
  static int _awayS = 0;

  static void start() {
    if (_lifecycle != null) return;
    _lifecycle = AppLifecycleListener(
      onHide: _hidden,
      onPause: _hidden,
      onShow: _resumed,
      onResume: _resumed,
    );
  }

  static void stop() {
    _lifecycle?.dispose();
    _lifecycle = null;
    _waiting = false;
    _away
      ..stop()
      ..reset();
  }

  /// Follows one account's sync status (called once per account).
  static void attach(matrix.Client client) {
    final account = _Account();
    _accounts.add(account);
    client.onSyncStatus.stream.listen((event) {
      switch (event.status) {
        case matrix.SyncStatus.waitingForResponse:
          account.inFlight
            ..reset()
            ..start();
        case matrix.SyncStatus.processing:
          account.inFlight.stop();
        case matrix.SyncStatus.finished:
          account.inFlight.stop();
          if (_waiting && account.syncedMs == null) {
            account.syncedMs = _sinceResume.elapsedMilliseconds;
            _maybeRecord();
          }
        case matrix.SyncStatus.error:
          account.inFlight.stop();
          if (_waiting) {
            _errors++;
            if (TelemetryErrors.kind(event.error?.exception) == "timeout") {
              _timeouts++;
            }
          }
        default:
          return;
      }
    });
  }

  static void _hidden() {
    if (_away.isRunning) return;
    _away
      ..reset()
      ..start();
  }

  static void _resumed() {
    if (!_away.isRunning) return;
    _away.stop();
    _awayS = _away.elapsed.inSeconds;
    if (!Telemetry.enabled || _awayS < _minAwayS || _accounts.isEmpty) return;
    _staleMs = 0;
    _inFlight = 0;
    for (final account in _accounts) {
      account.syncedMs = null;
      if (account.inFlight.isRunning) {
        _inFlight++;
        final ms = account.inFlight.elapsedMilliseconds;
        if (ms > _staleMs) _staleMs = ms;
      }
    }
    _errors = _timeouts = 0;
    _sinceResume
      ..reset()
      ..start();
    _waiting = true;
    Future.delayed(const Duration(milliseconds: _giveUpMs), () {
      if (_waiting) _record();
    });
  }

  static void _maybeRecord() {
    if (_accounts.every((a) => a.syncedMs != null)) _record();
  }

  static void _record() {
    _waiting = false;
    final synced = [
      for (final a in _accounts)
        if (a.syncedMs != null) a.syncedMs!,
    ];
    synced.sort();
    Telemetry.record("resume", {
      "away_s": _awayS.clamp(0, 2592000),
      "accounts": _accounts.length.clamp(0, 1000000),
      "in_flight": _inFlight.clamp(0, 1000000),
      "stale_ms": _staleMs.clamp(0, 86400000),
      if (synced.isNotEmpty) "first_sync_ms": synced.first.clamp(0, 86400000),
      if (synced.length == _accounts.length)
        "last_sync_ms": synced.last.clamp(0, 86400000),
      "errors": _errors.clamp(0, 1000000),
      "timeouts": _timeouts.clamp(0, 1000000),
    });
  }
}
