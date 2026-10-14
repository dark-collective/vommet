import 'dart:async';
import 'dart:math' as math;

import 'package:commet/utils/background_tasks/pack_import_queue_task.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: the multi-pack sticker import's card among the background tasks:
/// one row per pack (ready / progress / waiting / couldn't load) with
/// Cancel. With more than [collapseAbove] packs it starts collapsed to one
/// overall bar; the arrow opens a list capped at about [maxRows] rows that
/// follows the pack being uploaded. It never grows past that.
class PackImportQueueView extends StatefulWidget {
  const PackImportQueueView(this.task, {super.key});
  final PackImportQueueTask task;

  static const collapseAbove = 5;
  static const maxRows = 7;
  static const rowHeight = 32.0;

  @override
  State<PackImportQueueView> createState() => _PackImportQueueViewState();
}

class _PackImportQueueViewState extends State<PackImportQueueView> {
  StreamSubscription? sub;
  late bool expanded;
  final ScrollController scroll = ScrollController();
  PackImportJob? followed;

  String labelPackImportHeader(int done, int total) =>
      Intl.message("Importing packs · $done of $total",
          args: [done, total],
          name: "labelPackImportHeader",
          desc: "Header of the background sticker pack import card");

  String labelPackImportFinished(int done, int total) =>
      Intl.message("Imported $done of $total packs",
          args: [done, total],
          name: "labelPackImportFinished",
          desc: "Header of the sticker pack import card once it's finished");

  String labelPackImportNow(String pack, int done, int total) =>
      Intl.message("Now: $pack · $done of $total images",
          args: [pack, done, total],
          name: "labelPackImportNow",
          desc: "Collapsed sticker import card: the pack being uploaded");

  String labelPackImportLeft(int waiting, int failed) =>
      Intl.message("$waiting waiting · $failed couldn't load",
          args: [waiting, failed],
          name: "labelPackImportLeft",
          desc: "Collapsed sticker import card: packs not started / failed");

  String get labelPackImportReady => Intl.message("Ready to use",
      name: "labelPackImportReady",
      desc: "Sticker import card: this pack is imported and usable");

  String get labelPackImportWaiting => Intl.message("Waiting",
      name: "labelPackImportWaiting",
      desc: "Sticker import card: this pack hasn't started yet");

  String get labelPackImportFailed => Intl.message("Couldn't load",
      name: "labelPackImportFailed",
      desc: "Sticker import card: this pack failed");

  String get labelPackImportCancelled => Intl.message("Cancelled",
      name: "labelPackImportCancelled",
      desc: "Sticker import card: this pack was cancelled before it started");

  String get promptCancelPackImport => Intl.message("Cancel",
      name: "promptCancelPackImport",
      desc: "Stops the packs of a sticker import that haven't started");

  @override
  void initState() {
    super.initState();
    expanded = widget.task.total <= PackImportQueueView.collapseAbove;
    sub = widget.task.onChanged.listen((_) {
      if (!mounted) return;
      setState(() {});
      followCurrent();
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    scroll.dispose();
    super.dispose();
  }

  /// Keeps the opened list on the pack being uploaded.
  void followCurrent() {
    final current = widget.task.current;
    if (current == null || current == followed) return;
    followed = current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      final index = widget.task.jobs.indexOf(current);
      final target = math.max(0.0, (index - 2) * PackImportQueueView.rowHeight);
      scroll.animateTo(math.min(target, scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final colors = Theme.of(context).colorScheme;
    final collapsible = task.total > PackImportQueueView.collapseAbove;
    final width = math.min(360.0, MediaQuery.of(context).size.width - 40);

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: tiamat.Text.labelEmphasised(
                      task.isFinished
                          ? labelPackImportFinished(task.doneCount, task.total)
                          : labelPackImportHeader(
                              task.finishedCount, task.total),
                      overflow: TextOverflow.ellipsis),
                ),
                if (collapsible)
                  tiamat.IconButton(
                    icon: expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    size: 20,
                    onPressed: () => setState(() {
                      expanded = !expanded;
                      followed = null;
                      followCurrent();
                    }),
                  ),
                if (!task.isFinished && !task.cancelled)
                  TextButton(
                    onPressed: task.cancel,
                    child: Text(promptCancelPackImport),
                  ),
              ],
            ),
            if (collapsible)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 4, 6),
                child: LinearProgressIndicator(
                    value: task.progress,
                    borderRadius: BorderRadius.circular(4)),
              ),
            if (!expanded) collapsedDetail(colors),
            if (expanded)
              ConstrainedBox(
                constraints: const BoxConstraints(
                    maxHeight: PackImportQueueView.maxRows *
                        PackImportQueueView.rowHeight),
                child: Scrollbar(
                  controller: scroll,
                  child: ListView.builder(
                    controller: scroll,
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(right: 8),
                    itemExtent: PackImportQueueView.rowHeight,
                    itemCount: task.jobs.length,
                    itemBuilder: (context, i) =>
                        jobRow(context, task.jobs[i], colors),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget collapsedDetail(ColorScheme colors) {
    final task = widget.task;
    final current = task.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (current != null)
          tiamat.Text.labelLow(
              labelPackImportNow(
                  current.name, current.imagesDone, current.imageCount),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
        tiamat.Text.labelLow(
            labelPackImportLeft(task.waitingCount, task.failedCount)),
      ],
    );
  }

  Widget jobRow(BuildContext context, PackImportJob job, ColorScheme colors) {
    Widget status = switch (job.state) {
      PackImportJobState.done => Row(children: [
          const Icon(Icons.check, size: 16, color: Colors.green),
          const SizedBox(width: 4),
          Flexible(
              child: tiamat.Text.labelLow(labelPackImportReady,
                  color: Colors.green, overflow: TextOverflow.ellipsis)),
        ]),
      PackImportJobState.running => LinearProgressIndicator(
          value: job.fraction, borderRadius: BorderRadius.circular(4)),
      PackImportJobState.waiting =>
        tiamat.Text.labelLow(labelPackImportWaiting),
      PackImportJobState.cancelled =>
        tiamat.Text.labelLow(labelPackImportCancelled),
      PackImportJobState.failed => Tooltip(
          message: job.error ?? "",
          child: tiamat.Text.labelLow(labelPackImportFailed,
              color: colors.error, overflow: TextOverflow.ellipsis),
        ),
    };

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 22,
            height: 22,
            child: job.thumbnail != null
                ? Image.memory(job.thumbnail!,
                    fit: BoxFit.contain, filterQuality: FilterQuality.medium)
                : Icon(Icons.image_outlined,
                    size: 18, color: colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
            flex: 5,
            child: tiamat.Text.label(job.name,
                overflow: TextOverflow.ellipsis, maxLines: 1)),
        const SizedBox(width: 8),
        Expanded(flex: 5, child: status),
      ],
    );
  }
}
