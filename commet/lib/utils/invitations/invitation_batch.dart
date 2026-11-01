// Vommet issue 842: a journal of individual invitations, not an atomic batch.
import 'dart:async';
import 'package:commet/utils/background_tasks/background_task_manager.dart';

enum InviteOutcome {
  waiting,
  sending,
  sent,
  skipped,
  blocked,
  failed,
  unconfirmed,
  held,
  canceled,
}

enum InviteOperation { invite, history }

enum InviteCheck { send, joined, invited, blocked }

class BatchInviteItem {
  BatchInviteItem({
    required this.userId,
    required this.roomId,
    required this.roomName,
    this.parentRoomId,
    this.operation = InviteOperation.invite,
    this.shareHistory = true,
  });
  final String userId;
  final String roomId;
  final String roomName;
  final String? parentRoomId;
  final InviteOperation operation;
  final bool shareHistory;
  InviteOutcome outcome = InviteOutcome.waiting;
  String? reason;
  (String, String, InviteOperation) get key => (userId, roomId, operation);
}

class InvitationBatchTask implements BackgroundTaskWithIntegerProgress {
  InvitationBatchTask({
    required this.accountId,
    required this.name,
    required Iterable<BatchInviteItem> items,
    required this.check,
    required this.send,
    required this.reasonFor,
    required this.uncertain,
    this.retryAfter,
    Future<void> Function(Duration)? sleep,
  })  : items = List.unmodifiable(
          {for (final item in items) item.key: item}.values,
        ),
        _sleep = sleep ?? Future<void>.delayed;
  final String accountId;
  final String name;
  final List<BatchInviteItem> items;
  final Future<InviteCheck> Function(BatchInviteItem) check;
  final Future<void> Function(BatchInviteItem) send;
  final String Function(Object) reasonFor;
  final bool Function(Object) uncertain;
  final Duration? Function(Object)? retryAfter;
  final Future<void> Function(Duration) _sleep;
  static final Set<(String, String, String, InviteOperation)> _reserved = {};
  final _changes = StreamController<void>.broadcast();
  final _progress = StreamController<int>.broadcast();
  bool running = false;
  bool stopping = false;
  Completer<void>? _wake;
  bool _disposed = false;
  bool _started = false;
  final Set<(String, String, InviteOperation)> _owned = {};
  int count(InviteOutcome state) =>
      items.where((i) => i.outcome == state).length;
  bool get needsAttention => items.any(
        (i) => {
          InviteOutcome.failed,
          InviteOutcome.blocked,
          InviteOutcome.unconfirmed,
          InviteOutcome.held,
          InviteOutcome.canceled,
        }.contains(i.outcome),
      );
  bool get canRetry => items.any(
        (i) =>
            i.outcome == InviteOutcome.failed ||
            i.outcome == InviteOutcome.blocked,
      );
  bool get canResume => items.any(
        (i) =>
            i.outcome == InviteOutcome.canceled ||
            i.outcome == InviteOutcome.held,
      );
  void changed() {
    if (!_disposed) {
      _changes.add(null);
      _progress.add(current);
    }
  }

  @override
  Stream<void> get statusChanged => _changes.stream;
  @override
  Stream<int> get onProgress => _progress.stream;
  @override
  int get total => items.length;
  @override
  int get current => items
      .where(
        (i) =>
            i.outcome != InviteOutcome.waiting &&
            i.outcome != InviteOutcome.sending,
      )
      .length;
  @override
  BackgroundTaskStatus get status => running
      ? BackgroundTaskStatus.running
      : needsAttention
          ? BackgroundTaskStatus.failed
          : BackgroundTaskStatus.completed;
  // Names/IDs are displayed only by the redaction-aware invitation card/view.
  @override
  String get label {
    final sent = items
        .where(
          (i) =>
              i.operation == InviteOperation.invite &&
              i.outcome == InviteOutcome.sent,
        )
        .length;
    final shares = items
        .where(
          (i) =>
              i.operation == InviteOperation.history &&
              i.outcome == InviteOutcome.sent,
        )
        .length;
    return 'Invitations: $sent sent${shares == 0 ? '' : ' · $shares history shares recorded'}${running ? stopping ? ' · stopping' : ' · sending' : needsAttention ? ' · needs attention' : ''}';
  }

  @override
  bool shouldRemoveTask = false;
  @override
  bool get canCallAction => action != null;
  @override
  void Function()? action;
  void stop() {
    if (running) {
      stopping = true;
      if (_wake?.isCompleted == false) _wake!.complete();
      changed();
    }
  }

  void dismiss() {
    if (running) return;
    shouldRemoveTask = true;
    changed();
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (final item in items) {
      final key = (accountId, item.userId, item.roomId, item.operation);
      if (_reserved.add(key)) {
        _owned.add(item.key);
      } else {
        item.outcome = InviteOutcome.held;
        item.reason = 'Already in another invitation batch';
      }
    }
    await _run();
  }

  Future<void> retry() => _restart({
        InviteOutcome.failed,
        InviteOutcome.blocked,
        InviteOutcome.held,
      });
  Future<void> resume() =>
      _restart({InviteOutcome.canceled, InviteOutcome.held});

  /// Only after an explicit warning/confirmation in the view. Check again before sending.
  Future<void> retryUnconfirmed() =>
      _restart({InviteOutcome.unconfirmed, InviteOutcome.held});
  Future<void> _restart(Set<InviteOutcome> states) async {
    if (running || _disposed) return;
    for (final item in items.where((i) => states.contains(i.outcome))) {
      final reservation = (accountId, item.userId, item.roomId, item.operation);
      if (!_reserved.add(reservation)) continue;
      _owned.add(item.key);
      item.outcome = InviteOutcome.waiting;
      item.reason = null;
    }
    await _run();
  }

  Future<void> reconcile() async {
    if (running || _disposed) return;
    running = true;
    stopping = false;
    changed();
    try {
      for (final item in items.where(
        (i) => i.outcome == InviteOutcome.unconfirmed,
      )) {
        if (stopping) break;
        try {
          final result = await check(item);
          if (result == InviteCheck.joined || result == InviteCheck.invited) {
            // Another inviter or an independent join may have achieved this.
            // Membership proves no repeat is needed, not who sent an invite.
            item.outcome = InviteOutcome.skipped;
            item.reason = result == InviteCheck.joined
                ? 'Already joined; membership confirmed'
                : 'Invite pending; membership confirmed';
          }
        } catch (_) {
          /* Keep the uncertain result; never infer success. */
        }
      }
    } finally {
      running = false;
      changed();
    }
  }

  Future<void> _run() async {
    if (running || _disposed) return;
    running = true;
    stopping = false;
    changed();
    try {
      for (final item in items.where(
        (i) => i.outcome == InviteOutcome.waiting,
      )) {
        if (stopping) {
          item.outcome = InviteOutcome.canceled;
          item.reason = 'Not sent';
          continue;
        }
        final parent = items
            .where(
              (p) =>
                  p.userId == item.userId &&
                  p.roomId == item.parentRoomId &&
                  p.operation == InviteOperation.invite,
            )
            .firstOrNull;
        if (parent != null &&
            parent.outcome != InviteOutcome.sent &&
            parent.outcome != InviteOutcome.skipped) {
          item.outcome = InviteOutcome.held;
          item.reason = 'Waiting for the parent space invitation';
          changed();
          continue;
        }
        item.outcome = InviteOutcome.sending;
        changed();
        bool dispatched = false;
        try {
          final eligibility = await check(item);
          if (stopping) {
            item.outcome = InviteOutcome.canceled;
            item.reason = 'Not sent';
          } else if (eligibility == InviteCheck.blocked) {
            item.outcome = InviteOutcome.blocked;
            item.reason =
                'Not allowed. Check membership and invite permissions.';
          } else if (item.operation == InviteOperation.invite &&
              eligibility != InviteCheck.send) {
            item.outcome = InviteOutcome.skipped;
            item.reason = eligibility == InviteCheck.joined
                ? 'Already joined'
                : 'Invite pending';
          } else {
            var attempts = 0;
            while (true) {
              dispatched = true;
              try {
                item.reason = null;
                await send(item);
                item.outcome = InviteOutcome.sent;
                break;
              } catch (error) {
                final delay = retryAfter?.call(error);
                if (delay == null || attempts++ >= 3 || stopping) rethrow;
                item.reason = 'Server busy; waiting to retry';
                changed();
                final wake = Completer<void>();
                _wake = wake;
                await Future.any<void>([
                  _sleep(delay > const Duration(seconds: 1)
                      ? delay
                      : const Duration(seconds: 1)),
                  wake.future,
                ]);
                _wake = null;
                if (stopping) {
                  item.outcome = InviteOutcome.canceled;
                  item.reason = 'Not sent';
                  break;
                }
                dispatched = false;
                final fresh = await check(item);
                if (item.operation == InviteOperation.invite &&
                    (fresh == InviteCheck.joined ||
                        fresh == InviteCheck.invited)) {
                  item.outcome = InviteOutcome.skipped;
                  item.reason = 'Already joined or invited';
                  break;
                }
                if (fresh == InviteCheck.blocked) {
                  item.outcome = InviteOutcome.blocked;
                  item.reason = 'No longer allowed';
                  break;
                }
              }
            }
          }
        } catch (error) {
          item.outcome = dispatched &&
                  item.operation == InviteOperation.invite &&
                  uncertain(error)
              ? InviteOutcome.unconfirmed
              : InviteOutcome.failed;
          item.reason = dispatched
              ? reasonFor(error)
              : 'Could not check membership. Nothing was sent for this request. ${reasonFor(error)}';
        }
        changed();
      }
    } finally {
      for (final key in _owned) {
        _reserved.remove((accountId, key.$1, key.$2, key.$3));
      }
      _owned.clear();
      running = false;
      changed();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _changes.close();
    _progress.close();
  }
}
