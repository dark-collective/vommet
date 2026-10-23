import 'dart:async';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/atoms/media_spoiler_cover.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/atoms/popup_dialog.dart';

/// Vommet experiment: makes the room's loaded pictures and videos browsable
/// from the image viewer. Placed around a room timeline; [Lightbox.show]
/// called below it opens a gallery when the shown media is one of the
/// timeline's attachments. Anything else (banners, avatars, link previews)
/// isn't in the list and opens on its own as before.
class LightboxGalleryScope extends InheritedWidget {
  const LightboxGalleryScope(
      {required this.timeline,
      this.newestFirst = false,
      required super.child,
      super.key});

  final Timeline timeline;

  /// The media below is laid out newest first (the member panel's Media
  /// tab), so the gallery runs the same way: older pictures to the right.
  final bool newestFirst;

  static LightboxGalleryScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LightboxGalleryScope>();

  @override
  bool updateShouldNotify(LightboxGalleryScope oldWidget) =>
      oldWidget.timeline != timeline || oldWidget.newestFirst != newestFirst;
}

/// One picture or video in the gallery.
class LightboxGalleryItem {
  LightboxGalleryItem(this.event, this.attachment, this.index);

  final TimelineEvent event;
  final Attachment attachment;

  /// Position among the event's attachments.
  final int index;

  String get key => "${event.eventId}/$index";

  bool shows({ImageProvider? image, FileProvider? video}) =>
      switch (attachment) {
        ImageAttachment a =>
          image != null && (identical(a.image, image) || a.image == image),
        VideoAttachment a =>
          video != null && (identical(a.file, video) || a.file == video),
        _ => false,
      };

  /// The timeline's pictures and videos, oldest first.
  static List<LightboxGalleryItem> fromTimeline(Timeline timeline) =>
      fromEvents(timeline.events);

  /// [newestFirst] in the timeline's own order.
  static List<LightboxGalleryItem> fromEvents(List<TimelineEvent> newestFirst) {
    final items = <LightboxGalleryItem>[];
    for (final event in newestFirst.reversed) {
      if (event is! TimelineEventMessage) continue;
      final attachments = event.attachments;
      if (attachments == null) continue;
      for (var i = 0; i < attachments.length; i++) {
        final attachment = attachments[i];
        if (attachment is ImageAttachment || attachment is VideoAttachment) {
          items.add(LightboxGalleryItem(event, attachment, i));
        }
      }
    }
    return items;
  }
}

class LightboxGallery extends StatefulWidget {
  const LightboxGallery({
    required this.timeline,
    required this.initialKey,
    this.initialVideoController,
    this.initialContentKey,
    this.newestFirst = false,
    super.key,
  });

  final Timeline timeline;

  /// [LightboxGalleryItem.key] of the item that was opened.
  final String initialKey;

  /// The opened video's own controller and player key, so a video that was
  /// playing in the timeline carries on in the viewer.
  final VideoPlayerController? initialVideoController;
  final Key? initialContentKey;

  /// Shows newer items to the left, like the Media tab's grid.
  final bool newestFirst;

  /// Opens the gallery if [image] or [video] is one of the loaded
  /// attachments of the timeline around [context]. Returns null otherwise.
  static Future<void>? showIfInTimeline(
    BuildContext context, {
    ImageProvider? image,
    FileProvider? video,
    VideoPlayerController? videoController,
    Key? key,
  }) {
    final scope = LightboxGalleryScope.maybeOf(context);
    if (scope == null) return null;
    final timeline = scope.timeline;

    final items = LightboxGalleryItem.fromTimeline(timeline);
    final index =
        items.indexWhere((item) => item.shows(image: image, video: video));
    if (index == -1) return null;

    return showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: "LIGHTBOX",
        barrierColor: PopupDialog.barrierColor,
        pageBuilder: (context, _, __) => LightboxGallery(
              timeline: timeline,
              initialKey: items[index].key,
              initialVideoController: videoController,
              initialContentKey: key,
              newestFirst: scope.newestFirst,
            ),
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

  @override
  State<LightboxGallery> createState() => _LightboxGalleryState();
}

class _LightboxGalleryState extends State<LightboxGallery> {
  late List<LightboxGalleryItem> items;
  late int current;
  late PageController pages;
  final Map<String, VideoPlayerController> videoControllers = {};
  final List<StreamSubscription> subscriptions = [];

  bool zoomed = false;

  /// The user's swipe between pages (see [_PageSwipeRecognizer]); the
  /// PageView's own drag is off so a pinch never turns the page.
  ScrollHoldController? swipeHold;
  Drag? swipe;

  /// Vommet issue 629: the thumbnail strip along the bottom.
  final ScrollController strip = ScrollController();
  bool stripDragged = false;
  double stripWheel = 0;

  bool closing = false;
  bool loadingOlder = false;
  bool showControls = false;
  Timer? hideControls;

  @override
  void initState() {
    super.initState();
    items = LightboxGalleryItem.fromTimeline(widget.timeline);
    current = items.indexWhere((item) => item.key == widget.initialKey);
    if (current == -1) current = 0;
    if (widget.initialVideoController != null) {
      videoControllers[widget.initialKey] = widget.initialVideoController!;
    }
    pages = PageController(initialPage: current);
    strip.addListener(onStripScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => centerStrip());

    final timeline = widget.timeline;
    for (final stream in [
      timeline.onEventAdded.stream,
      timeline.onChange.stream,
      timeline.onRemove.stream,
    ]) {
      subscriptions.add(stream.listen((_) => scheduleRefresh()));
    }

    if (current <= 1) loadOlder();
  }

  @override
  void dispose() {
    for (final sub in subscriptions) {
      sub.cancel();
    }
    hideControls?.cancel();
    pages.dispose();
    strip.dispose();
    super.dispose();
  }

  bool refreshScheduled = false;

  // Timeline streams fire while the timeline is being changed; rebuild the
  // list once it settles.
  void scheduleRefresh() {
    if (refreshScheduled) return;
    refreshScheduled = true;
    Future.microtask(() {
      refreshScheduled = false;
      if (mounted) refresh();
    });
  }

  /// Rebuilds the list from the timeline, staying on the same item (older
  /// items loading in front of it shift its index).
  void refresh() {
    final shownKey = items.isEmpty ? null : items[current].key;
    final updated = LightboxGalleryItem.fromTimeline(widget.timeline);
    if (updated.isEmpty) {
      close();
      return;
    }

    var index = updated.indexWhere((item) => item.key == shownKey);
    if (index == -1) index = current.clamp(0, updated.length - 1);

    // Older items loading in front shift every page along. The page view
    // keeps its scroll offset in pixels, so moving to the new index only
    // after the frame (as before) showed whichever picture now sat at the
    // old index for a frame: the viewer flickered through other pictures
    // on each batch while the room loaded. Move the offset by the same
    // number of pages before this rebuild, so the frame lays out the new
    // list already on the shown picture. correctBy also keeps a swipe in
    // progress going.
    final shift = index - current;
    if (shift != 0 && pages.hasClients) {
      final position = pages.position;
      if (position.hasPixels && position.hasViewportDimension) {
        position.correctBy(shift * position.viewportDimension);
      }
    }

    final animatingTo = animatingToKey == null
        ? -1
        : updated.indexWhere((item) => item.key == animatingToKey);

    setState(() {
      items = updated;
      current = index;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Older items loading in front move the shown one along the strip too.
      if (shift != 0 && !stripDragged) centerStrip();
      if (!pages.hasClients) return;
      // An arrow-key move in flight aims at a pixel offset; aim it at its
      // picture's new place.
      if (shift != 0 && animatingTo != -1) {
        animateTo(animatingTo);
        return;
      }
      if (pages.position.isScrollingNotifier.value) return;
      if (pages.page?.round() != current) pages.jumpToPage(current);
    });
  }

  Future<void> loadOlder() async {
    if (loadingOlder || !widget.timeline.canLoadHistory) return;
    setState(() => loadingOlder = true);
    try {
      await widget.timeline.loadMoreHistory();
    } finally {
      if (mounted) {
        setState(() => loadingOlder = false);
        refresh();
      }
    }
  }

  void go(int delta) {
    final target = current + delta;
    if (target < 0) {
      loadOlder();
      return;
    }
    if (target >= items.length) return;
    animateTo(target);
  }

  /// [LightboxGalleryItem.key] of the page an arrow-key move is heading to.
  String? animatingToKey;
  int animation = 0;

  void animateTo(int index) {
    animatingToKey = items[index].key;
    final mine = ++animation;
    pages
        .animateToPage(index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic)
        .whenComplete(() {
      if (animation == mine) animatingToKey = null;
    });
  }

  void onPageChanged(int index) {
    setState(() {
      current = index;
      zoomed = false;
    });

    // A video keeps playing on a page that is only scrolled away.
    final shownKey = items[index].key;
    for (final entry in videoControllers.entries) {
      if (entry.key != shownKey) entry.value.pause();
    }

    if (index <= 1) loadOlder();
    if (!stripDragged) centerStrip(animate: true);
  }

  /// Shows the item at [index], from the strip: the next or previous one
  /// slides across; a jump further only builds the page it lands on.
  void showItem(int index) {
    if (index < 0 || index >= items.length || index == current) return;
    if ((index - current).abs() == 1) {
      animateTo(index);
    } else {
      pages.jumpToPage(index);
    }
  }

  static const double stripThumbnail = 56;
  static const double stripItemExtent = stripThumbnail + 8;
  static const double stripHeight = stripThumbnail + 20;

  /// Scrolls the strip so the shown item sits in its middle.
  void centerStrip({bool animate = false}) {
    if (!strip.hasClients) return;
    final position = strip.position;
    final target = (current * stripItemExtent -
            (position.viewportDimension - stripItemExtent) / 2)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (animate) {
      strip.animateTo(target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    } else {
      strip.jumpTo(target);
    }
  }

  /// The strip scrolled to its oldest end loads older history, so it keeps
  /// going (the room's Media tab does the same).
  void onStripScroll() {
    if (!strip.hasClients) return;
    if (strip.position.pixels < stripItemExtent * 3) loadOlder();
  }

  /// A drag on the strip (phones) moves the shown item to the one left in
  /// the strip's middle once the strip stops.
  bool onStripNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      stripDragged = true;
    } else if (notification is ScrollEndNotification && stripDragged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !strip.hasClients) return;
        // A fling still running ends with another notification.
        if (strip.position.isScrollingNotifier.value) return;
        stripDragged = false;
        final position = strip.position;
        final middle = ((position.pixels +
                    (position.viewportDimension - stripItemExtent) / 2) /
                stripItemExtent)
            .round()
            .clamp(0, items.length - 1);
        if (middle == current) {
          centerStrip(animate: true);
        } else {
          showItem(middle);
        }
      });
    }
    return false;
  }

  /// The mouse wheel over the strip moves to the next or previous item
  /// (over the picture it still zooms): down = the item to the right.
  void onStripWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0) return;
      if (stripWheel.sign != dy.sign) stripWheel = 0;
      stripWheel += dy;
      // A mouse notch is one item; a trackpad's small deltas add up.
      if (stripWheel.abs() < 50) return;
      final right = widget.newestFirst ? -1 : 1;
      go(stripWheel > 0 ? right : -right);
      stripWheel = 0;
    });
  }

  Widget buildStrip(BuildContext context) {
    return Listener(
      onPointerSignal: onStripWheel,
      child: ColoredBox(
        color: Colors.black54,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: stripHeight,
            child: NotificationListener<ScrollNotification>(
              onNotification: onStripNotification,
              child: ListView.builder(
                key: const ValueKey("lightbox-gallery-strip"),
                controller: strip,
                scrollDirection: Axis.horizontal,
                // Newer to the left when the gallery mirrors a newest-first
                // grid, as the pages do.
                reverse: widget.newestFirst,
                itemExtent: stripItemExtent,
                itemCount: items.length,
                itemBuilder: buildStripItem,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildStripItem(BuildContext context, int index) {
    final item = items[index];
    final attachment = item.attachment;
    final video = attachment is VideoAttachment ? attachment : null;
    final preview =
        attachment is ImageAttachment ? attachment.image : video?.thumbnail;
    final spoiler = attachment is FileAttachment ? attachment.spoiler : null;
    final shown = index == current;
    return Center(
      child: GestureDetector(
        key: ValueKey("lightbox-gallery-strip-${item.key}"),
        onTap: () => showItem(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: shown ? stripThumbnail : stripThumbnail - 8,
          height: shown ? stripThumbnail : stripThumbnail - 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                width: 2,
                color: shown
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Opacity(
              opacity: shown ? 1 : 0.7,
              child: Stack(fit: StackFit.expand, children: [
                const ColoredBox(color: Colors.white10),
                MediaSpoilerBuilder(
                  spoiler: spoiler,
                  builder: (context, hidden) => hidden
                      ? const Icon(Icons.visibility_off,
                          size: 18, color: Colors.white70)
                      : preview == null
                          ? const SizedBox.shrink()
                          : Image(
                              image: preview,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                ),
                if (video != null)
                  const Center(
                    child: Icon(Icons.play_arrow,
                        size: 22,
                        color: Colors.white,
                        shadows: [
                          BoxShadow(blurRadius: 6, color: Colors.black54)
                        ]),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void close() {
    if (closing) return;
    // Pages swap a playing video for its thumbnail first, so the player can
    // move back into the timeline without two copies of it.
    setState(() => closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void onHover() {
    hideControls?.cancel();
    if (!showControls) setState(() => showControls = true);
    hideControls = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => showControls = false);
    });
  }

  Widget buildPage(BuildContext context, int index) {
    final item = items[index];
    // Vommet: a spoiler not revealed yet stays covered here too (MSC4193);
    // swiping onto it loads nothing until it is tapped.
    final spoiler = switch (item.attachment) {
      FileAttachment a => a.spoiler,
      _ => null,
    };
    if (spoiler != null) {
      final attachment = item.attachment;
      return MediaSpoilerBuilder(
        key: ValueKey(item.key),
        spoiler: spoiler,
        builder: (context, hidden) => hidden
            ? MediaSpoilerViewerCover(
                spoiler: spoiler,
                onClose: close,
                isVideo: attachment is VideoAttachment,
                blurhash: spoilerBlurhashOf(switch (attachment) {
                  ImageAttachment a => a.image,
                  VideoAttachment v => v.thumbnail,
                  _ => null,
                }),
                aspectRatio: switch (attachment) {
                  ImageAttachment a => a.aspectRatio,
                  VideoAttachment v => v.aspectRatio,
                  _ => null,
                },
              )
            : buildMediaPage(context, index, item),
      );
    }
    return buildMediaPage(context, index, item);
  }

  Widget buildMediaPage(
      BuildContext context, int index, LightboxGalleryItem item) {
    final isInitial = item.key == widget.initialKey;
    void onZoom(bool value) {
      if (index == current && value != zoomed) {
        setState(() => zoomed = value);
      }
    }

    final attachment = item.attachment;
    if (attachment is VideoAttachment) {
      return Lightbox(
        key: ValueKey(item.key),
        video: attachment.file,
        thumbnail: attachment.thumbnail,
        aspectRatio: attachment.aspectRatio,
        videoController: videoControllers.putIfAbsent(
            item.key, () => VideoPlayerController()),
        contentKey: isInitial ? widget.initialContentKey : null,
        closing: closing,
        onZoomChanged: onZoom,
      );
    }

    final image = attachment as ImageAttachment;
    return Lightbox(
      key: ValueKey(item.key),
      image: image.image,
      fileName: image.name,
      closing: closing,
      onZoomChanged: onZoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.of(context).desktop;
    final item = items.isEmpty ? null : items[current];
    final sender = item == null
        ? null
        : widget.timeline.room
            .getMemberOrFallback(item.event.senderId)
            .displayName;

    // Items stay oldest first; going right means newer, or older when the
    // gallery mirrors a newest-first grid.
    final right = widget.newestFirst ? -1 : 1;
    final canGoOlder = current > 0 || widget.timeline.canLoadHistory;
    final canGoNewer = current < items.length - 1;

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.arrowLeft): () => go(-right),
        SingleActivator(LogicalKeyboardKey.arrowRight): () => go(right),
        const SingleActivator(LogicalKeyboardKey.escape): close,
      },
      child: Focus(
        autofocus: true,
        child: MouseRegion(
          onHover: (_) => onHover(),
          child: Column(children: [
            Expanded(
                child: Stack(
              children: [
                RawGestureDetector(
                    gestures: {
                      _PageSwipeRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                              _PageSwipeRecognizer>(
                        _PageSwipeRecognizer.new,
                        (recognizer) => recognizer
                          ..canSwipe = (() => !zoomed && pages.hasClients)
                          ..gestureSettings =
                              MediaQuery.maybeGestureSettingsOf(context)
                          ..onDown = ((_) {
                            swipeHold =
                                pages.position.hold(() => swipeHold = null);
                          })
                          ..onStart = ((details) {
                            swipe = pages.position
                                .drag(details, () => swipe = null);
                          })
                          ..onUpdate = ((details) => swipe?.update(details))
                          ..onEnd = ((details) => swipe?.end(details))
                          ..onCancel = () {
                            swipeHold?.cancel();
                            swipe?.cancel();
                          },
                      ),
                    },
                    child: PageView.builder(
                      controller: pages,
                      reverse: widget.newestFirst,
                      // Builds the pages either side too, so they load ahead.
                      allowImplicitScrolling: true,
                      // Swipes come from the RawGestureDetector above; PageView
                      // still snaps to pages when they end.
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: onPageChanged,
                      itemCount: items.length,
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey<String>) return null;
                        final index =
                            items.indexWhere((i) => i.key == key.value);
                        return index == -1 ? null : index;
                      },
                      itemBuilder: buildPage,
                    )),
                if (item != null)
                  Align(
                    alignment: Alignment.topCenter,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              // The viewer is a bare overlay with no Material
                              // above it, so the style must be complete: an
                              // inherited one falls back to Flutter's
                              // big yellow-underlined debug text.
                              child: Text(
                                "${widget.newestFirst ? items.length - current : current + 1}"
                                " / ${items.length}"
                                "${sender == null ? "" : " · $sender"}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    (Theme.of(context).textTheme.labelSmall ??
                                            const TextStyle(fontSize: 11))
                                        .copyWith(
                                            inherit: false,
                                            color: Colors.white70,
                                            decoration: TextDecoration.none),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (desktop) ...[
                  edgeArrow(
                      Alignment.centerLeft,
                      Icons.chevron_left,
                      (right == 1 ? canGoOlder : canGoNewer)
                          ? () => go(-right)
                          : null),
                  edgeArrow(
                      Alignment.centerRight,
                      Icons.chevron_right,
                      (right == 1 ? canGoNewer : canGoOlder)
                          ? () => go(right)
                          : null),
                ],
              ],
            )),
            // Vommet issue 629: the strip sits below the picture, so it never
            // covers it or a video's controls.
            if (items.length > 1 || widget.timeline.canLoadHistory)
              buildStrip(context),
          ]),
        ),
      ),
    );
  }

  Widget edgeArrow(
      Alignment alignment, IconData icon, VoidCallback? onPressed) {
    return Align(
      alignment: alignment,
      child: AnimatedOpacity(
        opacity: showControls && onPressed != null ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: IgnorePointer(
          ignoring: !showControls || onPressed == null,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: IconButton.filledTonal(
              iconSize: 32,
              onPressed: onPressed,
              icon: Icon(icon),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vommet: a sideways swipe to the next or previous page that gives way to
/// a pinch. When a second finger touches before the swipe has started (or a
/// trackpad gesture starts scaling), it steps aside so the picture zooms;
/// a plain drag would often win that race and turn the page instead.
class _PageSwipeRecognizer extends HorizontalDragGestureRecognizer {
  _PageSwipeRecognizer()
      : super(supportedDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        });

  /// False while the picture is zoomed in, so a drag pans it instead.
  bool Function() canSwipe = () => true;

  int _fingers = 0;
  bool _swiping = false;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      canSwipe() && super.isPointerAllowed(event);

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) =>
      canSwipe() && super.isPointerPanZoomAllowed(event);

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
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomUpdateEvent &&
        !_swiping &&
        (event.scale - 1).abs() > 0.02) {
      resolve(GestureDisposition.rejected);
      return;
    }
    super.handleEvent(event);
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
