// Vommet: bounded Followed threads preview (Vommet issue 1144).
import 'dart:async';

import 'package:commet/debug/log.dart';

typedef FollowedThreadPreviewResult<T> = ({
  List<T> rows,
  int failures,
  int completed
});

/// Keep transport slots occupied until the real request settles, even when
/// its results are no longer needed. Shared across cards and account switches.
class FollowedThreadPreview {
  static const roomLimit = 6;
  static const extraLimit = 6;
  static final Set<Future<void>> _inFlight = {};

  static Future<FollowedThreadPreviewResult<T>> load<R, T>({
    required Iterable<R> rooms,
    required Future<List<T>> Function(R) page,
    required Iterable<Future<T?> Function()> Function(List<T>) extra,
    Duration deadline = const Duration(seconds: 8),
    Future<void>? canceled,
  }) async {
    final rows = <T>[];
    final finished = Completer<void>();
    var stopped = false;
    var failures = 0;
    var completed = 0;
    final timer = Timer(deadline, () {
      if (stopped) return;
      failures++;
      stopped = true;
      finished.complete();
    });
    if (canceled != null) {
      unawaited(canceled.then((_) {
        if (stopped) return;
        stopped = true;
        finished.complete();
      }));
    }

    Future<void> runBatch(Iterable<Future<List<T>> Function()> tasks) async {
      final pending = tasks.iterator;
      Future<void> worker() async {
        while (!stopped) {
          if (_inFlight.length >= 2) {
            await Future.any([..._inFlight, finished.future]);
            continue;
          }
          if (!pending.moveNext()) return;
          final task = pending.current;
          late Future<void> request;
          request = Future.sync(task).then((result) {
            if (!stopped) {
              completed++;
              rows.addAll(result);
            }
          }, onError: (Object error) {
            if (!stopped) {
              failures++;
              Log.w(
                  "Home thread preview request failed (${error.runtimeType})");
            }
          }).whenComplete(() => _inFlight.remove(request));
          _inFlight.add(request);
          await Future.any([request, finished.future]);
        }
      }

      await Future.wait([worker(), worker()]);
    }

    Future<void> run() async {
      try {
        await runBatch(rooms.take(roomLimit).map((room) => () => page(room)));
        if (stopped) return;
        await runBatch(extra(rows).take(extraLimit).map((fetch) => () async {
              final row = await fetch();
              return [if (row != null) row];
            }));
      } catch (_) {
        if (!stopped) failures++;
      } finally {
        if (!stopped) {
          stopped = true;
          finished.complete();
        }
      }
    }

    unawaited(run());
    await finished.future;
    timer.cancel();
    return (
      rows: List<T>.unmodifiable(rows),
      failures: failures,
      completed: completed
    );
  }
}
