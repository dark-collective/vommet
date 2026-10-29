import 'dart:async';

import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:commet/ui/organisms/background_task_view/pack_import_queue_view.dart';
import 'package:commet/utils/background_tasks/pack_import_queue_task.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class BackgroundTaskView extends StatefulWidget {
  const BackgroundTaskView(this.manager, {super.key});
  final BackgroundTaskManager manager;

  @override
  State<BackgroundTaskView> createState() => _BackgroundTaskViewState();
}

class _BackgroundTaskViewState extends State<BackgroundTaskView> {
  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    sub = widget.manager.onListUpdate.listen(onTaskListUpdated);
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(blurRadius: 4, color: Theme.of(context).shadowColor)
            ]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.manager.tasks
                  .map((e) => e is PackImportQueueTask
                      // Vommet: the multi-pack sticker import's own card.
                      ? PackImportQueueView(
                          e,
                          key: ValueKey("task-display${e.hashCode}"),
                        )
                      : _SingleBackgroundTaskView(
                          e,
                          key: ValueKey("task-display${e.hashCode}"),
                        ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  void onTaskListUpdated(event) {
    setState(() {});
  }
}

class _SingleBackgroundTaskView extends StatefulWidget {
  const _SingleBackgroundTaskView(this.task, {super.key});
  final BackgroundTask task;

  @override
  State<_SingleBackgroundTaskView> createState() =>
      __SingleBackgroundTaskViewState();
}

class __SingleBackgroundTaskViewState extends State<_SingleBackgroundTaskView> {
  StreamSubscription? progressSubscription;
  StreamSubscription? completeSubscription;
  double? progress;
  late BackgroundTaskStatus status;

  @override
  void initState() {
    status = widget.task.status;
    completeSubscription = widget.task.statusChanged.listen((event) {
      onTaskComplete();
    });
    if (widget.task is BackgroundTaskWithIntegerProgress) {
      var progressTask = (widget.task as BackgroundTaskWithIntegerProgress);
      progressSubscription = progressTask.onProgress.listen(onTaskProgressed);

      progress = progressTask.current / progressTask.total;
    }

    if (widget.task is BackgroundTaskWithOptionalProgress) {
      var task = (widget.task as BackgroundTaskWithOptionalProgress);
      progress = task.progress;
      progressSubscription = task.statusChanged.listen(onOptionalProgress);
    }
    super.initState();
  }

  @override
  void dispose() {
    progressSubscription?.cancel();
    completeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.task is BackgroundTaskWithDetails) return buildDetailed(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap:
            widget.task.canCallAction ? () => widget.task.action?.call() : null,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          // Vommet: as wide as its label, and the label wraps when the
          // window is narrower (the floating tile now caps its width at the
          // window's, so a max-size row would stretch to the full window).
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
                child: SizedBox(
                    width: 10,
                    height: 10,
                    child: status == BackgroundTaskStatus.completed
                        ? const Icon(
                            Icons.check,
                            color: Colors.greenAccent,
                            size: 10,
                          )
                        : status == BackgroundTaskStatus.failed
                            ? Icon(
                                Icons.error,
                                color: Theme.of(context).colorScheme.error,
                                size: 10,
                              )
                            : CircularProgressIndicator(
                                strokeWidth: 2,
                                value: progress,
                              )),
              ),
              Flexible(child: tiamat.Text.tiny(widget.task.label))
            ],
          ),
        ),
      ),
    );
  }

  /// Vommet: label + Cancel, a progress bar, and a detail line (e.g. the
  /// rooms a batch join couldn't join).
  Widget buildDetailed(BuildContext context) {
    final task = widget.task as BackgroundTaskWithDetails;
    final scheme = Theme.of(context).colorScheme;
    final detail = task.detail;
    return SizedBox(
      width: 320,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: status == BackgroundTaskStatus.completed
                      ? const Icon(Icons.check,
                          color: Colors.greenAccent, size: 12)
                      : status == BackgroundTaskStatus.failed
                          ? Icon(Icons.error, color: scheme.error, size: 12)
                          : CircularProgressIndicator(
                              strokeWidth: 2, value: progress),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(task.label,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (task.canCancel)
                  TextButton(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () => setState(task.cancel),
                    child: Text(CommonStrings.promptCancel),
                  ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: scheme.surfaceContainerHighest),
              ),
            ],
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(detail,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }

  void onTaskComplete() {
    setState(() {
      status = widget.task.status;
    });
  }

  void onTaskProgressed(int event) {
    setState(() {
      progress =
          event / (widget.task as BackgroundTaskWithIntegerProgress).total;
    });
  }

  void onOptionalProgress(void event) {
    setState(() {
      progress = (widget.task as BackgroundTaskWithOptionalProgress).progress;
    });
  }
}
