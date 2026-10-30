import 'dart:math';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/ui/organisms/chat/reply_from_viewer.dart';
import 'package:commet/ui/organisms/forward_message/forward_from_viewer.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/timeline_image_size.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/emoji_widget.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_reactions.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu_dialog.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:commet/ui/organisms/message_selection/message_selection_row.dart';
import 'package:commet/utils/mosaic_layout.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 741: the picture of a mosaic its message's menu and hover
/// bar act on (the last one under the pointer, the oldest until then), and
/// how to mark it: a ring while the message is hovered or a picture's menu is
/// open, the other pictures dimmed while a reaction is being picked.
class MosaicFocus extends ChangeNotifier {
  String? _target;
  bool _marked = false;
  bool _picking = false;
  bool _disposed = false;

  // A picker or menu can close after the message left the screen.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String? get target => _target;
  bool get marked => _marked;
  bool get picking => _picking;

  /// Ignored while picking, so the picker can't change pictures under it.
  set target(String? eventId) {
    if (_picking || eventId == _target) return;
    _target = eventId;
    notifyListeners();
  }

  set marked(bool value) {
    if (value == _marked) return;
    _marked = value;
    notifyListeners();
  }

  set picking(bool value) {
    if (value == _picking) return;
    _picking = value;
    notifyListeners();
  }

  /// Whether the tile of [eventId] gets the ring; [isFirst]: it's the
  /// oldest picture, the target until another one is pointed at. Vommet
  /// issue 894: while a jump to one picture ([jumped]) is highlighted, just
  /// that one is ringed.
  bool rings(String eventId, {bool isFirst = false, String? jumped}) =>
      jumped != null
          ? jumped == eventId
          : (_marked || _picking) &&
              (_target ?? (isFirst ? eventId : null)) == eventId;

  /// Whether the tile of [eventId] is dimmed (another one is the target, or
  /// the [jumped] to picture).
  bool dims(String eventId, {bool isFirst = false, String? jumped}) =>
      jumped != null
          ? jumped != eventId
          : _picking && (_target ?? (isFirst ? eventId : null)) != eventId;
}

/// Consecutive media posts by one sender, laid out as one Telegram-style
/// mosaic. Each tile is still its own event: tapping opens that picture, its
/// context menu (right-click / long-press) acts on that event only, and its
/// reactions show on it (Vommet issue 741).
class MediaMosaic extends StatelessWidget {
  const MediaMosaic({
    required this.timeline,
    required this.events,
    this.isThreadTimeline = false,
    this.setEditingEvent,
    this.setReplyingEvent,
    this.selectOnLongPress,
    this.focus,
    this.onTileHovered,
    this.jumpedEventId,
    super.key,
  });

  /// Marks the picture the message's menu acts on; see [MosaicFocus].
  final MosaicFocus? focus;

  /// Vommet issue 894: the picture a jump (a reply's quote) landed on; it
  /// gets the ring and the others dim while the jump's highlight lasts.
  final String? jumpedEventId;

  /// The pointer entered a tile (after [focus] points at it).
  final VoidCallback? onTileHovered;

  final Timeline timeline;

  /// On a touch screen, called first on a long press on a picture with its
  /// event id; when it returns true (the picture was ticked in the message
  /// selection, see "Select several messages"), its menu doesn't open.
  final bool Function(String eventId)? selectOnLongPress;

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
      // Vommet: Large pictures make mosaics wider, with taller rows
      // (Vommet issue 721).
      final size = timelineImageSize;
      final maxWidth = min(available, size.maxMosaicWidth);
      final rowScale = size.mosaicRowScale;
      final maxRowHeight = min(240 * rowScale,
          size.maxPictureSize(MediaQuery.sizeOf(context)).height);
      var layout = Mosaic.layout(aspects,
          maxWidth: maxWidth,
          targetRowHeight: min(160 * rowScale, maxRowHeight),
          maxRowHeight: maxRowHeight);

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
            targetRowHeight:
                max(48, min(160 * rowScale, maxRowHeight) / upscale),
            maxRowHeight: max(64, maxRowHeight / upscale));
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
                    position: t.index + 1,
                    count: media.length,
                    timeline: timeline,
                    isThreadTimeline: isThreadTimeline,
                    groupEventIds: [for (final e in events) e.eventId],
                    selectOnLongPress: selectOnLongPress,
                    setEditingEvent: setEditingEvent,
                    setReplyingEvent: setReplyingEvent,
                    focus: focus,
                    jumpedEventId: jumpedEventId,
                    onHovered: onTileHovered,
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
    required this.groupEventIds,
    this.selectOnLongPress,
    required this.position,
    required this.count,
    this.setEditingEvent,
    this.setReplyingEvent,
    this.focus,
    this.jumpedEventId,
    this.onHovered,
    super.key,
  });

  final TimelineEvent event;
  final Attachment? attachment;

  /// 1 for the oldest picture of the mosaic, [count] for the newest.
  final int position;
  final int count;
  final MosaicFocus? focus;
  final String? jumpedEventId;
  final VoidCallback? onHovered;
  final Timeline timeline;
  final bool isThreadTimeline;
  final List<String> groupEventIds;
  final bool Function(String eventId)? selectOnLongPress;
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
    // Vommet issue 802: Forward in the viewer's menu.
    final forward = forwardFromViewer(widget.timeline.room, widget.event,
        timeline: widget.timeline);
    // Vommet issue 894: Reply to just this picture.
    final reply = replyFromViewer(widget.timeline.room, widget.event);
    if (a is ImageAttachment) {
      Lightbox.show(context,
          image: a.image, fileName: a.name, onForward: forward, onReply: reply);
    } else if (a is VideoAttachment) {
      Lightbox.show(context,
          onForward: forward,
          onReply: reply,
          video: a.file,
          aspectRatio: a.aspectRatio,
          thumbnail: a.thumbnail,
          fileName: a.name,
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
        // Vommet issue 895: Select on a picture ticks just that picture.
        selectTogether: null,
        onActionFinished: onDone,
        reactionTarget:
            widget.count > 1 ? (widget.position, widget.count) : null,
        onReactionPicking: widget.focus == null
            ? null
            : (picking) {
                widget.focus!.target = widget.event.eventId;
                widget.focus!.picking = picking;
              },
      );

  bool get isFirst => widget.position == 1;

  /// A phone's long-press menu: the ring marks this picture while it's open.
  Future<void> openSheet(BuildContext context) async {
    final focus = widget.focus;
    focus?.target = widget.event.eventId;
    focus?.marked = true;
    await showModalBottomSheet(
      showDragHandle: true,
      isScrollControlled: true,
      elevation: 0,
      context: context,
      builder: (sheetContext) => TimelineEventMenuDialog(
        event: widget.event,
        timeline: widget.timeline,
        menu:
            menu(sheetContext, onDone: () => Navigator.of(sheetContext).pop()),
      ),
    );
    if (mounted) focus?.marked = false;
  }

  Widget content(BuildContext context) {
    final a = widget.attachment;
    final scheme = Theme.of(context).colorScheme;
    ImageProvider? image;
    if (a is ImageAttachment) image = a.image;
    if (a is VideoAttachment) image = a.thumbnail;

    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: scheme.surfaceContainerHigh),
      if (image != null)
        RedactedImage(
            child: Image(
          image: image,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        )),
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
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: open,
          onLongPress: MediaQuery.of(context).mobile
              ? () {
                  if (widget.selectOnLongPress?.call(widget.event.eventId) ==
                      true) return;
                  openSheet(context);
                }
              : null,
          child: content(context),
        ),
      ),
    );

    if (MediaQuery.of(context).desktop) {
      final m = menu(context);
      result = AdaptiveContextMenu(items: [
        if (m.reactionContextMenuItem() case final reactions?) reactions,
        for (final i in [...m.primaryActions, ...m.secondaryActions])
          tiamat.ContextMenuItem(
              text: i.name,
              icon: i.icon,
              onPressed: () => i.action?.call(context)),
      ], child: result);
      result = MouseRegion(
        onEnter: (_) {
          widget.focus?.target = widget.event.eventId;
          widget.onHovered?.call();
        },
        child: result,
      );
    }

    final reactions =
        _MosaicTileReactions(timeline: widget.timeline, event: widget.event);
    final focus = widget.focus;
    return Stack(fit: StackFit.expand, children: [
      result,
      reactions,
      if (widget.groupEventIds.length > 1)
        _MosaicTileSelection(
            eventId: widget.event.eventId, group: widget.groupEventIds),
      if (focus != null)
        IgnorePointer(
          child: ListenableBuilder(
            listenable: focus,
            builder: (context, _) {
              final id = widget.event.eventId;
              final jumped = widget.jumpedEventId;
              final dim = focus.dims(id, isFirst: isFirst, jumped: jumped);
              final ring = focus.rings(id, isFirst: isFirst, jumped: jumped);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: dim ? Colors.black54 : Colors.transparent,
                  border: ring
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 3)
                      : null,
                ),
              );
            },
          ),
        ),
    ]);
  }
}

/// Vommet issue 786: while selecting messages, a picture's own check in its
/// corner and a tint when ticked. The row draws no pointer through to the
/// mosaic; it asks [MessageSelection.tileAt] which picture a tap hit, so
/// this registers its box there.
class _MosaicTileSelection extends StatefulWidget {
  const _MosaicTileSelection({required this.eventId, required this.group});

  final String eventId;
  final List<String> group;

  @override
  State<_MosaicTileSelection> createState() => _MosaicTileSelectionState();
}

class _MosaicTileSelectionState extends State<_MosaicTileSelection> {
  MessageSelection? selection;
  bool active = false;
  bool ticked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final found = MessageSelectionScope.maybeOf(context);
    if (found != selection) {
      selection?.removeListener(onSelectionChanged);
      selection?.tiles.remove(this);
      selection = found;
      selection?.addListener(onSelectionChanged);
      readState();
    }
  }

  @override
  void dispose() {
    selection?.removeListener(onSelectionChanged);
    selection?.tiles.remove(this);
    super.dispose();
  }

  void readState() {
    active = selection?.active == true;
    ticked = selection?.isTicked([widget.eventId]) == true;
  }

  void onSelectionChanged() {
    final wasActive = active;
    final wasTicked = ticked;
    readState();
    if (mounted && (wasActive != active || wasTicked != ticked)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = this.selection;
    if (selection == null || !active) {
      selection?.tiles.remove(this);
      return const SizedBox.shrink();
    }
    selection.tiles[this] = (context, widget.eventId);
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: ticked ? colors.primary.withAlpha(60) : Colors.transparent,
        alignment: Alignment.topRight,
        padding: const EdgeInsets.all(6),
        child: DecoratedBox(
          // Keeps the empty circle visible on a light picture.
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Colors.black38),
          child: SelectionCheckCircle(ticked: ticked),
        ),
      ),
    );
  }
}

/// Vommet issue 741: a mosaic picture's reactions, as small chips in its
/// bottom corner: up to two (one on a narrow tile), then "+N" for the rest,
/// which opens them all.
class _MosaicTileReactions extends StatelessWidget {
  const _MosaicTileReactions({required this.timeline, required this.event});

  final Timeline timeline;
  final TimelineEvent event;

  /// How many reactions fit on a tile [width] wide before "+N".
  static int chipsFor(double width) => width >= 150 ? 2 : 1;

  void toggle(Emoticon emote, Set<String> users) {
    final me = timeline.client.self?.identifier;
    if (users.contains(me)) {
      timeline.room.removeReaction(event, emote);
    } else {
      timeline.room.addReaction(event, emote);
    }
  }

  /// Vommet issue 784: every reaction with who reacted, as a sheet that drags
  /// up and scrolls on a phone (a dialog on desktop). Tapping an emoji adds or
  /// removes your reaction, as on the tile.
  void showAll(BuildContext context) {
    if (MediaQuery.of(context).desktop) {
      AdaptiveDialog.show(context,
          scrollable: false,
          builder: (context) => SizedBox(
              width: 400,
              height: 500,
              child: _MosaicReactionsList(
                  timeline: timeline, event: event, toggle: toggle)));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      elevation: 0,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.95,
        builder: (context, controller) => ScaledSafeArea(
          child: _MosaicReactionsList(
              timeline: timeline,
              event: event,
              toggle: toggle,
              controller: controller),
        ),
      ),
    );
  }

  Widget chip(BuildContext context,
      {required Widget child,
      required VoidCallback onTap,
      VoidCallback? onLongPress,
      String? tooltip,
      bool mine = false}) {
    Widget result = Material(
      color: Colors.black.withAlpha(160),
      shape: StadiumBorder(
          side: mine
              ? BorderSide(color: Theme.of(context).colorScheme.primary)
              : BorderSide.none),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: child,
        ),
      ),
    );
    if (tooltip != null) result = Tooltip(message: tooltip, child: result);
    return Padding(padding: const EdgeInsets.only(right: 4), child: result);
  }

  @override
  Widget build(BuildContext context) {
    final event = this.event;
    if (event is! TimelineEventFeatureReactions) return const SizedBox.shrink();
    final all = (event as TimelineEventFeatureReactions)
        .getReactions(timeline)
        .entries
        .where((e) => e.value.isNotEmpty)
        .toList();
    if (all.isEmpty) return const SizedBox.shrink();
    final me = timeline.client.self?.identifier;
    const text = TextStyle(color: Colors.white, fontSize: 12);

    return LayoutBuilder(builder: (context, constraints) {
      final shown = all.take(chipsFor(constraints.maxWidth)).toList();
      final rest = all.length - shown.length;
      return Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(5),
          // Shrinks on a tile too small for the chips.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final e in shown)
                chip(context,
                    mine: e.value.contains(me),
                    tooltip: TimelineEventViewReactions.reactorsTooltip(
                        timeline, e.key, e.value,
                        redaction: RedactionScope.of(context)),
                    onTap: () => toggle(e.key, e.value),
                    onLongPress: () => TimelineEventViewReactions.showReactors(
                        context, timeline, e.key, e.value),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      EmojiWidget(e.key, height: 16, maxWidth: 48),
                      const SizedBox(width: 4),
                      Text("${e.value.length}", style: text),
                    ])),
              if (rest > 0)
                chip(context,
                    onTap: () => showAll(context),
                    child: Text("+$rest", style: text)),
            ]),
          ),
        ),
      );
    });
  }
}

/// Vommet issue 784: a mosaic picture's reactions, each emoji (tap to add or
/// remove yours) followed by the people who reacted with it. Follows the
/// timeline, so it updates while open.
class _MosaicReactionsList extends StatelessWidget {
  const _MosaicReactionsList(
      {required this.timeline,
      required this.event,
      required this.toggle,
      this.controller});

  final Timeline timeline;
  final TimelineEvent event;
  final void Function(Emoticon emote, Set<String> users) toggle;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: timeline.onChange.stream,
        builder: (context, _) {
          final index = timeline.events.indexOf(event);
          final current = index < 0 ? event : timeline.events[index];
          if (current is! TimelineEventFeatureReactions) {
            return const SizedBox.shrink();
          }
          final reactions = (current as TimelineEventFeatureReactions)
              .getReactions(timeline)
              .entries
              .where((e) => e.value.isNotEmpty)
              .toList();
          final me = timeline.client.self?.identifier;
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              for (final e in reactions) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Material(
                      color: scheme.surfaceContainerHigh,
                      shape: StadiumBorder(
                          side: e.value.contains(me)
                              ? BorderSide(color: scheme.primary)
                              : BorderSide.none),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        onTap: () => toggle(e.key, e.value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            EmojiWidget(e.key, height: 24, maxWidth: 72),
                            const SizedBox(width: 6),
                            tiamat.Text.label("${e.value.length}"),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
                for (final id in [
                  if (e.value.contains(me)) me!,
                  ...e.value.where((id) => id != me),
                ])
                  UserPanel(
                      userId: id,
                      contextRoom: timeline.room,
                      client: timeline.client),
              ],
            ],
          );
        });
  }
}
