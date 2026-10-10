import 'dart:async';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
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
      {required this.timeline, required super.child, super.key});

  final Timeline timeline;

  static Timeline? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LightboxGalleryScope>()?.timeline;

  @override
  bool updateShouldNotify(LightboxGalleryScope oldWidget) =>
      oldWidget.timeline != timeline;
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
    super.key,
  });

  final Timeline timeline;

  /// [LightboxGalleryItem.key] of the item that was opened.
  final String initialKey;

  /// The opened video's own controller and player key, so a video that was
  /// playing in the timeline carries on in the viewer.
  final VideoPlayerController? initialVideoController;
  final Key? initialContentKey;

  /// Opens the gallery if [image] or [video] is one of the loaded
  /// attachments of the timeline around [context]. Returns null otherwise.
  static Future<void>? showIfInTimeline(
    BuildContext context, {
    ImageProvider? image,
    FileProvider? video,
    VideoPlayerController? videoController,
    Key? key,
  }) {
    final timeline = LightboxGalleryScope.maybeOf(context);
    if (timeline == null) return null;

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

    setState(() {
      items = updated;
      current = index;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !pages.hasClients) return;
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
    pages.animateToPage(target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic);
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

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => go(1),
        const SingleActivator(LogicalKeyboardKey.escape): close,
      },
      child: Focus(
        autofocus: true,
        child: MouseRegion(
          onHover: (_) => onHover(),
          child: Stack(
            children: [
              PageView.builder(
                controller: pages,
                // Builds the pages either side too, so they load ahead.
                allowImplicitScrolling: true,
                physics: zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: onPageChanged,
                itemCount: items.length,
                findChildIndexCallback: (key) {
                  if (key is! ValueKey<String>) return null;
                  final index = items.indexWhere((i) => i.key == key.value);
                  return index == -1 ? null : index;
                },
                itemBuilder: buildPage,
              ),
              if (item != null)
                Align(
                  alignment: Alignment.topCenter,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: Text(
                              "${current + 1} / ${items.length}"
                              "${sender == null ? "" : "  ·  $sender"}",
                              style: const TextStyle(color: Colors.white),
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
                    current > 0 || widget.timeline.canLoadHistory
                        ? () => go(-1)
                        : null),
                edgeArrow(Alignment.centerRight, Icons.chevron_right,
                    current < items.length - 1 ? () => go(1) : null),
              ],
            ],
          ),
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
