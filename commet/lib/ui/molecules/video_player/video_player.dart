import 'dart:async';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/hover_menu.dart';
import 'package:commet/ui/atoms/tiny_pill.dart';
import 'package:commet/ui/molecules/video_player/video_player_implementation.dart';
import 'package:commet/ui/molecules/video_player/video_playback_speed.dart';
import 'package:commet/ui/molecules/video_player/system_pip.dart';
import 'package:commet/ui/molecules/video_player/video_pip.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:commet/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show Intl;
import 'package:tiamat/tiamat.dart' as tiamat;
import '../../atoms/gradient_background.dart';
import 'video_player_controller.dart';

import '../../atoms/icon_button.dart' as i;

// Vommet: viewer Save shortcut labels (Vommet issue 1053).
String get videoSave => Intl.message("Save video",
    name: "videoSave",
    desc:
        "Save the displayed video to the phone gallery or a chosen desktop file");
String get videoSaving => Intl.message("Saving video",
    name: "videoSaving", desc: "Video save action while a save is in progress");
String get videoMute => Intl.message("Mute",
    name: "videoMute", desc: "Mute the media viewer video");
String get videoUnmute => Intl.message("Unmute",
    name: "videoUnmute", desc: "Unmute the media viewer video");
String get videoFullscreen => Intl.message("Fullscreen",
    name: "videoFullscreen", desc: "Enter fullscreen video playback");
String get videoExitFullscreen => Intl.message("Exit fullscreen",
    name: "videoExitFullscreen", desc: "Leave fullscreen video playback");

String get videoSeekBack => Intl.message(
      "Back 10 seconds",
      name: "videoSeekBack",
      desc: "Video seek back button tooltip",
    );
String get videoSeekForward => Intl.message(
      "Forward 10 seconds",
      name: "videoSeekForward",
      desc: "Video seek forward button tooltip",
    );
String get videoSeekBackFeedback => Intl.message(
      "−10 seconds",
      name: "videoSeekBackFeedback",
      desc: "Video rewind gesture feedback",
    );
String get videoSeekForwardFeedback => Intl.message(
      "+10 seconds",
      name: "videoSeekForwardFeedback",
      desc: "Video forward gesture feedback",
    );

class VideoPlayer extends StatefulWidget {
  const VideoPlayer(this.videoFile,
      {this.thumbnail,
      this.fileName,
      super.key,
      this.canGoFullscreen = false,
      this.onFullscreen,
      this.isFullscreen = false,
      this.isPictureInPicture = false,
      this.streamUrl,
      this.decodeFirstFrame = false,
      this.controller,
      this.doThumbnail = true,
      this.showProgressBar = true,
      this.onPictureInPicture,
      this.onSave});
  final FileProvider videoFile;
  final ImageProvider? thumbnail;
  final Uri? streamUrl;
  final bool showProgressBar;
  final bool canGoFullscreen;
  final bool doThumbnail;
  final bool decodeFirstFrame;
  final String? fileName;
  final Function? onFullscreen;

  /// Vommet issue 756: the button leaves full screen instead.
  final bool isFullscreen;

  /// The compact player reserves double taps for expansion.
  final bool isPictureInPicture;
  final VideoPlayerController? controller;

  /// Vommet: shows a picture-in-picture button ([VideoPip]).
  final VoidCallback? onPictureInPicture;

  /// Only the media viewer supplies saving; timeline and PiP stay unchanged.
  final Future<void> Function()? onSave;

  @override
  State<VideoPlayer> createState() => VideoPlayerState();
}

class VideoPlayerState extends State<VideoPlayer> {
  late VideoPlayerController controller;
  bool saving = false;
  bool controlsFocused = false;
  bool playing = false;
  bool inited = false;
  bool buffering = false;
  DownloadProgress? downloadProgress;
  late bool showThumbnail;

  bool currentlyHovered = true;
  bool isCompleted = false;
  bool showingVolumeSlider = false;
  bool showingPlaybackSpeeds = false;
  double videoProgress = 0;
  bool updateSlider = true;
  Timer? uiHideTimer;
  bool isMuted = false;
  Duration videoLength = Duration.zero;
  int? seekFeedback;
  Timer? seekFeedbackTimer;
  double volume = 100;
  double appliedVolume = 100;

  final GlobalKey menuKey = GlobalKey();

  late List<StreamSubscription> subscriptions;

  bool get shouldShowControls =>
      currentlyHovered ||
      isCompleted ||
      showingVolumeSlider ||
      showingPlaybackSpeeds ||
      (widget.onSave != null && (saving || controlsFocused));

  @override
  void initState() {
    showThumbnail = widget.doThumbnail;

    controller = widget.controller ?? VideoPlayerController();

    setVolume(preferences.playerVolume.value);

    isMuted = preferences.isPlayerMuted.value;

    subscriptions = [
      controller.isBuffering.listen((isBuffering) {
        setState(() {
          buffering = isBuffering;

          if (!isBuffering) {
            showThumbnail = false;
            refreshLength();
          }
        });
      }),
      controller.isCompleted.listen((event) {
        setState(() {
          isCompleted = event;
        });
      }),
      controller.onDownloadProgressed.listen((event) {
        setState(() {
          downloadProgress = event;
        });
      }),
      controller.onProgressed.listen((event) async {
        var length = await controller.getLength();
        if (!mounted) return;
        if (updateSlider) {
          setState(() {
            videoLength = length;
            videoProgress = length > Duration.zero
                ? clampDouble(
                    event.inMicroseconds / length.inMicroseconds,
                    0,
                    1,
                  )
                : 0;
          });
        }
      }),
      controller.onVolumeChanged.listen(onVolumeChanged),
    ];

    super.initState();
    refreshLength();
  }

  Future<void> refreshLength() async {
    if (!controller.attached) return;
    final length = await controller.getLength();
    if (mounted) setState(() => videoLength = length);
  }

  @override
  void didUpdateWidget(covariant VideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A global-keyed player moves back to the timeline/PiP after the viewer.
    // Its disposed viewer focus node cannot deliver a final focus callback.
    if (widget.onSave == null) controlsFocused = false;
  }

  @override
  void dispose() {
    uiHideTimer?.cancel();
    seekFeedbackTimer?.cancel();
    for (var sub in subscriptions) {
      sub.cancel();
    }
    subscriptions.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Vommet issue 1081: in the system's picture-in-picture window the
    // video shows alone; the window has its own controls. The player stays
    // the Stack's first child, so it keeps playing.
    return ValueListenableBuilder(
        valueListenable: SystemPip.active,
        builder: (context, systemPip, _) => LayoutBuilder(
              builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.decodeFirstFrame || inited) pickPlayer(),
                  if (showThumbnail) thumbnail(),
                  if (!systemPip) ...overlays(constraints),
                ],
              ),
            ));
  }

  /// The buffering spinner, seek zones and controls over the video.
  List<Widget> overlays(BoxConstraints constraints) {
    return [
      if (buffering) bufferingWidget(),
      if (BuildConfig.MOBILE && !widget.isPictureInPicture) seekZones(),
      controls(
          viewerBarHeight: widget.onSave == null
              ? 0
              : constraints.maxWidth < 400
                  ? 88
                  : 50,
          compact: constraints.maxWidth < 240,
          short: !widget.isPictureInPicture && constraints.maxHeight < 140),
      if (!widget.isPictureInPicture &&
          (constraints.maxHeight >= 140 || !shouldShowControls))
        seekFeedbackWidget(),
    ];
  }

  Widget bufferingWidget() {
    double? progress;
    final download = downloadProgress;

    if (download != null) {
      progress = download.fraction;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(
              value: progress,
            ),
          ),
          if (download != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
              child: TinyPill(
                  background: Theme.of(context).colorScheme.secondaryContainer,
                  foreground:
                      Theme.of(context).colorScheme.onSecondaryContainer,
                  // Vommet: no "/ -1 B" when the size is unknown.
                  download.hasTotal
                      ? "${TextUtils.readableFileSize(download.downloaded)} / ${TextUtils.readableFileSize(download.total)}"
                      : TextUtils.readableFileSize(download.downloaded)),
            )
        ],
      ),
    );
  }

  Widget thumbnail() {
    return widget.thumbnail != null
        ? Image(
            fit: BoxFit.cover,
            image: widget.thumbnail!,
          )
        : Container(
            color: Colors.black,
          );
  }

  Widget controls(
      {bool compact = false, bool short = false, double viewerBarHeight = 0}) {
    return GestureDetector(
      onTap: () {
        if (BuildConfig.MOBILE) {
          if (shouldShowControls) {
            onUnhovered();
          } else {
            onHovered();
          }
        }
      },
      child: MouseRegion(
        hitTestBehavior: HitTestBehavior.translucent,
        onEnter: (_) {
          onHovered();
        },
        onExit: (_) {
          onUnhovered();
        },
        child: IgnorePointer(
          ignoring: BuildConfig.MOBILE && !shouldShowControls,
          child: Listener(
            // A message/viewer double-tap recognizer can hold the arena even
            // when its child is a button. Let direct controls finish on up;
            // seek-zone taps use their separate, ordinary double-tap arena.
            onPointerUp: (event) {
              // Double-tap holds are installed while processing pointer-up.
              // Release after all recognizers have seen this event.
              scheduleMicrotask(() =>
                  GestureBinding.instance.gestureArena.release(event.pointer));
            },
            child: AnimatedOpacity(
              opacity: shouldShowControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: viewerBarHeight > 0
                            ? viewerBarHeight
                            : short
                                ? 50
                                : 0),
                    child: Align(
                      alignment: Alignment.center,
                      child: Row(
                        textDirection: TextDirection.ltr,
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!widget.isPictureInPicture)
                            skipButton(false, compact: compact, short: short),
                          Opacity(
                            opacity: 0.9,
                            child: tiamat.CircleButton(
                              radius: viewerBarHeight > 0 && short ? 24 : 30,
                              icon: isCompleted
                                  ? Icons.replay
                                  : playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                              onPressed: () {
                                if (isCompleted) return replay();
                                if (playing) return pause();
                                play();
                              },
                            ),
                          ),
                          if (!widget.isPictureInPicture)
                            skipButton(true, compact: compact, short: short),
                        ],
                      ),
                    ),
                  ),
                  if (widget.canGoFullscreen ||
                      widget.showProgressBar ||
                      widget.onSave != null)
                    Align(
                        alignment: Alignment.bottomCenter,
                        child: playbackBar(compact: compact)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget progressSlider() => tiamat.Slider(
        value: videoProgress,
        onChangeEnd: (value) {
          updateSlider = true;
          seekPercent(value);
        },
        onChanged: (value) => setState(() => videoProgress = value),
        onChangeStart: (_) => updateSlider = false,
      );

  Widget playerAction(IconData icon, String tooltip, VoidCallback? onPressed,
          {Key? key}) =>
      Material(
          type: MaterialType.transparency,
          child: IconButton(
              key: key,
              tooltip: tooltip,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(icon, size: 24),
              onPressed: onPressed));

  Widget volumeControl({required bool viewer}) {
    final icon = isMuted
        ? Icons.volume_mute
        : appliedVolume == 0
            ? Icons.volume_off
            : Icons.volume_up;
    void toggle() {
      toggleIsMuted();
      preferences.isPlayerMuted.set(isMuted);
    }

    return SizedBox(
        height: viewer ? 48 : 24,
        width: viewer ? 48 : 24,
        child: HoverMenu(
            key: menuKey,
            menuAlignment: Alignment.bottomCenter,
            parentAlignment: Alignment.topCenter,
            onHoverStateChanged: (hovered) =>
                setState(() => showingVolumeSlider = hovered),
            child: viewer
                ? playerAction(icon, isMuted ? videoUnmute : videoMute, toggle)
                : tiamat.IconButton(icon: icon, onPressed: toggle),
            builder: (context) => RotatedBox(
                quarterTurns: 3,
                child: Container(
                    decoration: BoxDecoration(
                        color: ColorScheme.of(context).surfaceContainer,
                        borderRadius: BorderRadius.circular(8)),
                    child: SizedBox(
                        width: 200,
                        height: 50,
                        child: tiamat.Slider(
                            value: appliedVolume / 100,
                            onChanged: (value) => setVolume(value * 100),
                            onChangeEnd: (_) =>
                                preferences.playerVolume.set(volume)))))));
  }

  // Vommet: viewer-only Save and compact playback controls (Vommet issue 1053).
  Future<void> saveVideo() async {
    if (saving || widget.onSave == null) return;
    setState(() => saving = true);
    try {
      await widget.onSave!();
    } finally {
      if (mounted) {
        setState(() => saving = false);
        if (widget.onSave != null) onHovered();
      }
    }
  }

  Widget saveButton() => Material(
      type: MaterialType.transparency,
      child: Semantics(
          liveRegion: saving,
          child: IconButton(
              key: const ValueKey('video_save'),
              tooltip: saving ? videoSaving : videoSave,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: saving ? null : saveVideo,
              icon: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_alt, size: 24))));

  Widget playbackBar({required bool compact}) {
    final viewer = widget.onSave != null;
    Widget spaced(Widget child) =>
        Padding(padding: EdgeInsets.only(right: compact ? 0 : 8), child: child);
    final speed = VideoPlaybackSpeedButton(
        controller: controller,
        onMenuStateChanged: onPlaybackSpeedMenuStateChanged);
    final actions = <Widget>[
      if (widget.showProgressBar)
        viewer
            ? volumeControl(viewer: true)
            : spaced(volumeControl(viewer: false)),
      if (viewer) saveButton(),
      if (widget.showProgressBar)
        viewer
            ? ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48), child: speed)
            : speed,
      if (widget.onPictureInPicture != null)
        viewer
            ? playerAction(Icons.picture_in_picture_alt_rounded, videoPipOpen,
                widget.onPictureInPicture)
            : spaced(Tooltip(
                message: videoPipOpen,
                child: i.IconButton(
                    icon: Icons.picture_in_picture_alt_rounded,
                    size: 22,
                    onPressed: widget.onPictureInPicture))),
      if (widget.canGoFullscreen)
        viewer
            ? playerAction(
                widget.isFullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                widget.isFullscreen ? videoExitFullscreen : videoFullscreen,
                () => widget.onFullscreen?.call())
            : spaced(i.IconButton(
                icon: widget.isFullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                size: 24,
                onPressed: () => widget.onFullscreen?.call())),
    ];
    return GradientBackground(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        backgroundColor:
            Theme.of(context).colorScheme.surfaceContainerLowest.withAlpha(200),
        child: viewer
            ? Focus(
                onFocusChange: (focused) =>
                    setState(() => controlsFocused = focused),
                child: LayoutBuilder(builder: (context, constraints) {
                  if (constraints.maxWidth < 400) {
                    final seekOnOwnRow =
                        widget.showProgressBar && constraints.maxHeight >= 88;
                    // During viewer transitions the video can briefly be
                    // smaller than the bar. Scroll horizontally so a vertical
                    // swipe still belongs to the viewer.
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      if (seekOnOwnRow)
                        SizedBox(height: 40, child: progressSlider()),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          heightFactor: 1,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            primary: false,
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              if (widget.showProgressBar && !seekOnOwnRow)
                                SizedBox(width: 96, child: progressSlider()),
                              ...actions,
                            ]),
                          ),
                        ),
                      ),
                    ]);
                  }
                  return SizedBox(
                      height: 50,
                      child: Row(children: [
                        if (widget.showProgressBar)
                          Expanded(child: progressSlider())
                        else
                          const Spacer(),
                        ...actions,
                      ]));
                }))
            : SizedBox(
                height: 50,
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (widget.showProgressBar) Expanded(child: progressSlider()),
                  ...actions
                ])));
  }

  void toggleControls() {
    if (shouldShowControls) {
      onUnhovered();
    } else {
      onHovered();
    }
  }

  Widget seekZones() => Row(
        textDirection: TextDirection.ltr,
        children: [
          for (final direction in [-1, 0, 1])
            Expanded(
              child: GestureDetector(
                key: ValueKey("video_seek_zone_$direction"),
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: toggleControls,
                // Even before loading, consume the canvas double tap so it
                // cannot trigger the surrounding message's reply/reaction.
                onDoubleTap: () {
                  if (direction != 0) skip(direction);
                },
              ),
            ),
        ],
      );

  Widget skipButton(bool forward, {bool compact = false, bool short = false}) =>
      Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 8),
        child: Material(
          type: MaterialType.transparency,
          child: IconButton.filledTonal(
            key: ValueKey(forward ? "video_seek_forward" : "video_seek_back"),
            tooltip: forward ? videoSeekForward : videoSeekBack,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            iconSize: 28,
            // A short canvas has no room above the buttons for a badge.
            // Pulse the matching button instead while controls are visible.
            style: short && seekFeedback == (forward ? 1 : -1)
                ? IconButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onPrimaryContainer)
                : null,
            icon: Icon(forward ? Icons.forward_10 : Icons.replay_10),
            onPressed: videoLength > Duration.zero
                ? () => skip(forward ? 1 : -1)
                : null,
          ),
        ),
      );

  Future<void> skip(int direction) async {
    try {
      if (!await controller.seekRelative(Duration(seconds: direction * 10))) {
        return;
      }
      if (!mounted) return;
      seekFeedbackTimer?.cancel();
      setState(() => seekFeedback = direction);
      seekFeedbackTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => seekFeedback = null);
      });
    } catch (error, stack) {
      Log.onError(error, stack, content: "Couldn't seek video");
    }
  }

  Widget seekFeedbackWidget() => IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          child: seekFeedback == null
              ? const SizedBox.shrink()
              : Align(
                  key: ValueKey(seekFeedback),
                  alignment: seekFeedback! < 0
                      ? Alignment.topLeft
                      : Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Semantics(
                      liveRegion: true,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(180),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          child: Text(
                            seekFeedback! < 0
                                ? videoSeekBackFeedback
                                : videoSeekForwardFeedback,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium!
                                .copyWith(
                                    inherit: false,
                                    color: Colors.white,
                                    fontSize: 13,
                                    decoration: TextDecoration.none),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      );

  void pause() async {
    setState(() {
      playing = false;
    });

    controller.pause();
  }

  void play() async {
    setState(() {
      inited = true;
      playing = true;
      isCompleted = false;
      controller.play();
      if (BuildConfig.MOBILE) onUnhovered();
    });
  }

  void replay() async {
    setState(() {
      playing = true;
      controller.replay();
      isCompleted = false;
      if (BuildConfig.MOBILE) onUnhovered();
    });
  }

  void onHovered() {
    setState(() {
      currentlyHovered = true;
    });

    if (BuildConfig.MOBILE) {
      uiHideTimer?.cancel();
      uiHideTimer = Timer(const Duration(seconds: 3), onUnhovered);
    }
  }

  void onUnhovered() {
    setState(() {
      currentlyHovered = false;
    });
    uiHideTimer?.cancel();
  }

  void onPlaybackSpeedMenuStateChanged(bool open) {
    if (!mounted) return;
    setState(() => showingPlaybackSpeeds = open);
    if (open) {
      uiHideTimer?.cancel();
    } else if (BuildConfig.MOBILE) {
      onHovered();
    }
  }

  void seekPercent(double percent) async {
    controller.seekTo(await controller.getLength() * percent);
    setState(() {
      videoProgress = percent;
    });
  }

  void toggleIsMuted() {
    if (!isMuted) {
      setState(() {
        isMuted = true;
        appliedVolume = 0;
      });
      controller.setVolume(0.0);
    } else {
      setState(() {
        isMuted = false;
        appliedVolume = preferences.playerVolume.value;
      });
      controller.setVolume(appliedVolume);
    }

    if (menuKey.currentState case HoverMenuState state) {
      state.entry?.markNeedsBuild();
    }
  }

  void setVolume(double value) {
    setState(() {
      volume = value;
      appliedVolume = value;
      isMuted = false;
    });

    if (menuKey.currentState case HoverMenuState state) {
      state.entry?.markNeedsBuild();
    }

    controller.setVolume(value);
  }

  void onVolumeChanged(double event) {
    setState(() {
      volume = event;
      appliedVolume = isMuted ? 0 : volume;
    });
  }

  Widget pickPlayer() {
    return VideoPlayerImplementation(
      controller: controller,
      videoFile: widget.videoFile,
      decodeFirstFrame: widget.decodeFirstFrame,
      streamUrl: widget.streamUrl,
    );
  }
}
