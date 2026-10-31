import 'dart:async';

import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart';

/// Vommet: clearing our call membership when we leave a call.
///
/// Hanging up used to wait for this state event before the call ended on
/// screen, so a slow homeserver left people stuck in the call for over a
/// minute (and every extra click on hang up started another leave). The
/// clear now runs here: the session waits for it briefly, and if it hasn't
/// landed by then the call ends anyway and the clear keeps retrying in the
/// background until it lands.
///
/// Rejoining the same call while a clear is still pending would race it (the
/// empty state event could land after the new membership and wipe it), so a
/// join calls [settle] first: it stops the retries and waits for a request
/// that is already in flight.
class MatrixRtcLeave {
  /// Runs the [steps] of leaving a call (name -> step) side by side and waits
  /// for all of them. A failing step doesn't stop the others, and doesn't
  /// stop the call from ending: offline, cancelling the heartbeat or closing
  /// the LiveKit connection throws, and hang up used to rethrow that and
  /// leave the call open on screen with no way to end it.
  static Future<LeaveSteps> runSteps(
      Map<String, Future<void> Function()> steps) async {
    final result = LeaveSteps();
    await Future.wait(steps.entries.map((step) async {
      final clock = Stopwatch()..start();
      try {
        await step.value();
      } catch (e) {
        Log.w("Leaving the call: ${step.key} failed: $e");
        if (result.failure == null) {
          result.failure = e;
          result.failedStep = step.key;
        }
      } finally {
        result.ms[step.key] = clock.elapsedMilliseconds;
      }
    }));
    return result;
  }

  /// Settable so tests don't wait for real backoff.
  static List<Duration> retryDelays = const [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  /// Give up after this long; the membership then expires on its own.
  static Duration giveUpAfter = const Duration(minutes: 10);

  static final Map<String, _PendingLeave> _pending = {};

  static String _key(String roomId, String stateKey) => "$roomId|$stateKey";

  /// Clears the membership at [stateKey] in [roomId] with [send] (which puts
  /// the empty state event), retrying until it lands. Completes when the
  /// clear has landed or been given up, so callers that only want to wait a
  /// little should add their own timeout.
  static Future<void> clear(
      String roomId, String stateKey, Future<void> Function() send) {
    final key = _key(roomId, stateKey);
    final existing = _pending[key];
    if (existing != null && !existing.cancelled) return existing.done.future;

    final pending = _PendingLeave();
    _pending[key] = pending;
    _run(send, key, pending);
    return pending.done.future;
  }

  static Future<void> _run(
      Future<void> Function() send, String key, _PendingLeave pending) async {
    final clock = Stopwatch()..start();
    var attempt = 0;
    try {
      while (!pending.cancelled) {
        final request = send();
        pending.inFlight = request;
        try {
          await request;
          Log.i("Cleared call state after ${clock.elapsedMilliseconds} ms"
              "${attempt > 0 ? " ($attempt retries)" : ""}");
          return;
        } catch (e) {
          if (!_worthRetrying(e)) {
            Log.e("Clearing call state failed, not retrying: $e");
            return;
          }
          if (clock.elapsed >= giveUpAfter) {
            Log.e("Clearing call state still failing after "
                "${clock.elapsed.inMinutes} min, giving up: $e");
            return;
          }
          final delay = retryDelays[attempt.clamp(0, retryDelays.length - 1)];
          attempt++;
          Log.w("Clearing call state failed, retrying in "
              "${delay.inMilliseconds} ms: $e");
          await Future.delayed(delay);
        } finally {
          pending.inFlight = null;
        }
      }
    } finally {
      if (identical(_pending[key], pending)) _pending.remove(key);
      if (!pending.done.isCompleted) pending.done.complete();
    }
  }

  /// The server answered and refused: retrying the same request won't help,
  /// except when it asked us to slow down or failed on its side.
  static bool _worthRetrying(Object e) {
    if (e is! MatrixException) return true;
    if (e.error == MatrixError.M_LIMIT_EXCEEDED) return true;
    final status = e.response?.statusCode;
    return status != null && status >= 500;
  }

  /// Called before posting a new membership at [stateKey] in [roomId]: stops
  /// a pending clear from retrying, and waits (up to [timeout]) for a clear
  /// request that is already on its way so it can't land after the join.
  static Future<void> settle(String roomId, String stateKey,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final pending = _pending.remove(_key(roomId, stateKey));
    if (pending == null) return;
    pending.cancelled = true;
    final inFlight = pending.inFlight;
    if (inFlight == null) return;
    Log.i("Waiting for the previous call leave before joining");
    try {
      await inFlight.timeout(timeout);
    } catch (_) {
      // Failed or slow: either way it is no longer ours to wait for.
    }
  }
}

class LeaveSteps {
  final Map<String, int> ms = {};
  String failedStep = "none";
  Object? failure;
}

class _PendingLeave {
  bool cancelled = false;
  Future<void>? inFlight;
  final Completer<void> done = Completer<void>();
}
