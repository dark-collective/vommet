import 'package:commet/ui/atoms/clickable_gesture_detector.dart';
import 'dart:async';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/atoms/lightbox_full_screen.dart';
import 'package:commet/ui/atoms/lightbox_menu.dart';
import 'package:commet/ui/atoms/media_spoiler_cover.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:commet/ui/organisms/chat/reply_from_viewer.dart';
import 'package:commet/ui/organisms/forward_message/forward_from_viewer.dart';
import 'package:commet/ui/organisms/room_members_list/media_grid_zoom.dart';
import 'package:commet/utils/media_spoiler.dart';
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
  LightboxGalleryScope(
      {required Timeline timeline,
      this.newestFirst = false,
      this.onJumpToEvent,
      required super.child,
      super.key})
      : source = TimelineGallerySource(timeline);

  /// Vommet: a gallery over [source]'s list instead of the timeline's (the
  /// Media tab's, which also holds pictures paged from the server's
  /// filtered history that the timeline never loaded).
  const LightboxGalleryScope.source(
      {required this.source,
      this.newestFirst = false,
      this.onJumpToEvent,
      required super.child,
      super.key});

  final LightboxGallerySource source;

  /// The media below is laid out newest first (the member panel's Media
  /// tab), so the gallery runs the same way: older pictures to the right.
  final bool newestFirst;

  /// Vommet issue 771: the viewer's menu offers Jump to message for the
  /// picture or video on screen (the Media tab sets this; in the chat the
  /// message is already there).
  final void Function(String eventId)? onJumpToEvent;

  static LightboxGalleryScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LightboxGalleryScope>();

  @override
  bool updateShouldNotify(LightboxGalleryScope oldWidget) =>
      oldWidget.source != source ||
      oldWidget.newestFirst != newestFirst ||
      oldWidget.onJumpToEvent != onJumpToEvent;
}

/// Vommet: where a gallery's pictures and videos come from, and how it
/// loads older ones when it nears the oldest.
abstract class LightboxGallerySource {
  /// The room, for the senders' names.
  Room get room;

  /// The pictures and videos, oldest first.
  List<LightboxGalleryItem> get items;

  /// Whether [loadOlder] can still find older ones.
  bool get canLoadOlder;

  /// Loads older history; [items] may grow at the oldest end.
  Future<void> loadOlder();

  /// Calls [onChange] whenever [items] may have changed (possibly while
  /// the list is still changing). Returns a function that stops it.
  void Function() listen(void Function() onChange);
}

/// The room timeline's loaded pictures and videos (the chat's gallery).
class TimelineGallerySource implements LightboxGallerySource {
  TimelineGallerySource(this.timeline);

  final Timeline timeline;

  @override
  Room get room => timeline.room;

  @override
  List<LightboxGalleryItem> get items =>
      LightboxGalleryItem.fromTimeline(timeline);

  @override
  bool get canLoadOlder => timeline.canLoadHistory;

  @override
  Future<void> loadOlder() => timeline.loadMoreHistory();

  @override
  void Function() listen(void Function() onChange) {
    final subscriptions = [
      for (final stream in [
        timeline.onEventAdded.stream,
        timeline.onChange.stream,
        timeline.onRemove.stream,
      ])
        stream.listen((_) => onChange()),
    ];
    return () {
      for (final sub in subscriptions) {
        sub.cancel();
      }
    };
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineGallerySource && identical(other.timeline, timeline);

  @override
  int get hashCode => identityHashCode(timeline);
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
    this.timeline,
    this.source,
    required this.initialKey,
    this.initialVideoController,
    this.initialContentKey,
    this.newestFirst = false,
    this.onJumpToEvent,
    this.initialOnPictureInPicture,
    super.key,
  }) : assert(timeline != null || source != null);

  /// The chat's gallery: the timeline's pictures and videos. Ignored when
  /// [source] is given.
  final Timeline? timeline;

  /// Vommet: where the pictures and videos come from instead of
  /// [timeline] (the Media tab's own list).
  final LightboxGallerySource? source;

  /// [LightboxGalleryItem.key] of the item that was opened.
  final String initialKey;

  /// The opened video's own controller and player key, so a video that was
  /// playing in the timeline carries on in the viewer.
  final VideoPlayerController? initialVideoController;
  final Key? initialContentKey;

  /// Shows newer items to the left, like the Media tab's grid.
  final bool newestFirst;

  /// See [LightboxGalleryScope.onJumpToEvent].
  final void Function(String eventId)? onJumpToEvent;

  /// Vommet: the opened video can go on in the picture-in-picture window
  /// (its own player only, so the other pages don't offer it).
  final VoidCallback? initialOnPictureInPicture;

  /// Opens the gallery if [image] or [video] is one of the loaded
  /// attachments of the gallery scope around [context] (the timeline, or
  /// the Media tab's list). Returns null otherwise.
  static Future<void>? showIfInTimeline(
    BuildContext context, {
    ImageProvider? image,
    FileProvider? video,
    VideoPlayerController? videoController,
    VoidCallback? onPictureInPicture,
    Key? key,
  }) {
    final scope = LightboxGalleryScope.maybeOf(context);
    if (scope == null) return null;
    final source = scope.source;

    final items = source.items;
    final index =
        items.indexWhere((item) => item.shows(image: image, video: video));
    if (index == -1) return null;

    return showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: "LIGHTBOX",
        barrierColor: PopupDialog.barrierColor,
        pageBuilder: (context, _, __) => LightboxGallery(
              source: source,
              initialKey: items[index].key,
              initialVideoController: videoController,
              initialContentKey: key,
              newestFirst: scope.newestFirst,
              onJumpToEvent: scope.onJumpToEvent,
              initialOnPictureInPicture: onPictureInPicture,
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

class _LightboxGalleryState extends State<LightboxGallery>
    with SingleTickerProviderStateMixin {
  late final LightboxGallerySource source =
      widget.source ?? TimelineGallerySource(widget.timeline!);
  late List<LightboxGalleryItem> items;
  late int current;
  void Function()? stopListening;
  late PageController pages;
  final Map<String, VideoPlayerController> videoControllers = {};
  final List<StreamSubscription> subscriptions = [];

  bool zoomed = false;

  /// Vommet issue 755: the system bars hide while zoomed in. The padding
  /// they left stays, so the picture doesn't jump when they go.
  EdgeInsets? unzoomedPadding;
  EdgeInsets? unzoomedViewPadding;

  /// Sets [zoomed] (in a setState) and hides or shows the system bars.
  void setZoomed(bool value) {
    zoomed = value;
    if (value) {
      LightboxSystemBars.hide(this);
    } else {
      LightboxSystemBars.show(this);
    }
  }

  /// The user's swipe between pages (see [_PageSwipeRecognizer]); the
  /// PageView's own drag is off so a pinch never turns the page.
  ScrollHoldController? swipeHold;
  Drag? swipe;

  /// Vommet issue 629: the thumbnail strip along the bottom.
  final ScrollController strip = ScrollController();
  bool stripDragged = false;

  /// Vommet issue 684: on phones, a swipe up on the strip turns it into a
  /// grid of the room's pictures and videos under the shown one.
  /// [gridOpen] is where it is going; [gridReveal] how far it is open
  /// (Vommet issue 753: 0 = the strip, 1 = the whole grid; a drag on the
  /// strip or the grid's handle moves it with the finger).
  bool gridOpen = false;
  late final AnimationController gridReveal;
  final ScrollController grid = ScrollController();
  int gridColumns = 1;
  double gridRowExtent = 0;

  /// How far a drag must go to open the grid all the way: its height less
  /// the strip's.
  double gridTravel = 1;

  bool closing = false;
  bool loadingOlder = false;
  bool showControls = false;
  Timer? hideControls;

  @override
  void initState() {
    super.initState();
    items = source.items;
    current = items.indexWhere((item) => item.key == widget.initialKey);
    if (current == -1) current = 0;
    if (widget.initialVideoController != null) {
      videoControllers[widget.initialKey] = widget.initialVideoController!;
    }
    pages = PageController(initialPage: current);
    strip.addListener(onStripScroll);
    grid.addListener(onGridScroll);
    gridReveal = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(onGridReveal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      centerStrip();
      fillStrip();
    });

    stopListening = source.listen(scheduleRefresh);
    // Vommet issue 754: a pinch on the grid (or in the Media tab) resizes
    // its thumbnails.
    subscriptions.add(preferences.mediaGridThumbnailSize.onChanged.listen((_) {
      if (mounted) setState(() {});
    }));

    if (current <= 1) loadOlder();
  }

  @override
  void dispose() {
    for (final sub in subscriptions) {
      sub.cancel();
    }
    stopListening?.call();
    hideControls?.cancel();
    LightboxSystemBars.show(this);
    // Vommet issue 662: however the gallery closes, the window comes back.
    LightboxFullScreen.exit();
    pages.dispose();
    strip.dispose();
    grid.dispose();
    gridReveal.dispose();
    super.dispose();
  }

  bool refreshScheduled = false;

  // Timeline streams fire while the timeline is being changed; rebuild the
  // list once it settles (the Media tab's list notifies the same way).
  void scheduleRefresh() {
    if (refreshScheduled) return;
    refreshScheduled = true;
    Future.microtask(() {
      refreshScheduled = false;
      if (mounted) refresh();
    });
  }

  /// Rebuilds the list from the source, staying on the same item (older
  /// items loading in front of it shift its index).
  void refresh() {
    final shownKey = items.isEmpty ? null : items[current].key;
    final updated = source.items;
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
    // Vommet issue 742: the strip keeps the thumbnails it shows, wherever
    // the wheel or a drag left it.
    if (shift != 0 && strip.hasClients) {
      final position = strip.position;
      if (position.hasPixels) position.correctBy(shift * stripItemExtent);
    }
    // The grid stays on the shown item's row the same way.
    if (shift != 0 && grid.hasClients && gridRowExtent > 0) {
      final position = grid.position;
      final rows = index ~/ gridColumns - current ~/ gridColumns;
      if (position.hasPixels && rows != 0) {
        position.correctBy(rows * gridRowExtent);
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
      // A centering move in flight aims at a pixel offset; aim it again.
      if (shift != 0 &&
          !stripDragged &&
          strip.hasClients &&
          strip.position.isScrollingNotifier.value) {
        centerStrip();
      }
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

  /// Vommet issue 700: batches in a row that [fillStrip] loaded without a
  /// new picture or video. A room with few of them stops there instead of
  /// paging through its whole history.
  int emptyFillBatches = 0;
  static const int maxEmptyFillBatches = 5;

  Future<void> loadOlder({bool fill = false}) async {
    if (loadingOlder || !source.canLoadOlder) return;
    if (!fill) emptyFillBatches = 0;
    final before = items.length;
    setState(() => loadingOlder = true);
    try {
      await source.loadOlder();
    } finally {
      if (mounted) {
        setState(() => loadingOlder = false);
        refresh();
        emptyFillBatches = items.length > before ? 0 : emptyFillBatches + 1;
        // After refresh's own post-frame move of the strip.
        WidgetsBinding.instance.addPostFrameCallback((_) => fillStrip());
      }
    }
  }

  /// Vommet issue 700: keeps loading older history while the strip's oldest
  /// end is still in view, so it fills on its own (the timeline fills its
  /// viewport the same way). [onStripScroll] only runs when the strip
  /// scrolls, and a strip narrower than its viewport never does.
  void fillStrip() {
    if (!mounted || !strip.hasClients) return;
    if (emptyFillBatches >= maxEmptyFillBatches) return;
    final position = strip.position;
    if (!position.hasPixels || !position.hasContentDimensions) return;
    if (position.pixels < stripItemExtent * 3) loadOlder(fill: true);
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
      setZoomed(false);
    });

    // A video keeps playing on a page that is only scrolled away.
    final shownKey = items[index].key;
    for (final entry in videoControllers.entries) {
      if (entry.key != shownKey) entry.value.pause();
    }

    if (index <= 1) loadOlder();
    if (!stripDragged) centerStrip(animate: true);
    revealInGrid(animate: true);
  }

  /// Catches up with a page change the page view didn't report.
  void reportSettledPage() {
    if (!mounted || !pages.hasClients) return;
    final page = pages.page?.round();
    if (page == null || page == current || page < 0 || page >= items.length) {
      return;
    }
    onPageChanged(page);
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

  /// A drag on the strip (a finger, or the mouse on desktop) only scrolls it
  /// (Vommet issue 742): a tap on a thumbnail is what shows another item.
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
      });
    }
    return false;
  }

  /// The mouse wheel over the strip scrolls it (over the picture it still
  /// zooms): down = towards the right. Vommet issue 742: the shown item
  /// stays put.
  void onStripWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0 || !strip.hasClients) return;
      final position = strip.position;
      final delta = widget.newestFirst ? -dy : dy;
      final target = (position.pixels + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (target != position.pixels) strip.jumpTo(target);
    });
  }

  static const double handleHeight = 20;
  static const double gridSpacing = 4;
  static const double gridPadding = 6;

  void setGridOpen(bool open) {
    gridOpen = open;
    settleGrid();
  }

  /// Eases the grid the rest of the way to [gridOpen].
  void settleGrid() {
    // Back closes the grid only while it is open (see build).
    setState(() {});
    final target = gridOpen ? 1.0 : 0.0;
    if (gridReveal.value == target) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      gridReveal.value = target;
      return;
    }
    final left = (target - gridReveal.value).abs();
    gridReveal.animateTo(target,
        duration: gridReveal.duration! * left.clamp(0.4, 1.0),
        curve: Curves.easeOutCubic);
  }

  double lastGridReveal = 0;

  void onGridReveal() {
    final value = gridReveal.value;
    final was = lastGridReveal;
    lastGridReveal = value;
    // The grid comes in (or the strip comes back): place it after layout.
    if ((was == 0) != (value == 0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (gridReveal.value > 0) {
          revealInGrid(center: true);
          onGridScroll();
        } else {
          centerStrip();
        }
      });
    }
    setState(() {});
  }

  bool gridDragging = false;

  /// A drag on the strip or the grid's handle: the grid follows the finger,
  /// up opens it, down closes it.
  void onGridDragStart(DragStartDetails details) {
    gridDragging = true;
    gridReveal.stop();
  }

  void onGridDragUpdate(DragUpdateDetails details) {
    gridReveal.value -= details.delta.dy / gridTravel;
  }

  /// Let go, a flick goes its way; a slow drag settles on the nearer end.
  void onGridDragEnd(DragEndDetails details) {
    gridDragging = false;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() > 300) {
      gridOpen = velocity < 0;
    } else {
      gridOpen = gridReveal.value >= 0.5;
    }
    settleGrid();
  }

  /// Also called for a tap that never became a drag: that leaves the grid
  /// to the tap.
  void onGridDragCancel() {
    if (!gridDragging) return;
    gridDragging = false;
    gridOpen = gridReveal.value >= 0.5;
    settleGrid();
  }

  /// Scrolls the grid to the shown item's row, if it isn't in view already
  /// (or to the middle, when the grid opens).
  void revealInGrid({bool animate = false, bool center = false}) {
    if (!grid.hasClients || gridRowExtent <= 0) return;
    final position = grid.position;
    if (!position.hasPixels || !position.hasViewportDimension) return;
    final rowTop = (current ~/ gridColumns) * gridRowExtent;
    final viewport = position.viewportDimension;
    final double target;
    if (center) {
      target = rowTop - (viewport - gridRowExtent) / 2;
    } else if (rowTop < position.pixels) {
      target = rowTop;
    } else if (rowTop + gridRowExtent > position.pixels + viewport) {
      target = rowTop + gridRowExtent - viewport;
    } else {
      return;
    }
    final clamped =
        target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (animate) {
      grid.animateTo(clamped,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    } else {
      grid.jumpTo(clamped);
    }
  }

  /// The grid scrolled up to its oldest row loads older history, like the
  /// strip.
  void onGridScroll() {
    if (!grid.hasClients || !grid.position.hasPixels) return;
    if (grid.position.pixels < gridRowExtent * 2) loadOlder();
  }

  /// The grid's height: the room the shown picture leaves under itself at
  /// full width, so the grid never covers it, but at least three rows (the
  /// picture shrinks for those) and at most most of the viewer.
  double gridHeightFor(Size size, EdgeInsets padding) {
    final width = size.width - gridPadding * 2;
    gridColumns = (width / (MediaGridZoom.size + gridSpacing)).ceil();
    if (gridColumns < 1) gridColumns = 1;
    gridRowExtent =
        (width - gridSpacing * (gridColumns - 1)) / gridColumns + gridSpacing;
    final chrome = handleHeight + gridPadding + padding.bottom;
    final least = chrome + gridRowExtent * 3;
    final item = items.isEmpty ? null : items[current];
    final aspect = switch (item?.attachment) {
      ImageAttachment a => a.aspectRatio,
      VideoAttachment v => v.aspectRatio,
      _ => 1.0,
    };
    // Space above the picture for the counter.
    final above = padding.top + 36;
    final picture = aspect > 0 ? size.width / aspect : size.width;
    final room = size.height - above - picture;
    return (room > least ? room : least).clamp(0, size.height * 0.7).toDouble();
  }

  Widget buildHandle({required bool open}) {
    return GestureDetector(
      key: ValueKey(open
          ? "lightbox-gallery-grid-handle"
          : "lightbox-gallery-strip-handle"),
      behavior: HitTestBehavior.opaque,
      onTap: () => setGridOpen(!open),
      child: SizedBox(
        height: handleHeight,
        width: double.infinity,
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      ),
    );
  }

  Widget buildGrid(BuildContext context, double height) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      key: const ValueKey("lightbox-gallery-grid"),
      color: Colors.black87,
      child: SizedBox(
        height: height,
        child: Column(children: [
          buildHandle(open: true),
          Expanded(
            child: MediaGridZoomDetector(
              controller: grid,
              padding: gridPadding,
              child: GridView.builder(
                key: const ValueKey("lightbox-gallery-grid-view"),
                controller: grid,
                physics: const NoWheelWhileCtrlScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                    gridPadding, 0, gridPadding, gridPadding + bottom),
                // Older above, newer below, whichever way the strip runs.
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: gridColumns,
                    mainAxisSpacing: gridSpacing,
                    crossAxisSpacing: gridSpacing),
                itemCount: items.length,
                itemBuilder: buildGridItem,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget buildGridItem(BuildContext context, int index) {
    final item = items[index];
    final shown = index == current;
    final primary = Theme.of(context).colorScheme.primary;
    return ClickableGestureDetector(
      key: ValueKey("lightbox-gallery-grid-${item.key}"),
      onTap: () => showItem(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border:
              Border.all(width: 2, color: shown ? primary : Colors.transparent),
          boxShadow: shown
              ? [
                  BoxShadow(
                      color: primary.withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 1)
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: thumbnail(item, iconSize: 28),
        ),
      ),
    );
  }

  Widget buildStrip(BuildContext context, {bool handle = false}) {
    return Listener(
      onPointerSignal: onStripWheel,
      child: ColoredBox(
        color: Colors.black54,
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (handle) buildHandle(open: false),
            SizedBox(
              height: stripHeight,
              child: NotificationListener<ScrollNotification>(
                onNotification: onStripNotification,
                // Vommet issue 660: a mouse drags the strip too, like a
                // finger (a click on a thumbnail still shows it: the drag
                // starts past the touch slop). The wheel scrolls it too.
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      ...ScrollConfiguration.of(context).dragDevices,
                      PointerDeviceKind.mouse,
                    },
                  ),
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
          ]),
        ),
      ),
    );
  }

  Widget buildStripItem(BuildContext context, int index) {
    final item = items[index];
    final shown = index == current;
    return Center(
      child: ClickableGestureDetector(
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
              child: thumbnail(item, iconSize: 22),
            ),
          ),
        ),
      ),
    );
  }

  /// A picture's own thumbnail or a video's, behind its spoiler cover.
  Widget thumbnail(LightboxGalleryItem item, {required double iconSize}) {
    final attachment = item.attachment;
    final video = attachment is VideoAttachment ? attachment : null;
    final preview =
        attachment is ImageAttachment ? attachment.image : video?.thumbnail;
    final spoiler = attachment is FileAttachment ? attachment.spoiler : null;
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Colors.white10),
      MediaSpoilerBuilder(
        spoiler: spoiler,
        builder: (context, hidden) => hidden
            ? const Icon(Icons.visibility_off, size: 18, color: Colors.white70)
            : preview == null
                ? const SizedBox.shrink()
                : Image(
                    image: preview,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
      ),
      if (video != null)
        Center(
          child: Icon(Icons.play_arrow,
              size: iconSize,
              color: Colors.white,
              shadows: const [BoxShadow(blurRadius: 6, color: Colors.black54)]),
        ),
    ]);
  }

  /// Closes the gallery. [then] runs once it is popped (Vommet issue 902):
  /// an action that opens a dialog straight away would otherwise have that
  /// dialog closed by this deferred pop instead of the gallery.
  void close({VoidCallback? then}) {
    if (closing) return;
    // Pages swap a playing video for its thumbnail first, so the player can
    // move back into the timeline without two copies of it.
    setState(() => closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
      then?.call();
    });
  }

  /// Vommet issue 771: closes the gallery and jumps to [item]'s message.
  VoidCallback? jumpToMessage(LightboxGalleryItem item) {
    final jump = widget.onJumpToEvent;
    if (jump == null) return null;
    return () => close(then: () => jump(item.event.eventId));
  }

  /// Vommet issue 802: closes the gallery and forwards [item]'s message.
  VoidCallback? forward(LightboxGalleryItem item) {
    final room = widget.source?.room ?? widget.timeline?.room;
    if (room == null) return null;
    final action = forwardFromViewer(room, item.event,
        timeline: widget.source == null ? widget.timeline : null);
    if (action == null) return null;
    return () => close(then: action);
  }

  /// Vommet issue 894: closes the gallery and starts a reply to [item]'s
  /// picture or video; opened from the Media tab, the chat jumps to it too.
  VoidCallback? reply(LightboxGalleryItem item) {
    final room = widget.source?.room ?? widget.timeline?.room;
    if (room == null) return null;
    final action =
        replyFromViewer(room, item.event, jump: widget.onJumpToEvent != null);
    if (action == null) return null;
    return () {
      close();
      action();
    };
  }

  /// Vommet: closes the gallery and plays [item] in the picture-in-picture
  /// window. Only the video the gallery was opened on.
  VoidCallback? pictureInPicture(LightboxGalleryItem item) {
    final pip = widget.initialOnPictureInPicture;
    if (pip == null || item.key != widget.initialKey) return null;
    if (item.attachment is! VideoAttachment) return null;
    return () {
      pip();
      close();
    };
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
        setState(() => setZoomed(value));
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
        fileName: attachment.name,
        closing: closing,
        onZoomChanged: onZoom,
        menuButton: false,
        onJumpToMessage: jumpToMessage(item),
        onForward: forward(item),
        onReply: reply(item),
        onPictureInPicture: pictureInPicture(item),
      );
    }

    final image = attachment as ImageAttachment;
    return Lightbox(
      key: ValueKey(item.key),
      image: image.image,
      fileName: image.name,
      closing: closing,
      onZoomChanged: onZoom,
      menuButton: false,
      onJumpToMessage: jumpToMessage(item),
      onForward: forward(item),
      onReply: reply(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: LightboxFullScreen.active,
      builder: (context, fullScreen, _) => PopScope(
        // Vommet issue 684: back closes the grid first. Vommet issue 756:
        // and leaves full screen before that.
        canPop: !fullScreen && !(gridOpen && MediaQuery.of(context).mobile),
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || LightboxFullScreen.exitIfActive()) return;
          setGridOpen(false);
        },
        child: keepPaddingWhileZoomed(
            context,
            Stack(
              fit: StackFit.expand,
              children: [
                // Vommet issue 694: zoomed in, the room behind the viewer (its
                // message box shows through the barrier where the strip was) fades
                // out with the strip, leaving the picture on black.
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: zoomed ? 1 : 0,
                    duration: zoomFade,
                    curve: Curves.easeInOut,
                    child: const ColoredBox(
                        key: ValueKey("lightbox-gallery-zoom-backdrop"),
                        color: Colors.black),
                  ),
                ),
                buildGallery(context, fullScreen),
              ],
            )),
      ),
    );
  }

  /// Vommet issue 755: while zoomed in, lays the gallery out with the
  /// padding it had before the system bars hid.
  Widget keepPaddingWhileZoomed(BuildContext context, Widget child) {
    final media = MediaQuery.of(context);
    if (!zoomed || unzoomedPadding == null) {
      unzoomedPadding = media.padding;
      unzoomedViewPadding = media.viewPadding;
    }
    // Always a MediaQuery, so zooming doesn't rebuild the pages below.
    return MediaQuery(
      data: media.copyWith(
          padding: unzoomedPadding, viewPadding: unzoomedViewPadding),
      child: child,
    );
  }

  /// [fullScreen] (Vommet issue 662) shows the picture or video alone: no
  /// counter, arrows or strip, and ESC leaves full screen first.
  Widget buildGallery(BuildContext context, bool fullScreen) {
    final desktop = MediaQuery.of(context).desktop;
    final phone = MediaQuery.of(context).mobile;
    final item = items.isEmpty ? null : items[current];
    final sender = item == null
        ? null
        : source.room.getMemberOrFallback(item.event.senderId).displayName;

    // Items stay oldest first; going right means newer, or older when the
    // gallery mirrors a newest-first grid.
    final right = widget.newestFirst ? -1 : 1;
    final canGoOlder = current > 0 || source.canLoadOlder;
    final canGoNewer = current < items.length - 1;

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.arrowLeft): () => go(-right),
        SingleActivator(LogicalKeyboardKey.arrowRight): () => go(right),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!LightboxFullScreen.exitIfActive()) close();
        },
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
                    // Vommet: refresh moves the page view's offset when
                    // older items load in front, but the view keeps the
                    // page it last reported. Landing back on that number
                    // (one item loaded, then a move to the new one) reported
                    // nothing, and the counter stayed on the old item.
                    child: NotificationListener<ScrollEndNotification>(
                        onNotification: (notification) {
                          if (notification.depth == 0) reportSettledPage();
                          return false;
                        },
                        child: PageView.builder(
                          controller: pages,
                          // Vommet issue 694: a zoomed-in picture may spread
                          // over the faded strip. Paging is off while zoomed, so
                          // the pages either side stay off screen.
                          clipBehavior: zoomed ? Clip.none : Clip.hardEdge,
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
                        ))),
                if (item != null && !fullScreen)
                  Align(
                    alignment: Alignment.topCenter,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: fadeWhileZoomed(
                          alwaysIgnorePointer: true,
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
                if (item != null && !fullScreen) menuButton(item),
                if (desktop && !fullScreen) ...[
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
            // covers it or a video's controls. While zoomed it fades but
            // keeps its space, so the picture doesn't jump.
            if (!fullScreen && (items.length > 1 || source.canLoadOlder))
              fadeWhileZoomed(
                // Vommet issue 684: the grid takes the strip's place and
                // grows up into the room the picture leaves. Vommet issue
                // 753: it grows with the finger while the drag goes on.
                child: GestureDetector(
                  onVerticalDragStart: phone ? onGridDragStart : null,
                  onVerticalDragUpdate: phone ? onGridDragUpdate : null,
                  onVerticalDragEnd: phone ? onGridDragEnd : null,
                  onVerticalDragCancel: phone ? onGridDragCancel : null,
                  child: buildBottom(context, phone),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  /// The strip, or on a phone the grid as far open as [gridReveal] says:
  /// laid out at its full height and cut off below, so its rows keep
  /// their place while it grows.
  Widget buildBottom(BuildContext context, bool phone) {
    if (!phone) return buildStrip(context);
    final padding = MediaQuery.paddingOf(context);
    final full = gridHeightFor(MediaQuery.sizeOf(context), padding);
    final stripFull = handleHeight + stripHeight + padding.bottom;
    gridTravel = full - stripFull > 1 ? full - stripFull : 1;
    final reveal = gridReveal.value;
    if (reveal == 0) return buildStrip(context, handle: true);
    return SizedBox(
      key: const ValueKey("lightbox-gallery-grid-reveal"),
      height: stripFull + gridTravel * reveal,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: full,
          maxHeight: full,
          child: buildGrid(context, full),
        ),
      ),
    );
  }

  static const Duration zoomFade = Duration(milliseconds: 250);

  /// Vommet issue 766: the ⋮ menu (Copy / Save as / Share) for the page on
  /// screen, in the top-right corner. It fades while zoomed in and stays
  /// away from a spoiler that is still covered.
  Widget menuButton(LightboxGalleryItem item) {
    final attachment = item.attachment;
    final spoiler = attachment is FileAttachment ? attachment.spoiler : null;
    return Positioned(
      top: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ValueListenableBuilder(
            valueListenable: MediaSpoilerReveal.revealed,
            builder: (context, _, __) => LightboxMenuButton(
              key: ValueKey("lightbox-gallery-menu/${item.key}"),
              hidden: zoomed || closing || MediaSpoilerReveal.isHidden(spoiler),
              onOpen: (position) => LightboxMenu.show(context, position,
                  image:
                      attachment is ImageAttachment ? attachment.image : null,
                  video: attachment is VideoAttachment ? attachment.file : null,
                  fileName: attachment.name,
                  onJumpToMessage: jumpToMessage(item),
                  onForward: forward(item),
                  onReply: reply(item),
                  onPictureInPicture: pictureInPicture(item)),
            ),
          ),
        ),
      ),
    );
  }

  /// Vommet issue 685: the counter, arrows and strip fade out as soon as
  /// the picture is zoomed in at all, and back in when it is back to fit.
  Widget fadeWhileZoomed(
      {required Widget child, bool alwaysIgnorePointer = false}) {
    return AnimatedOpacity(
      opacity: zoomed ? 0 : 1,
      duration: zoomFade,
      curve: Curves.easeInOut,
      child:
          IgnorePointer(ignoring: zoomed || alwaysIgnorePointer, child: child),
    );
  }

  Widget edgeArrow(
      Alignment alignment, IconData icon, VoidCallback? onPressed) {
    final visible = showControls && onPressed != null && !zoomed;
    return Align(
      alignment: alignment,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: zoomFade,
        curve: Curves.easeInOut,
        child: IgnorePointer(
          ignoring: !visible,
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
