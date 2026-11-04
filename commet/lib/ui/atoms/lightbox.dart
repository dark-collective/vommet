import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:commet/cache/file_provider.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/auto_download_overlay.dart';
import 'package:commet/ui/atoms/lightbox_feedback.dart';
import 'package:commet/ui/atoms/lightbox_full_screen.dart';
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:commet/ui/atoms/lightbox_menu.dart';
import 'package:commet/ui/atoms/lightbox_transition.dart';
import 'package:commet/ui/atoms/lightbox_zoom.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/molecules/my_gifs_from_viewer.dart';
import 'package:commet/ui/molecules/video_player/system_pip.dart';
import 'package:commet/ui/molecules/video_player/video_pip.dart';
import 'package:commet/ui/molecules/video_player/video_player.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/popup_dialog.dart';

class Lightbox extends StatefulWidget {
  const Lightbox({
    this.image,
    this.video,
    this.thumbnail,
    this.aspectRatio,
    this.contentKey,
    this.customWidget,
    this.videoController,
    this.fileName,
    this.closing = false,
    this.onZoomChanged,
    this.menuButton = true,
    this.adaptiveInsets = false,
    this.onJumpToMessage,
    this.onForward,
    this.onReply,
    this.onPictureInPicture,
    this.myGifsMenuEntry,
    super.key,
  });
  final ImageProvider? image;

  /// Vommet: suggested name when saving the image (e.g. the attachment's).
  final String? fileName;
  final FileProvider? video;
  final ImageProvider? thumbnail;
  final VideoPlayerController? videoController;
  final Widget? customWidget;
  final double? aspectRatio;
  final Key? contentKey;

  /// Vommet: set by the gallery when it closes, so a video page swaps its
  /// player for the thumbnail like [dismiss] does.
  final bool closing;

  /// Vommet: told when the image is zoomed in or back out (the gallery
  /// stops paging while zoomed so a drag pans instead).
  final void Function(bool zoomed)? onZoomChanged;

  /// Vommet issue 766: the ⋮ menu button in the top-right corner. The
  /// gallery shows its own, for the page on screen.
  final bool menuButton;

  /// The gallery's dock reduces the viewport. In a short or narrow viewport,
  /// shrink the desktop margin so the media and its controls stay usable.
  final bool adaptiveInsets;

  /// Vommet issue 771: adds Jump to message to the menu (opened from the
  /// Media tab). Whoever opened the viewer closes it.
  final VoidCallback? onJumpToMessage;

  /// Vommet issue 802: adds Forward to the menu. Whoever opened the viewer
  /// closes it.
  final VoidCallback? onForward;

  /// Vommet issue 894: adds Reply to the menu. Whoever opened the viewer
  /// closes it.
  final VoidCallback? onReply;

  /// Vommet: a video can go on in the picture-in-picture window (menu item
  /// and player button). Whoever opened the viewer closes it.
  final VoidCallback? onPictureInPicture;

  /// My GIFs for the displayed source event, evaluated when its menu opens.
  final MyGifsMenuEntryBuilder? myGifsMenuEntry;

  @override
  State<Lightbox> createState() => _LightboxState();

  static Future<void> show(
    BuildContext context, {
    ImageProvider? image,
    ImageProvider? thumbnail,
    FileProvider? video,
    Widget? customWidget,
    VideoPlayerController? videoController,
    double? aspectRatio,
    String? fileName,
    VoidCallback? onJumpToMessage,
    VoidCallback? onForward,
    VoidCallback? onReply,
    VoidCallback? onPictureInPicture,
    VoidCallback? onPipBackToMessage,
    MyGifsMenuEntryBuilder? myGifsMenuEntry,
    Key? key,
  }) {
    // Vommet issue 1080: a video opened without its own picture-in-picture
    // (a mosaic, the Media tab) still gets one. The window opens once the
    // viewer is popped, with the same player key and controller, like a
    // message does it.
    VideoPipRequest? pip;
    if (video != null && onPictureInPicture == null && customWidget == null) {
      final playerKey = key is GlobalKey ? key : GlobalKey();
      final controller = videoController ?? VideoPlayerController();
      key = playerKey;
      videoController = controller;
      onPictureInPicture = () => pip = pictureInPictureRequest(
            video: video,
            controller: controller,
            playerKey: playerKey,
            aspectRatio: aspectRatio,
            thumbnail: thumbnail,
            fileName: fileName,
            myGifsMenuEntry: myGifsMenuEntry,
            onBackToMessage: onPipBackToMessage,
          );
    }
    void openPip() {
      final request = pip;
      if (request != null) VideoPip.show(request);
    }

    // Vommet experiment: browse the room's pictures and videos.
    if (customWidget == null && preferences.experimentLightboxGallery.value) {
      final gallery = LightboxGallery.showIfInTimeline(context,
          image: image,
          video: video,
          videoController: videoController,
          onPictureInPicture: onPictureInPicture,
          key: key);
      if (gallery != null) return gallery.then((_) => openPip());
    }

    final pictureInPicture = onPictureInPicture;
    final contentKey = key;
    final controller = videoController;
    return showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: "LIGHTBOX",
        barrierColor: PopupDialog.barrierColor,
        pageBuilder: (context, _, __) {
          return LightboxFullScreenScope(
              child: LightboxFeedback(
                  child: Lightbox(
            image: image,
            video: video,
            videoController: controller,
            aspectRatio: aspectRatio,
            thumbnail: thumbnail,
            contentKey: contentKey,
            customWidget: customWidget,
            fileName: fileName,
            myGifsMenuEntry: myGifsMenuEntry,
            onJumpToMessage: onJumpToMessage == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    onJumpToMessage();
                  },
            onForward: onForward == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    onForward();
                  },
            onReply: onReply == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    onReply();
                  },
            onPictureInPicture: pictureInPicture == null || video == null
                ? null
                : () {
                    // The viewer's future completes on the pop; the caller
                    // opens the window then, once the player is free.
                    pictureInPicture();
                    Navigator.of(context).pop();
                  },
            key: GlobalKey(),
          )));
        },
        transitionDuration: const Duration(milliseconds: 300),
        transitionBuilder: (context, animation, secondaryAnimation, child) =>
            LightboxTransition(
              animation: animation,
              child: child,
            )).then((_) => openPip());
  }

  /// Vommet issue 1080: the picture-in-picture window for a video that
  /// isn't tied to a message on screen (a gallery page, a mosaic tile, the
  /// Media tab). [playerKey] and [controller] are the viewer's, so the
  /// player moves into the window and carries on where it was.
  static VideoPipRequest pictureInPictureRequest({
    required FileProvider video,
    required VideoPlayerController controller,
    required GlobalKey playerKey,
    double? aspectRatio,
    ImageProvider? thumbnail,
    String? fileName,
    Uri? streamUrl,
    MyGifsMenuEntryBuilder? myGifsMenuEntry,
    VoidCallback? onBackToMessage,
  }) =>
      VideoPipRequest(
        aspectRatio: aspectRatio,
        player: (context) => VideoPlayer(
          video,
          isPictureInPicture: true,
          streamUrl: streamUrl,
          thumbnail: thumbnail,
          fileName: fileName,
          doThumbnail: true,
          controller: controller,
          key: playerKey,
        ),
        onBackToMessage: onBackToMessage,
        onExpand: () {
          final context = navigator.currentContext;
          if (context == null) return;
          Lightbox.show(context,
              video: video,
              aspectRatio: aspectRatio,
              thumbnail: thumbnail,
              fileName: fileName,
              videoController: controller,
              myGifsMenuEntry: myGifsMenuEntry,
              onPipBackToMessage: onBackToMessage,
              key: playerKey);
        },
      );
}

class _LightboxState extends State<Lightbox>
    with TickerProviderStateMixin, LightboxZoom {
  double aspectRatio = 1;
  bool dismissing = false;
  final controller = TransformationController();
  bool loadingHighQuality = false;

  StreamSubscription? onLodChanged;

  /// Vommet: the viewer's own decode of the image (sharper than the
  /// timeline's on Linux, see [LODImageProvider.forViewer]).
  late final ImageProvider? image = switch (widget.image) {
    LODImageProvider lod => lod.forViewer(),
    var other => other,
  };

  bool rotate = false;

  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 850),
    vsync: this,
  );

  late final Animation<double> rotationAnimation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  ).drive(Tween(begin: -0.25, end: 0.0));

  late final Animation<double> scaleAnimation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  ).drive(Tween(begin: 0.6, end: 1.0));

  late final Animation<double> rotation =
      ConstantTween(0.0).animate(_controller);
  late final Animation<double> scale = ConstantTween(1.0).animate(_controller);

  /// Vommet issue 701: how far a vertical swipe has moved the viewer. Let go
  /// far enough, or flung, it closes; otherwise it springs back.
  double swipeOffset = 0;
  double swipeBackFrom = 0;
  late final AnimationController swipeBack;

  static const double swipeCloseDistance = 120;
  static const double swipeCloseVelocity = 800;

  /// Only the picture or video at its original size: zoomed in, a drag pans
  /// it. Full-screen videos on phones use the swipe to return to the viewer;
  /// full screen on desktop keeps its own way out.
  bool get canSwipeToClose =>
      (widget.image != null || widget.video != null) &&
      widget.customWidget == null &&
      !dismissing &&
      !widget.closing &&
      (!fullScreen ||
          (widget.video != null && LightboxSystemBars.supported())) &&
      controller.value.getMaxScaleOnAxis() <= 1.01;

  void onSwipeUpdate(DragUpdateDetails details) {
    swipeBack.stop();
    setState(() => swipeOffset += details.primaryDelta ?? 0);
  }

  void onSwipeEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final flung = velocity.abs() > swipeCloseVelocity &&
        (swipeOffset == 0 || velocity.sign == swipeOffset.sign);
    if (flung || swipeOffset.abs() > swipeCloseDistance) {
      if (fullScreen) {
        // Vommet issue 961: leave the video's full screen, not the viewer.
        setState(() => swipeOffset = 0);
        LightboxFullScreen.exit();
        return;
      }
      LightboxTransition.setDismissDirection(
          context, swipeOffset == 0 ? velocity : swipeOffset);
      dismiss();
    } else {
      onSwipeCancel();
    }
  }

  void onSwipeCancel() {
    if (swipeOffset == 0) return;
    swipeBackFrom = swipeOffset;
    swipeBack.forward(from: 0);
  }

  @override
  void dispose() {
    final pip = systemPip;
    if (pip != null) SystemPip.remove(pip);
    SystemPip.active.removeListener(onSystemPipChanged);
    swipeBack.dispose();
    onLodChanged?.cancel();
    // Vommet: the viewer's decode can be large; don't keep it cached.
    if (!identical(image, widget.image)) image?.evict();
    super.dispose();
  }

  bool zoomed = false;

  void onTransformChanged() {
    final value = controller.value.getMaxScaleOnAxis() > 1.01;
    if (value == zoomed) return;
    setState(() => zoomed = value);
    widget.onZoomChanged?.call(value);
  }

  /// Vommet issue 694: in the gallery on phones a zoomed-in picture may
  /// draw past its margin and over the faded thumbnail strip, so zooming in
  /// far enough fills the whole screen.
  bool get unclipped =>
      BuildConfig.MOBILE && zoomed && widget.onZoomChanged != null;

  @override
  void initState() {
    super.initState();
    // Vommet issue 1081: a playing video here may go to the system's
    // picture in picture when the app is left.
    final video = widget.videoController;
    if (widget.video != null && video != null && SystemPip.supported) {
      systemPip = SystemPipCandidate(video, aspectRatio: widget.aspectRatio);
      SystemPip.add(systemPip!);
      SystemPip.active.addListener(onSystemPipChanged);
    }
    swipeBack = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    )..addListener(() => setState(() => swipeOffset =
        swipeBackFrom * (1 - Curves.easeOutCubic.transform(swipeBack.value))));
    // Vommet issue 766: the menu button fades while zoomed in.
    controller.addListener(onTransformChanged);

    _controller.stop(canceled: true);

    // Vommet: opening media in the viewer downloads it even when automatic
    // download held it back.
    revealAutoDownload(widget.image);
    revealAutoDownload(widget.thumbnail);

    if (widget.aspectRatio != null) {
      aspectRatio = widget.aspectRatio!;
    }

    if (widget.image != null) {
      getImageInfo();
    }

    if (widget.video != null) {
      getVideoInfo();
    }

    if (image case LODImageProvider lod) {
      onLodChanged = lod.onLODChanged.listen((_) {
        getImageInfo();
      });

      loadingHighQuality = true;
      lod.fetchFullRes().then((_) {
        if (mounted) {
          getImageInfo();

          setState(() {
            loadingHighQuality = false;
          });
        }
      });
    }
  }

  void getImageInfo() async {
    var image = await getImage();
    // Vommet: the viewer may have closed while the image loaded.
    if (!mounted) return;
    setState(() {
      aspectRatio = image.width / image.height;
    });

    shouldRotate();
  }

  void getVideoInfo() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.aspectRatio != null) {
        shouldRotate();
      }

      var size = await widget.videoController?.getSize();
      print(size);
      if (size != null) {
        setState(() {
          aspectRatio = size.width / size.height;
        });
      }

      shouldRotate();
    });
  }

  double counterRotation = 0.25;

  void shouldRotate() {
    if (!MediaQuery.of(context).mobile) {
      return;
    }

    if (widget.image != null && preferences.autoRotateImages.value == false) {
      return;
    }

    if (widget.video != null && preferences.autoRotateVideos.value == false) {
      return;
    }

    var size = MediaQuery.sizeOf(context);
    var screenRatio = size.width / size.height;
    bool prevValue = rotate;
    setState(() {
      rotate = (aspectRatio < 1 && screenRatio > 1) ||
          (aspectRatio > 1 && screenRatio < 1);
    });

    if (rotate != prevValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.value = 0;
        _controller.animateTo(1);
      });
    }
  }

  Future<ui.Image> getImage() {
    Completer<ui.Image> completer = Completer<ui.Image>();

    image!
        .resolve(const ImageConfiguration())
        .addListener(ImageStreamListener((info, synchronousCall) {
      if (!completer.isCompleted) {
        completer.complete(info.image);
      }
    }));
    return completer.future;
  }

  /// Vommet issue 766: the viewer has a menu (pictures and videos).
  bool get hasMenu =>
      widget.customWidget == null &&
      (widget.image != null || widget.video != null);

  Future<void> showMediaMenu(Offset position) =>
      LightboxMenu.show(context, position,
          image: widget.image,
          video: widget.video,
          fileName: widget.fileName,
          onJumpToMessage: widget.onJumpToMessage,
          onForward: widget.onForward,
          onReply: widget.onReply,
          onPictureInPicture: widget.onPictureInPicture,
          myGifsMenuEntry: widget.myGifsMenuEntry);

  SystemPipCandidate? systemPip;

  /// Whether full screen was entered for the system's picture in picture.
  bool fullScreenForSystemPip = false;

  /// Vommet issue 1081: in the system window, only the video shows (the
  /// viewer's full screen); back in the app, the viewer is as it was.
  void onSystemPipChanged() {
    final mine = systemPip != null && identical(SystemPip.armed, systemPip);
    if (SystemPip.active.value) {
      if (mine && fullScreenApplies && !LightboxFullScreen.active.value) {
        fullScreenForSystemPip = true;
        LightboxFullScreen.enter();
      }
    } else if (fullScreenForSystemPip) {
      fullScreenForSystemPip = false;
      LightboxFullScreen.exit();
    }
  }

  /// Vommet issue 1080: picture in picture from the player, full screen
  /// included: full screen ends first, so the window opens over the app.
  VoidCallback? get pictureInPicture {
    final pip = widget.onPictureInPicture;
    if (pip == null) return null;
    return () {
      // Vommet issue 1081: the video now plays in the in-app window, which
      // never goes to the system's picture in picture.
      final candidate = systemPip;
      if (candidate != null) {
        systemPip = null;
        SystemPip.remove(candidate);
      }
      if (fullScreen) LightboxFullScreen.exit();
      pip();
    };
  }

  void dismiss() {
    setState(() {
      dismissing = true;
    });
    Navigator.pop(context, widget.contentKey);
  }

  @override
  Widget buildViewer(BuildContext context) {
    // Vommet issue 662: full screen fills the monitor with the picture or
    // video alone; a click on a picture leaves it, a video keeps its own.
    final fullScreen = this.fullScreen;
    final radius = BorderRadius.circular(fullScreen ? 0 : 10);
    final viewer = RawGestureDetector(
      gestures: {
        _SwipeToCloseRecognizer:
            GestureRecognizerFactoryWithHandlers<_SwipeToCloseRecognizer>(
          _SwipeToCloseRecognizer.new,
          (recognizer) => recognizer
            ..canSwipe = (() => canSwipeToClose)
            ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
            ..onUpdate = onSwipeUpdate
            ..onEnd = onSwipeEnd
            ..onCancel = onSwipeCancel,
        ),
      },
      child: Transform.translate(
        offset: Offset(0, swipeOffset),
        child: buildContent(context, fullScreen, radius),
      ),
    );
    if (!widget.menuButton || !hasMenu || fullScreen) return viewer;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        viewer,
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: LightboxMenuButton(
                hidden: zoomed || dismissing,
                onOpen: showMediaMenu,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildContent(
      BuildContext context, bool fullScreen, BorderRadius radius) {
    const inset = BuildConfig.MOBILE ? 10.0 : 100.0;
    if (!widget.adaptiveInsets) {
      return buildInsetContent(context, fullScreen, radius, inset);
    }
    return LayoutBuilder(builder: (context, constraints) {
      final padding = MediaQuery.paddingOf(context);
      final available = math.min(constraints.maxWidth - padding.horizontal,
          constraints.maxHeight - padding.vertical);
      final adaptive = ((available - 160) / 2).clamp(0.0, inset).toDouble();
      return buildInsetContent(context, fullScreen, radius, adaptive);
    });
  }

  Widget buildInsetContent(BuildContext context, bool fullScreen,
      BorderRadius radius, double inset) {
    // Vommet issue 756: a full-screen video follows the phone's own
    // orientation, so the viewer doesn't turn it.
    final turned = rotate && !fullScreen;
    return GestureDetector(
      onTap: () {
        if (!fullScreen) {
          dismiss();
        } else if (widget.image != null) {
          LightboxFullScreen.exit();
        }
      },
      child: Container(
        color: fullScreen ? Colors.black : Colors.transparent,
        child: Padding(
          padding: fullScreen ? EdgeInsets.zero : EdgeInsets.all(inset),
          child: ScaledSafeArea(
            child: RotatedBox(
              quarterTurns: turned ? 1 : 0,
              child: ScaleTransition(
                scale: turned ? scaleAnimation : scale,
                child: RotationTransition(
                  turns: turned ? rotationAnimation : rotation,
                  child: ClipRRect(
                    borderRadius: radius,
                    clipBehavior: unclipped ? Clip.none : Clip.antiAlias,
                    child: RedactedImage(
                        child: InteractiveViewer(
                      clipBehavior: unclipped ? Clip.none : Clip.hardEdge,
                      trackpadScrollCausesScale: true,
                      key: zoomViewerKey,
                      transformationController: controller,
                      maxScale: 3.5,
                      child: Container(
                        alignment: Alignment.center,
                        child: ClipRRect(
                          borderRadius: radius,
                          child: GestureDetector(
                            onTapUp: fullScreen && widget.image != null
                                ? (_) => LightboxFullScreen.exit()
                                : onZoomTapUp,
                            onDoubleTapDown: onZoomDoubleTapDown,
                            onDoubleTap: onZoomDoubleTap,
                            onTap: () {},
                            // Vommet: right-click (long-press on phones) the
                            // image for Save as.
                            onSecondaryTapUp: widget.image == null
                                ? null
                                : (d) => showMediaMenu(d.globalPosition),
                            onLongPressStart: widget.image == null
                                ? null
                                : (d) => showMediaMenu(d.globalPosition),
                            child: AspectRatio(
                                aspectRatio: aspectRatio,
                                child: widget.customWidget ??
                                    (widget.image != null
                                        ? Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Image(
                                                fit: BoxFit.cover,
                                                image: image!,
                                                isAntiAlias: true,
                                                filterQuality:
                                                    FilterQuality.medium,
                                              ),
                                              if (loadingHighQuality)
                                                Align(
                                                  alignment:
                                                      Alignment.bottomRight,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            8.0),
                                                    child: Container(
                                                        decoration: BoxDecoration(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .surfaceContainer,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8)),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(8.0),
                                                          child: SizedBox(
                                                              width: 12,
                                                              height: 12,
                                                              child:
                                                                  CircularProgressIndicator()),
                                                        )),
                                                  ),
                                                )
                                            ],
                                          )
                                        : widget.video != null
                                            ? dismissing || widget.closing
                                                ? widget.thumbnail != null
                                                    ? Image(
                                                        fit: BoxFit.cover,
                                                        image:
                                                            widget.thumbnail!,
                                                      )
                                                    : Container(
                                                        color: Colors.black,
                                                      )
                                                : VideoPlayer(
                                                    widget.video!,
                                                    controller:
                                                        widget.videoController,
                                                    showProgressBar: true,
                                                    onSave: () =>
                                                        LightboxMenu.saveVideo(
                                                            context,
                                                            widget.video!,
                                                            fileName: widget
                                                                .fileName),
                                                    // Vommet issue 1080: in
                                                    // full screen too.
                                                    onPictureInPicture:
                                                        pictureInPicture,
                                                    // Vommet issue 756.
                                                    canGoFullscreen:
                                                        LightboxSystemBars
                                                                .supported() &&
                                                            fullScreenApplies,
                                                    isFullscreen: fullScreen,
                                                    onFullscreen: fullScreen
                                                        ? LightboxFullScreen
                                                            .exit
                                                        : LightboxFullScreen
                                                            .enter,
                                                    thumbnail: widget.thumbnail,
                                                    key: widget.contentKey,
                                                  )
                                            : const Placeholder())),
                          ),
                        ),
                      ),
                    )),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vommet issue 701: an up or down swipe on the picture or video closes the
/// viewer (phones and tablets; a mouse drag doesn't). Like the gallery's
/// page swipe, it steps aside when a second finger lands first, so a pinch
/// still zooms.
class _SwipeToCloseRecognizer extends VerticalDragGestureRecognizer {
  _SwipeToCloseRecognizer()
      : super(supportedDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
        });

  /// False while zoomed in, so a drag pans the picture instead.
  bool Function() canSwipe = () => true;

  int _fingers = 0;
  bool _swiping = false;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      canSwipe() && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_fingers > 0 && !_swiping) {
      // A second finger: this is a pinch, not a swipe.
      resolve(GestureDisposition.rejected);
      return;
    }
    _fingers++;
    super.addAllowedPointer(event);
  }

  @override
  void acceptGesture(int pointer) {
    _swiping = true;
    super.acceptGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _fingers = 0;
    _swiping = false;
    super.didStopTrackingLastPointer(pointer);
  }
}
