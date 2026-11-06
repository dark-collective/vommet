import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership.dart';

/// One session's own membership. All mutations and leave share this queue.
/// The successful content is retained locally: sync may lag several writes.
class MatrixRtcMembershipWriter {
  MatrixRtcMembershipWriter(
      {required this.readInitial,
      required this.send,
      this.isCurrent,
      this.currentOriginServerTs});
  final Future<({Map<String, dynamic> content, int originServerTs})> Function()
      readInitial;
  final Future<void> Function(Map<String, dynamic>) send;

  /// Session-owned status is reconciled for every write, including refresh
  /// and focus changes, so a failed stop cannot be refreshed as active.
  void Function(Map<String, dynamic>)? beforeSend;

  /// A newer empty synced state blocks ordinary writes. Active sessions
  /// arrange heartbeat recovery; without a recovery owner this closes it.
  final bool Function(int initialOriginServerTs)? isCurrent;

  /// Schedules recovery without awaiting it inside this writer's queue.
  void Function()? onMembershipLost;
  final int Function()? currentOriginServerTs;
  bool _lost = false;
  int? _initialOriginServerTs;
  Map<String, dynamic>? _content;
  Future<void> _tail = Future.value();
  bool _closed = false;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  /// Completes with false when nothing was written because the membership
  /// is closed (left, or replaced by a newer synced state).
  Future<bool> update(void Function(Map<String, dynamic>) change,
          {bool recover = false}) =>
      _enqueue(() async {
        if (_closed) return false;
        var current = _content;
        if (current == null) {
          final initial = await readInitial();
          _initialOriginServerTs = initial.originServerTs;
          current = Map<String, dynamic>.from(initial.content);
          if (current.isEmpty) return false;
          current['created_ts'] ??=
              MatrixRtcMembership.createdTs(current, initial.originServerTs);
        }
        if (_closed) return false;
        // Retain the full join even if the first mutation sees a delayed leave.
        _content ??= current;
        if (!recover &&
            (_lost || isCurrent?.call(_initialOriginServerTs!) == false)) {
          if (onMembershipLost == null) {
            _closed = true;
          } else {
            // Keep a concurrent focus migration/refresh for the recovery
            // write, even though the ordinary write must wait for a new leave.
            final pending = Map<String, dynamic>.from(current);
            change(pending);
            _content = pending;
            _lost = true;
            onMembershipLost!();
          }
          return false;
        }
        final recoveredThrough = recover ? currentOriginServerTs?.call() : null;
        final next = Map<String, dynamic>.from(current);
        change(next);
        beforeSend?.call(next);
        await send(next);
        _content = next;
        if (recover) {
          _lost = false;
          if (recoveredThrough != null &&
              recoveredThrough > _initialOriginServerTs!) {
            _initialOriginServerTs = recoveredThrough;
          }
        }
        return true;
      });

  /// Closes synchronously, waits for an in-flight write, then clears.
  /// May be called again by the existing bounded leave retry mechanism.
  /// The empty state is not sent once [cancelled] returns true (a rejoin
  /// settled the leave while it waited behind an in-flight write), so it
  /// can't land after the new membership.
  Future<void> clear({bool Function()? cancelled}) {
    _closed = true;
    return _enqueue(() async {
      if (cancelled?.call() == true) return;
      await send({});
    });
  }
}
