import 'dart:async';
import 'dart:typed_data';

import 'package:commet/debug/log.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';

enum PackImportJobState { waiting, running, done, failed, cancelled }

/// Reports a running pack's progress: [fraction] of the work (0–1) and how
/// many of its images are finished.
typedef PackImportProgress = void Function(double fraction, int imagesDone);

/// Vommet: one pack in a [PackImportQueueTask].
class PackImportJob {
  PackImportJob({
    required this.name,
    required this.imageCount,
    required this.run,
    this.thumbnail,
    this.error,
  }) : state = error == null
            ? PackImportJobState.waiting
            : PackImportJobState.failed;

  final String name;
  final int imageCount;
  final Uint8List? thumbnail;

  /// Downloads, uploads and writes the pack; throws when it fails.
  final Future<void> Function(PackImportProgress progress) run;

  PackImportJobState state;

  /// Why the pack couldn't be imported (set when [state] is failed).
  String? error;

  double fraction = 0;
  int imagesDone = 0;

  bool get finished =>
      state == PackImportJobState.done ||
      state == PackImportJobState.failed ||
      state == PackImportJobState.cancelled;
}

/// Vommet: imports several packs one after the other in the background.
/// Each pack is written as soon as it's done, so it's usable before the rest
/// finish. A failing pack doesn't stop the others; [cancel] stops the packs
/// that haven't started (the running one finishes).
class PackImportQueueTask implements BackgroundTask {
  PackImportQueueTask(this.jobs,
      {this.removeAfter = const Duration(seconds: 8)});

  final List<PackImportJob> jobs;
  final Duration removeAfter;

  final StreamController<void> _changed = StreamController.broadcast();

  /// Fires on every progress or state change.
  Stream<void> get onChanged => _changed.stream;

  bool _cancelled = false;
  bool get cancelled => _cancelled;

  Future<void>? _done;

  /// Starts the queue (once); completes when every pack is finished.
  Future<void> start() => _done ??= _runAll();

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final job in jobs) {
      if (job.state == PackImportJobState.waiting) {
        job.state = PackImportJobState.cancelled;
      }
    }
    _notify();
  }

  Future<void> _runAll() async {
    for (final job in jobs) {
      if (_cancelled) break;
      if (job.state != PackImportJobState.waiting) continue;

      job.state = PackImportJobState.running;
      _notify();
      try {
        await job.run((fraction, imagesDone) {
          job.fraction = fraction.clamp(0, 1).toDouble();
          job.imagesDone = imagesDone;
          _notify();
        });
        job.state = PackImportJobState.done;
        job.fraction = 1;
      } catch (e) {
        Log.w("Pack import failed: ${job.name}: $e");
        job.state = PackImportJobState.failed;
        job.error = e.toString();
      }
      _notify();
    }

    status = jobs.any((j) => j.state == PackImportJobState.done) ||
            jobs.every((j) => j.state == PackImportJobState.cancelled)
        ? BackgroundTaskStatus.completed
        : BackgroundTaskStatus.failed;
    _notify();

    if (removeAfter > Duration.zero) {
      Timer(removeAfter, () {
        shouldRemoveTask = true;
        _notify();
      });
    }
  }

  void _notify() {
    if (!_changed.isClosed) _changed.add(null);
  }

  int get total => jobs.length;
  int get doneCount =>
      jobs.where((j) => j.state == PackImportJobState.done).length;
  int get failedCount =>
      jobs.where((j) => j.state == PackImportJobState.failed).length;
  int get waitingCount =>
      jobs.where((j) => j.state == PackImportJobState.waiting).length;
  int get finishedCount => jobs.where((j) => j.finished).length;

  PackImportJob? get current =>
      jobs.where((j) => j.state == PackImportJobState.running).firstOrNull;

  /// Overall progress over all packs, 0–1.
  double get progress {
    if (jobs.isEmpty) return 1;
    var sum = 0.0;
    for (final job in jobs) {
      sum += job.finished ? 1 : job.fraction;
    }
    return sum / jobs.length;
  }

  bool get isFinished => status != BackgroundTaskStatus.running;

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  @override
  String get label => "Importing packs: $finishedCount of $total";

  @override
  Stream<void> get statusChanged => _changed.stream;

  @override
  bool shouldRemoveTask = false;

  @override
  bool get canCallAction => false;

  @override
  void Function()? action;

  @override
  void dispose() {
    _changed.close();
  }
}
