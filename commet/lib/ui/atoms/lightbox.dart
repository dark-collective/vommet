import 'dart:async';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/molecules/video_player/video_player.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:commet/utils/image_clipboard.dart';
import 'package:commet/utils/image_save.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/popup_dialog.dart';
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
    Key? key,
  }) {
    // Vommet experiment: browse the room's pictures and videos.
    if (customWidget == null && preferences.experimentLightboxGallery.value) {
      final gallery = LightboxGallery.showIfInTimeline(context,
          image: image,
          video: video,
          videoController: videoController,
          key: key);
      if (gallery != null) return gallery;
    }

    return showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: "LIGHTBOX",
        barrierColor: PopupDialog.barrierColor,
        pageBuilder: (context, _, __) {
          return Lightbox(
            image: image,
            video: video,
            videoController: videoController,
            aspectRatio: aspectRatio,
            thumbnail: thumbnail,
            contentKey: key,
            customWidget: customWidget,
            fileName: fileName,
            key: GlobalKey(),
          );
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

class _LightboxState extends State<Lightbox> with TickerProviderStateMixin {
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

  @override
  void dispose() {
    onLodChanged?.cancel();
    // Vommet: the viewer's decode can be large; don't keep it cached.
    if (!identical(image, widget.image)) image?.evict();
    super.dispose();
  }

  bool zoomed = false;

  void onTransformChanged() {
    final value = controller.value.getMaxScaleOnAxis() > 1.01;
    if (value == zoomed) return;
    zoomed = value;
    widget.onZoomChanged?.call(value);
  }

  @override
  void initState() {
    super.initState();
    if (widget.onZoomChanged != null) {
      controller.addListener(onTransformChanged);
    }

    _controller.stop(canceled: true);

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

  Future<void> showImageMenu(Offset position) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        if (ImageClipboard.supported)
          PopupMenuItem(
            value: "copy",
            child: Row(spacing: 12, children: [
              const Icon(Icons.copy, size: 20),
              Text(CommonStrings.promptCopyImage),
            ]),
          ),
        PopupMenuItem(
          value: "save",
          child: Row(spacing: 12, children: [
            const Icon(Icons.save_alt, size: 20),
            Text(CommonStrings.promptSaveAs),
          ]),
        ),
      ],
    );
    if (choice == "copy" && widget.image != null) {
      await ImageClipboard.copy(widget.image!);
    }
    if (choice == "save" && widget.image != null) {
      await ImageSave.saveAs(widget.image!, fileName: widget.fileName);
    }
  }

  void dismiss() {
    setState(() {
      dismissing = true;
    });
    Navigator.pop(context, widget.contentKey);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        dismiss();
      },
      child: Container(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(BuildConfig.MOBILE ? 10 : 100.0),
          child: ScaledSafeArea(
            child: RotatedBox(
              quarterTurns: rotate ? 1 : 0,
              child: ScaleTransition(
                scale: rotate ? scaleAnimation : scale,
                child: RotationTransition(
                  turns: rotate ? rotationAnimation : rotation,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: InteractiveViewer(
                      trackpadScrollCausesScale: true,
                      transformationController: controller,
                      maxScale: 3.5,
                      child: Container(
                        alignment: Alignment.center,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: GestureDetector(
                            onTap: () {},
                            // Vommet: right-click (long-press on phones) the
                            // image for Save as.
                            onSecondaryTapUp: widget.image == null
                                ? null
                                : (d) => showImageMenu(d.globalPosition),
                            onLongPressStart: widget.image == null
                                ? null
                                : (d) => showImageMenu(d.globalPosition),
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
                                                    canGoFullscreen: false,
                                                    thumbnail: widget.thumbnail,
                                                    key: widget.contentKey,
                                                  )
                                            : const Placeholder())),
                          ),
                        ),
                      ),
                    ),
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
