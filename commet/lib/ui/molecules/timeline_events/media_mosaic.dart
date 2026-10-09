import 'dart:math';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu_dialog.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:commet/utils/mosaic_layout.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Consecutive media posts by one sender, laid out as one Telegram-style
/// mosaic. Each tile is still its own event: tapping opens that picture, and
/// its context menu (right-click / long-press) acts on that event only.
class MediaMosaic extends StatelessWidget {
  const MediaMosaic({
    required this.timeline,
    required this.events,
    this.isThreadTimeline = false,
    this.setEditingEvent,
    this.setReplyingEvent,
    super.key,
  });

  final Timeline timeline;

  /// Oldest first.
  final List<TimelineEvent> events;
  final bool isThreadTimeline;
  final Function(TimelineEvent? event)? setEditingEvent;
  final Function(TimelineEvent? event)? setReplyingEvent;

  static const double maxMosaicWidth = 500;

  static Attachment? _media(TimelineEvent e) =>
      e is TimelineEventMessage ? e.attachments?.firstOrNull : null;

  static double _aspect(Attachment? a) {
    if (a is ImageAttachment && a.width != null && a.height != null) {
      return a.aspectRatio;
    }
    if (a is VideoAttachment && a.width != null && a.height != null) {
      return a.aspectRatio;
    }
    return 1;
  }

  /// Smallest width a mosaic shrinks to for small pictures.
  static const double minShrunkWidth = 120;

  /// How much the most enlarged picture is scaled up (tiles crop to fill,
  /// so the larger of the width and height ratios); 1 if none is. [natural]
  /// holds each item's size in pixels, null when unknown (e.g. videos).
  static double largestUpscale(
      MosaicLayout layout, List<Size?> natural, double devicePixelRatio) {
    var worst = 1.0;
    for (final t in layout.tiles) {
      final size = natural[t.index];
      if (size == null || size.width <= 0 || size.height <= 0) continue;
      final w = size.width / devicePixelRatio;
      final h = size.height / devicePixelRatio;
      worst = max(worst, max(t.width / w, t.height / h));
    }
    return worst;
  }

  static Size? _naturalSize(Attachment? a) =>
      a is ImageAttachment && a.width != null && a.height != null
          ? Size(a.width!, a.height!)
          : null;

  @override
  Widget build(BuildContext context) {
    final media = [for (final e in events) (e, _media(e))];

    return LayoutBuilder(builder: (context, constraints) {
      final available =
          constraints.maxWidth.isFinite ? constraints.maxWidth : maxMosaicWidth;
      final aspects = [for (final (_, a) in media) _aspect(a)];
      final maxWidth = min(available, maxMosaicWidth);
      var layout = Mosaic.layout(aspects, maxWidth: maxWidth);

      // Vommet: never draw a picture larger than its own pixels. Small
      // screenshots were blown up to fill the mosaic and looked blurry;
      // shrink the whole mosaic by the largest enlargement instead.
      final upscale = largestUpscale(
          layout,
          [for (final (_, a) in media) _naturalSize(a)],
          MediaQuery.devicePixelRatioOf(context));
      if (upscale > 1) {
        layout = Mosaic.layout(aspects,
            maxWidth: max(minShrunkWidth, maxWidth / upscale),
            targetRowHeight: max(48, 160 / upscale),
            maxRowHeight: max(64, 240 / upscale));
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 2, 2, 2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: layout.width,
            height: layout.height,
            child: Stack(children: [
              for (final t in layout.tiles)
                Positioned(
                  left: t.x,
                  top: t.y,
                  width: t.width,
                  height: t.height,
                  child: _MosaicTile(
                    key: ValueKey(media[t.index].$1.eventId),
                    event: media[t.index].$1,
                    attachment: media[t.index].$2,
                    timeline: timeline,
                    isThreadTimeline: isThreadTimeline,
                    setEditingEvent: setEditingEvent,
                    setReplyingEvent: setReplyingEvent,
                  ),
                ),
            ]),
          ),
        ),
      );
    });
  }
}

class _MosaicTile extends StatefulWidget {
  const _MosaicTile({
    required this.event,
    required this.attachment,
    required this.timeline,
    required this.isThreadTimeline,
    this.setEditingEvent,
    this.setReplyingEvent,
    super.key,
  });

  final TimelineEvent event;
  final Attachment? attachment;
  final Timeline timeline;
  final bool isThreadTimeline;
  final Function(TimelineEvent? event)? setEditingEvent;
  final Function(TimelineEvent? event)? setReplyingEvent;

  @override
  State<_MosaicTile> createState() => _MosaicTileState();
}

class _MosaicTileState extends State<_MosaicTile> {
  final videoController = VideoPlayerController();
  final videoKey = GlobalKey();

  void open() {
    final a = widget.attachment;
    if (a is ImageAttachment) {
      Lightbox.show(context, image: a.image);
    } else if (a is VideoAttachment) {
      Lightbox.show(context,
          video: a.file,
          aspectRatio: a.aspectRatio,
          thumbnail: a.thumbnail,
          videoController: videoController,
          key: videoKey);
    }
  }

  TimelineEventMenu menu(BuildContext context, {VoidCallback? onDone}) =>
      TimelineEventMenu(
        timeline: widget.timeline,
        event: widget.event,
        context: context,
        isThreadTimeline: widget.isThreadTimeline,
        setEditingEvent: widget.setEditingEvent,
        setReplyingEvent: widget.setReplyingEvent,
        onActionFinished: onDone,
      );

  Widget content(BuildContext context) {
    final a = widget.attachment;
    final scheme = Theme.of(context).colorScheme;
    ImageProvider? image;
    if (a is ImageAttachment) image = a.image;
    if (a is VideoAttachment) image = a.thumbnail;

    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: scheme.surfaceContainerHigh),
      if (image != null)
        Image(
          image: image,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      if (a is VideoAttachment)
        const Center(
          child: Icon(Icons.play_circle_fill, size: 40, color: Colors.white70),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    Widget result = Material(
      color: Colors.transparent,
      child: Ink(
        child: InkWell(
          onTap: open,
          onLongPress: MediaQuery.of(context).mobile
              ? () => showModalBottomSheet(
                    showDragHandle: true,
                    isScrollControlled: true,
                    elevation: 0,
                    context: context,
                    builder: (sheetContext) => TimelineEventMenuDialog(
                      event: widget.event,
                      timeline: widget.timeline,
                      menu: menu(sheetContext,
                          onDone: () => Navigator.of(sheetContext).pop()),
                    ),
                  )
              : null,
          child: content(context),
        ),
      ),
    );

    if (MediaQuery.of(context).desktop) {
      final m = menu(context);
      result = AdaptiveContextMenu(items: [
        for (final i in [...m.primaryActions, ...m.secondaryActions])
          tiamat.ContextMenuItem(
              text: i.name,
              icon: i.icon,
              onPressed: () => i.action?.call(context)),
      ], child: result);
    }

    return result;
  }
}
