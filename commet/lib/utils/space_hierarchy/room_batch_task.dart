// Vommet: the background card for joining (or leaving) a batch of rooms:
// "Joining <space>: x of y", a progress bar, Cancel, and a line naming the
// rooms that failed.

import 'dart:async';

import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:commet/utils/space_hierarchy/room_action_queue.dart';

class RoomBatchItem {
  const RoomBatchItem(this.roomId, this.name,
      {this.via = const [], this.joinRule});
  final String roomId;
  final String name;
  final List<String> via;
  final String? joinRule;
}

class RoomBatchTask
    implements BackgroundTaskWithIntegerProgress, BackgroundTaskWithDetails {
  RoomBatchTask({
    required this.verb,
    required this.doneVerb,
    required this.failVerb,
    required this.spaceName,
    required List<RoomBatchItem> items,
    required Future<void> Function(RoomBatchItem item) run,
    required this.reasonFor,
    Duration? Function(Object error)? retryAfter,
    bool lastAlone = false,
  }) {
    queue = RoomActionQueue<RoomBatchItem>(
      items: items,
      run: run,
      retryAfter: retryAfter,
      lastAlone: lastAlone,
      onChanged: () {
        if (!_progress.isClosed) _progress.add(queue.done);
      },
    );
  }

  /// "Joining", "Joined", "joined" (for "couldn't be joined").
  final String verb;
  final String doneVerb;
  final String failVerb;
  final String spaceName;
  final String Function(RoomBatchItem item, Object error) reasonFor;

  late final RoomActionQueue<RoomBatchItem> queue;

  final StreamController<void> _status = StreamController.broadcast();
  final StreamController<int> _progress = StreamController.broadcast();

  Future<void> start() async {
    await queue.start();
    status = queue.failures.isNotEmpty && queue.failures.length == total
        ? BackgroundTaskStatus.failed
        : BackgroundTaskStatus.completed;
    if (!_status.isClosed) _status.add(null);
    // Leave a failure line up long enough to read.
    Timer(Duration(seconds: queue.failures.isEmpty ? 5 : 20), () {
      shouldRemoveTask = true;
      if (!_status.isClosed) _status.add(null);
    });
  }

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  @override
  bool shouldRemoveTask = false;

  @override
  Stream<void> get statusChanged => _status.stream;

  @override
  Stream<int> get onProgress => _progress.stream;

  @override
  int get current => queue.done;

  @override
  int get total => queue.total;

  @override
  String get label {
    if (status == BackgroundTaskStatus.running) {
      return queue.cancelled
          ? "$verb $spaceName: stopping"
          : "$verb $spaceName: $current of $total";
    }
    return "$doneVerb $spaceName: ${current - queue.failures.length} of $total";
  }

  @override
  String? get detail {
    if (queue.failures.isEmpty) return null;
    final byReason = <String, List<String>>{};
    for (final f in queue.failures) {
      byReason
          .putIfAbsent(reasonFor(f.item, f.error), () => [])
          .add(f.item.name);
    }
    return byReason.entries.map((e) {
      final names = e.value.length > 3
          ? "${e.value.take(3).join(", ")} and ${e.value.length - 3} more"
          : e.value.join(", ");
      return "${e.value.length} couldn't be $failVerb (${e.key}): $names";
    }).join("\n");
  }

  @override
  bool get canCancel =>
      status == BackgroundTaskStatus.running && !queue.cancelled;

  @override
  void cancel() => queue.cancel();

  @override
  bool get canCallAction => false;

  @override
  void Function()? action;

  @override
  void dispose() {
    _status.close();
    _progress.close();
  }
}
