import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:commet/client/attachment.dart';
import 'package:commet/utils/video_gif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// A video turned into a GIF by [VideoGifTrim].
class ConvertedGif {
  const ConvertedGif(this.data, this.width, this.height, this.length);
  final Uint8List data;
  final int width;
  final int height;
  final Duration length;
}

/// Vommet issue 880: the "Trim for GIF" screen. Pick up to
/// [VideoGif.maxClip] of the video; it is made into a GIF on the device.
class VideoGifTrim extends StatefulWidget {
  const VideoGifTrim({required this.attachment, super.key});
  final PendingFileAttachment attachment;

  static String get labelTrimForGif => Intl.message("Trim for GIF",
      name: "labelTrimForGif",
      desc:
          "Title of the screen that picks which part of a video becomes a GIF");

  static String get labelGifLimits => Intl.message(
      "Up to 10 s · 480 px · 12 fps · no sound",
      name: "labelGifLimits",
      desc:
          "The fixed limits of a GIF made from a video, shown on the Trim for GIF screen");

  static String get promptConvert => Intl.message("Convert",
      name: "promptConvert",
      desc: "Button on the Trim for GIF screen that makes the GIF");

  static String get labelMakingGif => Intl.message("Making the GIF…",
      name: "labelMakingGif",
      desc: "Shown with a progress bar while a video is turned into a GIF");

  static String get labelCantMakeGif =>
      Intl.message("Vommet couldn't make a GIF from this video.",
          name: "labelCantMakeGif",
          desc: "Shown when a video can't be turned into a GIF");

  static String labelGifStart(String time) => Intl.message("Start $time",
      name: "labelGifStart",
      args: [time],
      desc: "Where the GIF starts in the video, e.g. Start 0:04.2");

  static String labelGifEnd(String time) => Intl.message("End $time",
      name: "labelGifEnd",
      args: [time],
      desc: "Where the GIF ends in the video, e.g. End 0:09.0");

  /// Opens the screen; null when canceled or the GIF couldn't be made.
  static Future<ConvertedGif?> show(
      BuildContext context, PendingFileAttachment attachment) {
    return showGeneralDialog<ConvertedGif>(
        context: context,
        barrierDismissible: false,
        barrierLabel: "POPUP_DIALOG",
        barrierColor: tiamat.PopupDialog.barrierColor,
        pageBuilder: (context, _, __) => tiamat.PopupDialog(
            title: labelTrimForGif,
            content: VideoGifTrim(attachment: attachment)));
  }

  /// "0:04.2"
  static String formatTime(Duration d) {
    final tenths = d.inMilliseconds ~/ 100;
    final seconds = tenths ~/ 10;
    return "${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, "0")}.${tenths % 10}";
  }

  @override
  State<VideoGifTrim> createState() => _VideoGifTrimState();
}

class _VideoGifTrimState extends State<VideoGifTrim> {
  static const filmstripLength = 8;

  late final Player player;
  late final VideoController controller;
  StreamSubscription<Duration>? positionSub;

  Duration duration = Duration.zero;
  RangeValues range = const RangeValues(0, 0);
  final List<Uint8List?> filmstrip = [];
  bool ready = false;
  bool failed = false;

  /// Frames done while converting, or null when not converting.
  int? done;
  int total = 0;
  bool canceled = false;

  Duration get start => Duration(milliseconds: range.start.round());
  Duration get end => Duration(milliseconds: range.end.round());

  @override
  void initState() {
    player = Player();
    controller = VideoController(player);
    load();
    super.initState();
  }

  @override
  void dispose() {
    canceled = true;
    positionSub?.cancel();
    player.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final file = widget.attachment;
      final Media media = file.path != null
          ? Media(file.path!)
          : await Media.memory(file.data!, type: file.mimeType);
      await player.setVolume(0);
      await player.open(media, play: false);
      final length = await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 10));
      await player.stream.width
          .firstWhere((w) => (w ?? 0) > 0)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final first = (length < VideoGif.maxClip ? length : VideoGif.maxClip)
          .inMilliseconds
          .toDouble();
      setState(() {
        duration = length;
        range = RangeValues(0, first);
      });

      // Small pictures along the video, so the right part is easy to find.
      for (var i = 0; i < filmstripLength && mounted && !canceled; i++) {
        final at = length * ((i + 0.5) / filmstripLength);
        filmstrip.add(await grabThumbnail(at));
        if (mounted) setState(() {});
      }
      if (!mounted || canceled) return;

      await player.seek(start);
      positionSub = player.stream.position.listen(loop);
      await player.setPlaylistMode(PlaylistMode.none);
      await player.play();
      setState(() => ready = true);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  /// Keeps the preview inside the chosen part.
  void loop(Duration position) {
    if (done != null) return;
    if (position >= end || position < start - const Duration(seconds: 1)) {
      player.seek(start);
    }
  }

  Future<void> seekExactly(Duration at) async {
    await player.seek(at);
    try {
      await player.stream.position
          .firstWhere((p) => (p - at).abs() < const Duration(milliseconds: 60))
          .timeout(const Duration(milliseconds: 600));
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  Future<Uint8List?> grabThumbnail(Duration at) async {
    await seekExactly(at);
    try {
      final shot = await player.screenshot(format: "image/jpeg");
      if (shot == null) return null;
      return compute(_thumbnail, shot);
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _thumbnail(Uint8List jpeg) {
    final small = VideoGif.shrinkEncoded(jpeg, edge: 96);
    return small == null ? null : img.encodeJpg(small, quality: 70);
  }

  /// One GIF frame at [at], [width]×[height].
  Future<img.Image?> grabFrame(Duration at, int width, int height) async {
    await seekExactly(at);
    if (!kIsWeb) {
      final raw = await player.screenshot(format: null);
      if (raw == null) return null;
      final p = player.state.videoParams;
      final turned = (p.rotate ?? 0) % 180 != 0;
      final (pw, ph) = turned ? (p.h ?? 0, p.w ?? 0) : (p.w ?? 0, p.h ?? 0);
      // libmpv's screenshot is the decoded size, turned upright; fall back
      // to the other sizes the player reports.
      final layout = VideoGif.rawLayout(raw.length, [
        (pw, ph),
        (player.state.width ?? 0, player.state.height ?? 0),
        (ph, pw),
      ]);
      if (layout != null) {
        final (w, h, stride) = layout;
        return compute(_downscale, (raw, w, h, stride, width, height));
      }
    }
    final shot = await player.screenshot(format: "image/jpeg");
    if (shot == null) return null;
    final frame = await compute(_shrink, shot);
    if (frame == null) return null;
    if (frame.width == width && frame.height == height) return frame;
    return img.copyResize(frame,
        width: width, height: height, interpolation: img.Interpolation.average);
  }

  static img.Image _downscale((Uint8List, int, int, int, int, int) a) =>
      VideoGif.downscaleBgra(a.$1, a.$2, a.$3, a.$4, a.$5, a.$6);

  static img.Image? _shrink(Uint8List jpeg) => VideoGif.shrinkEncoded(jpeg);

  static Uint8List _encode(List<img.Image> frames) => VideoGif.encode(frames);

  Future<void> convert() async {
    final times = VideoGif.frameTimes(start, end);
    setState(() {
      done = 0;
      total = times.length + 1;
    });
    try {
      await player.pause();
      final (width, height) = VideoGif.targetSize(
          player.state.width ?? 0, player.state.height ?? 0);
      if (width <= 0 || height <= 0) throw StateError("no video size");

      final frames = <img.Image>[];
      for (final t in times) {
        if (canceled) return;
        final frame = await grabFrame(t, width, height);
        if (frame != null) frames.add(frame);
        if (mounted) setState(() => done = done! + 1);
      }
      if (frames.isEmpty || canceled) throw StateError("no frames");

      Uint8List data;
      if (kIsWeb) {
        // No isolates on the web: encode a frame at a time so the progress
        // bar still moves.
        final encoder = img.GifEncoder(repeat: 0, samplingFactor: 10);
        for (final frame in frames) {
          encoder.addFrame(frame, duration: VideoGif.delayCentiseconds);
          await Future<void>.delayed(Duration.zero);
        }
        data = encoder.finish()!;
      } else {
        data = await compute(_encode, frames);
      }
      if (!mounted || canceled) return;
      Navigator.of(context).pop(ConvertedGif(data, width, height,
          Duration(milliseconds: frames.length * 1000 ~/ VideoGif.fps)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        done = null;
        failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final converting = done != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: Video(controller: controller, controls: NoVideoControls),
              ),
            ),
          ),
          if (failed)
            tiamat.Text.labelLow(VideoGifTrim.labelCantMakeGif)
          else if (duration == Duration.zero)
            const LinearProgressIndicator()
          else
            buildRange(colors, converting),
          tiamat.Text.labelLow(VideoGifTrim.labelGifLimits),
          if (converting) ...[
            tiamat.Text.labelLow(VideoGifTrim.labelMakingGif),
            LinearProgressIndicator(value: total == 0 ? null : done! / total),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              tiamat.Button.secondary(
                text: MaterialLocalizations.of(context).cancelButtonLabel,
                onTap: () {
                  canceled = true;
                  Navigator.of(context).pop();
                },
              ),
              if (!failed)
                tiamat.Button(
                  text: VideoGifTrim.promptConvert,
                  onTap: ready && !converting ? convert : null,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildRange(ColorScheme colors, bool converting) {
    final top = duration.inMilliseconds.toDouble();
    final longest = VideoGif.maxClip.inMilliseconds.toDouble();
    final shortest = min(VideoGif.minClip.inMilliseconds.toDouble(),
        duration.inMilliseconds.toDouble());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    children: [
                      for (var i = 0; i < filmstripLength; i++)
                        Expanded(
                          child: i < filmstrip.length && filmstrip[i] != null
                              ? Image.memory(filmstrip[i]!,
                                  fit: BoxFit.cover, gaplessPlayback: true)
                              : ColoredBox(
                                  color: colors.surfaceContainerHighest),
                        ),
                    ],
                  ),
                ),
              ),
              RangeSlider(
                values: range,
                min: 0,
                max: top,
                onChanged: converting || !ready
                    ? null
                    : (value) {
                        var s = value.start, e = value.end;
                        // Keep the clip between the shortest and longest
                        // GIF, moving the other handle along.
                        if (e - s > longest) {
                          if (s != range.start) {
                            e = s + longest;
                          } else {
                            s = e - longest;
                          }
                        }
                        if (e - s < shortest) {
                          if (s != range.start) {
                            s = top - shortest < s ? top - shortest : s;
                            e = s + shortest;
                          } else {
                            e = e < shortest ? shortest : e;
                            s = e - shortest;
                          }
                        }
                        setState(() => range = RangeValues(s, e));
                      },
                onChangeEnd: (_) => player.seek(start),
              ),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            tiamat.Text.labelLow(
                VideoGifTrim.labelGifStart(VideoGifTrim.formatTime(start))),
            tiamat.Text.label(
                "${((end - start).inMilliseconds / 1000).toStringAsFixed(1)} s"),
            tiamat.Text.labelLow(
                VideoGifTrim.labelGifEnd(VideoGifTrim.formatTime(end))),
          ],
        ),
      ],
    );
  }
}
