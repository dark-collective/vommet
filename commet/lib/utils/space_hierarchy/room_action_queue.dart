// Vommet: runs joins (or leaves) for many rooms a few at a time, backing
// off when the server says to slow down. Pure Dart so it can be unit tested.

import 'dart:async';

class RoomActionFailure<T> {
  const RoomActionFailure(this.item, this.error);
  final T item;
  final Object error;
}

class RoomActionQueue<T> {
  RoomActionQueue({
    required List<T> items,
    required this.run,
    this.retryAfter,
    this.concurrency = 2,
    this.maxRetries = 5,
    this.lastAlone = false,
    Future<void> Function(Duration)? sleep,
    this.onChanged,
  })  : items = List.unmodifiable(items),
        _sleep = sleep ?? ((d) => Future.delayed(d));

  final List<T> items;
  final Future<void> Function(T item) run;

  /// For a "slow down" error, how long to wait (zero = use backoff); null
  /// for any other error.
  final Duration? Function(Object error)? retryAfter;
  final int concurrency;
  final int maxRetries;

  /// Run the last item only after all the others have finished (leaving a
  /// space after its rooms).
  final bool lastAlone;
  final void Function()? onChanged;
  final Future<void> Function(Duration) _sleep;

  int done = 0;
  final List<RoomActionFailure<T>> failures = [];
  bool cancelled = false;
  int _next = 0;
  DateTime? _pausedUntil;

  int get total => items.length;

  void cancel() {
    cancelled = true;
    onChanged?.call();
  }

  Future<void> start() async {
    final body =
        lastAlone && items.length > 1 ? items.length - 1 : items.length;
    await Future.wait([
      for (var i = 0; i < concurrency; i++) _worker(body),
    ]);
    if (body < items.length && !cancelled) {
      _next = body;
      await _worker(items.length);
    }
  }

  Future<void> _worker(int end) async {
    while (!cancelled && _next < end) {
      final item = items[_next++];
      await _runOne(item);
      done++;
      onChanged?.call();
    }
  }

  Future<void> _runOne(T item) async {
    var attempt = 0;
    while (true) {
      final until = _pausedUntil;
      if (until != null) {
        final wait = until.difference(DateTime.now());
        if (wait > Duration.zero) await _sleep(wait);
      }
      if (cancelled) return;
      try {
        await run(item);
        return;
      } catch (e) {
        final after = retryAfter?.call(e);
        if (after == null || attempt >= maxRetries) {
          failures.add(RoomActionFailure(item, e));
          return;
        }
        final backoff = Duration(seconds: 1 << attempt);
        final wait = after > backoff ? after : backoff;
        attempt++;
        // Both workers wait: the limit is per account.
        _pausedUntil = DateTime.now().add(wait);
        await _sleep(wait);
      }
    }
  }
}
