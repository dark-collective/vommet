import 'dart:async';

import 'package:commet/cache/file_provider.dart';
// Vommet: auto-download (Vommet issue 75).
import 'package:commet/ui/atoms/auto_download_overlay.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox_full_screen.dart';
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/molecules/video_player/video_player.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:commet/utils/image/lod_image.dart';
// Vommet: the viewer's Copy / Save as / Share menu (Vommet issues 480, 766).
import 'package:commet/ui/atoms/lightbox_menu.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/popup_dialog.dart';
import 'package:commet/ui/atoms/lightbox_zoom.dart';
import 'dart:ui' as ui;

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
    this.onJumpToMessage,
    this.onForward,
    this.onPictureInPicture,
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

  /// Vommet issue 771: adds Jump to message to the menu (opened from the
  /// Media tab). Whoever opened the viewer closes it.
  final VoidCallback? onJumpToMessage;

  /// Vommet issue 802: adds Forward to the menu. Whoever opened the viewer
  /// closes it.
  final VoidCallback? onForward;

  /// Vommet: a video can go on in the picture-in-picture window (menu item
  /// and player button). Whoever opened the viewer closes it.
  final VoidCallback? onPictureInPicture;

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
    VoidCallback? onPictureInPicture,
    Key? key,
  }) {
    // Vommet experiment: browse the room's pictures and videos.
    if (customWidget == null && preferences.experimentLightboxGallery.value) {
      final gallery = LightboxGallery.showIfInTimeline(context,
          image: image,
          video: video,
          videoController: videoController,
          onPictureInPicture: onPictureInPicture,
          key: key);
      if (gallery != null) return gallery;
    }

    return showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: "LIGHTBOX",
        barrierColor: PopupDialog.barrierColor,
        pageBuilder: (context, _, __) {
          return LightboxFullScreenScope(
              child: Lightbox(
            image: image,
            video: video,
            videoController: videoController,
            aspectRatio: aspectRatio,
            thumbnail: thumbnail,
            contentKey: key,
            customWidget: customWidget,
            fileName: fileName,
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
            onPictureInPicture: onPictureInPicture == null || video == null
                ? null
                : () {
                    // The viewer's future completes on the pop; the caller
                    // opens the window then, once the player is free.
                    onPictureInPicture();
                    Navigator.of(context).pop();
                  },
            key: GlobalKey(),
          ));
        },
        transitionDuration: const Duration(milliseconds: 300),
        transitionBuilder: (context, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween(begin: const Offset(0, 1), end: const Offset(0, 0))
                      .animate(CurvedAnimation(
                          parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ));
  }
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
  /// it. Full screen (desktop) has its own way out.
  bool get canSwipeToClose =>
      (widget.image != null || widget.video != null) &&
      widget.customWidget == null &&
      !dismissing &&
      !widget.closing &&
      !fullScreen &&
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
          onPictureInPicture: widget.onPictureInPicture);

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
          padding: fullScreen
              ? EdgeInsets.zero
              : const EdgeInsets.all(BuildConfig.MOBILE ? 10 : 100.0),
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
                                                    onPictureInPicture: fullScreen
                                                        ? null
                                                        : widget
                                                            .onPictureInPicture,
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
