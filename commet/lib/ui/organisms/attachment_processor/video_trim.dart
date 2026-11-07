import 'dart:async';

import 'package:commet/client/attachment.dart';
import 'package:commet/utils/video_frames_android.dart';
import 'package:commet/utils/video_trim.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Vommet issue 1051: the approved keyframe-snapping interaction, shared by both send flows.
class VideoTrimAction extends StatefulWidget {
  const VideoTrimAction(
      {required this.file,
      required this.edit,
      required this.onChanged,
      this.beforeEdit,
      this.enabled = true,
      super.key});
  final PendingFileAttachment file;
  final VideoTrimEdit? edit;
  final ValueChanged<VideoTrimEdit?> onChanged;
  final VoidCallback? beforeEdit;
  final bool enabled;
  // The editor can be supplied by widget fixtures without a platform player.
  static Future<VideoTrimEdit?> Function(
          BuildContext, PendingFileAttachment, VideoTrimEdit?) editor =
      VideoTrimDialog.show;
  static String get label => Intl.message('Trim video', name: 'videoTrimLabel');
  static String get reset => Intl.message('Reset trim', name: 'videoTrimReset');
  static void showReadError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(Intl.message(
            'The trimmed video could not be read. Reset trim or try again.',
            name: 'videoTrimReadError'))));
  }

  @override
  State<VideoTrimAction> createState() => _VideoTrimActionState();
}

class _VideoTrimActionState extends State<VideoTrimAction> {
  late final supported = VideoTrimJob.available();
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
      future: supported,
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return Material(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withAlpha(240),
            borderRadius: BorderRadius.circular(8),
            child: Wrap(alignment: WrapAlignment.end, children: [
              TextButton.icon(
                  key: const ValueKey('video-trim'),
                  icon: const Icon(Icons.content_cut, size: 18),
                  label: Text(VideoTrimAction.label),
                  onPressed: widget.enabled
                      ? () async {
                          widget.beforeEdit?.call();
                          final result = await VideoTrimAction.editor(
                              context, widget.file, widget.edit);
                          if (result == null) return;
                          if (!mounted) {
                            await result.release();
                            return;
                          }
                          widget.onChanged(result);
                        }
                      : null),
              if (widget.edit != null)
                IconButton(
                    key: const ValueKey('video-trim-reset'),
                    tooltip: VideoTrimAction.reset,
                    icon: const Icon(Icons.undo),
                    onPressed: widget.enabled
                        ? () {
                            widget.beforeEdit?.call();
                            widget.onChanged(null);
                          }
                        : null),
            ]));
      });
}

class VideoTrimDialog extends StatefulWidget {
  const VideoTrimDialog(
      {required this.original, this.edit, this.preview, this.job, super.key});
  final PendingFileAttachment original;
  final VideoTrimEdit? edit;
  final Widget? preview;
  final VideoTrimJob? job;
  static String get hint => Intl.message(
      'Cuts snap to keyframes, which may be seconds apart. Sound stays on.',
      name: 'videoTrimHint');
  static String get limits => Intl.message(
      'Android 15 · SDR H.264 MP4 · 48 kHz AAC-LC or silent · up to 2 min / 64 MB',
      name: 'videoTrimLimits');
  static String get failed => Intl.message(
      "This video can't be trimmed here. Your attachment is unchanged.",
      name: 'videoTrimFailed');
  static String get apply => Intl.message('Apply', name: 'videoTrimApply');
  static String get cancel => Intl.message('Cancel', name: 'videoTrimCancel');
  static String get startLabel => Intl.message('Start', name: 'videoTrimStart');
  static String get endLabel => Intl.message('End', name: 'videoTrimEnd');
  static String get eof => Intl.message('End of video', name: 'videoTrimEof');
  static String get saving =>
      Intl.message('Saving trim…', name: 'videoTrimSaving');
  static Future<VideoTrimEdit?> show(BuildContext context,
          PendingFileAttachment file, VideoTrimEdit? edit) =>
      showDialog<VideoTrimEdit>(
          context: context,
          barrierDismissible: false,
          builder: (_) => Dialog(
              child: VideoTrimDialog(
                  original: edit?.original ?? file.snapshotForSend(),
                  edit: edit)));
  @override
  State<VideoTrimDialog> createState() => _VideoTrimDialogState();
}

class _VideoTrimDialogState extends State<VideoTrimDialog> {
  late final job = widget.job ?? VideoTrimJob();
  Player? player;
  VideoController? controller;
  StreamSubscription<Duration>? positions;
  StreamSubscription<bool>? completed;
  List<Widget> frames = [];
  int first = 0, last = 0;
  bool ready = false, error = false, saving = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      await job.load(widget.original);
      if (!mounted) return;
      first = (widget.edit?.first ?? 0).clamp(0, job.cuts.length - 2);
      last = (widget.edit?.last ?? job.cuts.length - 1)
          .clamp(first + 1, job.cuts.length - 1);
      if (widget.preview == null) {
        player = Player();
        controller = VideoController(player!);
        await player!.open(Media(job.source!.path), play: false);
        await player!.setVolume(100);
        await player!.seek(Duration(microseconds: job.cuts[first]));
        positions = player!.stream.position.listen((at) {
          if (ready &&
              !saving &&
              (at.inMicroseconds >= job.cuts[last] ||
                  at.inMicroseconds < job.cuts[first] - 100000))
            player!.seek(Duration(microseconds: job.cuts[first]));
        });
        completed = player!.stream.completed.listen((done) {
          if (done && ready && !saving) {
            player!.seek(Duration(microseconds: job.cuts[first]));
            player!.play();
          }
        });
      }
      if (!mounted) return;
      setState(() => ready = true);
      unawaited(filmstrip());
    } catch (_) {
      if (mounted) setState(() => error = true);
    }
  }

  Future<void> filmstrip() async {
    try {
      final shots =
          await VideoFramesAndroid.thumbnails(job.source!.path, count: 8);
      if (mounted)
        setState(() => frames = [
              for (final shot in shots)
                Expanded(
                    child: shot == null
                        ? const SizedBox()
                        : Image.memory(shot, height: 40, fit: BoxFit.cover))
            ]);
    } catch (_) {} // A filmstrip is optional; cut points are not.
  }

  @override
  void dispose() {
    job.cancel();
    unawaited(() async {
      try {
        await positions?.cancel();
        await completed?.cancel();
        await player?.dispose();
      } finally {
        await job.close();
      }
    }()
        .catchError((_) {}));
    super.dispose();
  }

  String time(int i) {
    if (i == job.cuts.length - 1) return VideoTrimDialog.eof;
    final ms = job.cuts[i] ~/ 1000;
    return '${ms ~/ 60000}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}';
  }

  void select(int a, int b) {
    setState(() {
      first = a;
      last = b;
    });
    player?.pause();
    player?.seek(Duration(microseconds: job.cuts[first]));
  }

  Future<void> save() async {
    if (saving || !ready || error) return;
    setState(() => saving = true);
    try {
      await player?.pause();
      final result = await job.save(widget.original, first, last);
      if (!mounted) return;
      job.transferred = true;
      Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted)
        setState(() {
          saving = false;
          error = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !saving,
      child: SizedBox(
          width: 520,
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                tiamat.Text.largeTitle(VideoTrimAction.label),
                Text(VideoTrimDialog.limits),
                if (error)
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(VideoTrimDialog.failed))
                else if (!ready)
                  const LinearProgressIndicator()
                else ...[
                  SizedBox(
                      height: 200,
                      child: widget.preview ?? Video(controller: controller!)),
                  Text(VideoTrimDialog.hint),
                  if (frames.isNotEmpty) Row(children: frames),
                  RangeSlider(
                      key: const ValueKey('video-trim-range'),
                      min: 0,
                      max: job.cuts.last.toDouble(),
                      values: RangeValues(job.cuts[first].toDouble(),
                          job.cuts[last].toDouble()),
                      onChanged: saving
                          ? null
                          : (range) {
                              int nearest(double value) =>
                                  List.generate(job.cuts.length, (i) => i)
                                      .reduce((a, b) =>
                                          (job.cuts[a] - value).abs() <=
                                                  (job.cuts[b] - value).abs()
                                              ? a
                                              : b);
                              final a = nearest(range.start)
                                  .clamp(0, job.cuts.length - 2);
                              select(
                                  a,
                                  nearest(range.end)
                                      .clamp(a + 1, job.cuts.length - 1));
                            }),
                  Row(children: [
                    for (final start in [true, false])
                      Expanded(
                          child: InputDecorator(
                              decoration: InputDecoration(
                                  labelText: start
                                      ? VideoTrimDialog.startLabel
                                      : VideoTrimDialog.endLabel),
                              child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                      isExpanded: true,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                      value: start ? first : last,
                                      items: [
                                        for (var i = start ? 0 : first + 1;
                                            i <
                                                (start
                                                    ? last
                                                    : job.cuts.length);
                                            i++)
                                          DropdownMenuItem(
                                              value: i,
                                              child: Text(time(i),
                                                  overflow:
                                                      TextOverflow.ellipsis))
                                      ],
                                      onChanged: saving
                                          ? null
                                          : (v) {
                                              if (v != null)
                                                select(start ? v : first,
                                                    start ? last : v);
                                            }))))
                  ]),
                  if (saving) ...[
                    const LinearProgressIndicator(),
                    Text(VideoTrimDialog.saving)
                  ],
                ],
                Wrap(spacing: 12, children: [
                  TextButton(
                      onPressed: () {
                        job.cancel();
                        Navigator.of(context).pop();
                      },
                      child: Text(VideoTrimDialog.cancel)),
                  if (ready && !error)
                    FilledButton(
                        key: const ValueKey('video-trim-apply'),
                        onPressed:
                            saving || first == 0 && last == job.cuts.length - 1
                                ? null
                                : save,
                        child: Text(VideoTrimDialog.apply))
                ]),
              ]))));
}
