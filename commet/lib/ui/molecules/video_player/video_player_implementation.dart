import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/cache/streamable_file_provider.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/links/invidious_playback.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'video_player_controller.dart';

class VideoPlayerImplementation extends StatefulWidget {
  const VideoPlayerImplementation(
      {required this.controller,
      required this.videoFile,
      this.decodeFirstFrame = false,
      this.streamUrl,
      this.width = 640,
      this.height = 340,
      super.key});
  final FileProvider videoFile;
  final Uri? streamUrl;
  final int width;
  final int height;
  final bool decodeFirstFrame;
  final VideoPlayerController controller;
  @override
  State<VideoPlayerImplementation> createState() =>
      _VideoPlayerImplementationState();
}

class _VideoPlayerImplementationState extends State<VideoPlayerImplementation> {
  late Player player;
  VideoController? controller;
  bool loaded = false;
  Uri? file;

  @override
  void initState() {
    super.initState();

    player = Player();

    if (preferences.isPlayerMuted.value) {
      player.setVolume(0);
    } else {
      player.setVolume(preferences.playerVolume.value);
    }

    widget.controller.attach(
        pause: pause,
        play: play,
        replay: replay,
        screenshot: screenshot,
        getSize: getSize,
        getVolume: getVolume,
        seekTo: seekTo,
        getLength: getLength,
        setVolume: setVolume);

    player.stream.position.listen((event) {
      widget.controller.setProgress(event);
    });

    player.stream.completed.listen(
      (completed) {
        widget.controller.setCompleted(completed);
      },
    );

    player.stream.volume.listen(widget.controller.handleInternalVolumeChange);

    controller = VideoController(player);

    if (widget.streamUrl == null) {
      Future.microtask(() async {
        widget.controller.setBuffering(true);

        // Vommet: stream the file when it can be (unencrypted Matrix
        // media) instead of waiting for the whole download (Vommet issue
        // 338); the player reports its own buffering while it streams.
        final videoFile = widget.videoFile;
        final source = videoFile is StreamableFileProvider
            ? await (videoFile as StreamableFileProvider).getStreamSource()
            : null;
        if (!mounted) return;

        if (source != null) {
          player.stream.buffering.listen(widget.controller.setBuffering);
          await player.open(
              Playlist(
                  [Media(source.uri.toString(), httpHeaders: source.headers)]),
              play: !widget.decodeFirstFrame);
          if (!mounted) return;

          setState(() {
            loaded = true;
          });
          return;
        }

        var sub = widget.videoFile.onProgressChanged?.listen((data) {
          widget.controller.setBufferingProgress(data);
        });
        file = await widget.videoFile.resolve();

        sub?.cancel();

        await player.open(Playlist([Media(file.toString())]),
            play: !widget.decodeFirstFrame);
        widget.controller.setBuffering(false);

        setState(() {
          loaded = true;
        });
      });
    } else {
      Future.microtask(() async {
        widget.controller.setBuffering(true);

        var host = widget.streamUrl!.host;

        // Vommet issue 175: the Invidious instance the user picked for
        // YouTube is allowed without asking.
        bool allowed =
            preferences.allowedRemoteVideoHosts.value.contains(host) ||
                InvidiousPlayback.isPickedInstance(host);

        if (!allowed) {
          bool? confirmation = await AdaptiveDialog.confirmation(context,
              dangerous: true,
              title: "Stream Remote Video",
              prompt:
                  "Do you want to allow connections to `${widget.streamUrl!.host}` to stream this video?");

          allowed = confirmation == true;
          preferences.allowedRemoteVideoHosts.add(host);
        }

        if (allowed) {
          await player.open(Playlist([Media(widget.streamUrl!.toString())]),
              play: !widget.decodeFirstFrame);
        }

        widget.controller.setBuffering(false);

        setState(() {
          loaded = true;
        });
      });
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loaded) {
      return Video(
        fit: BoxFit.contain,
        controller: controller!,
        controls: null,
      );
    }
    return Container();
  }

  Future<void> pause() async {
    player.pause();
  }

  Future<void> play() async {
    player.play();
  }

  Future<Uint8List?> screenshot() async {
    return player.screenshot();
  }

  Future<void> replay() async {
    await player.seek(Duration.zero);
    await player.play();
  }

  Future<void> seekTo(Duration duration) async {
    await player.seek(duration);
  }

  Future<void> setVolume(double volume) async {
    await player.setVolume(volume);
  }

  Future<Duration> getLength() async {
    return player.state.duration;
  }

  Future<Size?> getSize() async {
    if (player.state.height == null || player.state.width == null) {
      return null;
    }

    return Size(
        player.state.width!.toDouble(), player.state.height!.toDouble());
  }

  Future<double> getVolume() async {
    return player.state.volume;
  }
}
