import 'package:commet/cache/file_provider.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/tiny_pill.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: plays a GIF sent as a video (see `VideoAttachment.isGif`) the way
/// a GIF looks: muted, looping, no controls. With [autoplay] off it shows its
/// preview picture with a play button until tapped. Once playing, a tap
/// calls [onOpen] (the full-screen viewer).
class GifVideoPlayer extends StatefulWidget {
  const GifVideoPlayer(this.videoFile,
      {required this.autoplay, this.thumbnail, this.onOpen, super.key});

  final FileProvider videoFile;
  final ImageProvider? thumbnail;
  final bool autoplay;
  final VoidCallback? onOpen;

  @override
  State<GifVideoPlayer> createState() => _GifVideoPlayerState();
}

class _GifVideoPlayerState extends State<GifVideoPlayer> {
  Player? player;
  VideoController? controller;
  bool started = false;
  bool showingVideo = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) start();
  }

  @override
  void didUpdateWidget(covariant GifVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoplay && !started) start();
  }

  Future<void> start() async {
    if (started) return;
    started = true;
    setState(() {});

    final player = Player();
    this.player = player;
    controller = VideoController(player);
    try {
      await player.setVolume(0);
      await player.setPlaylistMode(PlaylistMode.single);
      final file = await widget.videoFile.resolve();
      if (!mounted || file == null) return;
      await player.open(Media(file.toString()), play: true);
      await controller!.waitUntilFirstFrameRendered;
      if (mounted) setState(() => showingVideo = true);
    } catch (e) {
      Log.w("GIF video failed to play: $e");
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => started ? widget.onOpen?.call() : start(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null)
            Video(
                controller: controller!,
                fit: BoxFit.contain,
                controls: null,
                fill: Colors.transparent),
          if (!showingVideo)
            widget.thumbnail != null
                ? Image(image: widget.thumbnail!, fit: BoxFit.cover)
                : Container(color: Colors.black),
          if (!started)
            Center(
              child: Opacity(
                opacity: 0.9,
                child: tiamat.CircleButton(
                  radius: 24,
                  icon: Icons.gif_rounded,
                  onPressed: start,
                ),
              ),
            )
          else if (!showingVideo)
            const Center(
              child: SizedBox(
                  width: 32, height: 32, child: CircularProgressIndicator()),
            ),
          Positioned(
            left: 6,
            top: 6,
            child: TinyPill("GIF",
                background: colors.surfaceContainerLowest.withAlpha(200),
                foreground: colors.onSurface),
          ),
        ],
      ),
    );
  }
}
