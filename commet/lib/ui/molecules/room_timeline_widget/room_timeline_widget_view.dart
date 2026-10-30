import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/ui/molecules/timeline_events/media_group_member.dart';
import 'package:commet/utils/media_group.dart';
import 'package:commet/client/components/message_effects/message_effect_component.dart';
import 'package:commet/client/components/read_receipts/read_receipt_component.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/room_predecessor_banner.dart';
import 'package:commet/ui/molecules/room_timeline_widget/room_timeline_overlay.dart';
import 'package:commet/ui/molecules/room_timeline_widget/room_scroll_positions.dart';
import 'package:commet/ui/molecules/room_timeline_widget/unread_jump_targets.dart';
import 'package:commet/client/timeline_events/timeline_event_add_reaction.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:commet/ui/molecules/room_timeline_widget/timeline_keyboard_scroll.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomTimelineWidgetView extends StatefulWidget {
  const RoomTimelineWidgetView(
      {required this.timeline,
      this.markAsRead,
      this.onViewScrolled,
      this.setEditingEvent,
      this.setReplyingEvent,
      this.onAttachedToBottom,
      this.isThreadTimeline = false,
      super.key});
  final Timeline timeline;
  final Function(TimelineEvent event)? markAsRead;
  final Function(TimelineEvent? event)? setReplyingEvent;
  final Function(TimelineEvent? event)? setEditingEvent;
  final Function()? onAttachedToBottom;
  final bool isThreadTimeline;

  final Function(
      {required double offset,
      required double maxScrollExtent,
      required double minScrollExtent})? onViewScrolled;

  @override
  State<RoomTimelineWidgetView> createState() => RoomTimelineWidgetViewState();
}

class RoomTimelineWidgetViewState extends State<RoomTimelineWidgetView> {
  int numBuilds = 0;

  int recentItemsCount = 0;
  int get historyItemsCount => timeline.events.length - recentItemsCount;

  /// Vommet issue 743: the rows ([eventKeys], [recentItemsCount]) must match
  /// [Timeline.events]. If they drift (a change the view wasn't told about),
  /// the lists build out of range and the timeline stays blank until the room
  /// is reopened. Re-key from the timeline instead, keeping each event's key.
  /// Runs at build: between a removal's notice and the removal itself the two
  /// differ by design.
  void syncKeysWithTimeline() {
    final events = timeline.events;
    if (eventKeys.length == events.length &&
        recentItemsCount >= 0 &&
        recentItemsCount <= events.length) {
      return;
    }
    Log.w("Timeline view out of step with its timeline "
        "(${eventKeys.length} rows, ${events.length} events, "
        "$recentItemsCount recent), re-keying");
    final keys = {for (final (key, id) in eventKeys) id: key};
    eventKeys = [
      for (final e in events)
        (keys.remove(e.eventId) ?? GlobalKey(debugLabel: e.eventId), e.eventId)
    ];
    recentItemsCount = recentItemsCount.clamp(0, events.length);
  }

  bool firstFrame = true;
  bool animatingToBottom = false;

  late ScrollController controller;
  late List<(GlobalKey, String)> eventKeys;
  late Timeline timeline;

  GlobalKey firstFrameScrollViewKey = GlobalKey();
  GlobalKey scrollViewKey = GlobalKey();
  GlobalKey centerKey = GlobalKey();
  GlobalKey recentItemsKey = GlobalKey();
  GlobalKey overlayKey = GlobalKey();
  GlobalKey stackKey = GlobalKey();

  LayerLink selectedEventLayerLink = LayerLink();

  /// The event the hover menu acts on (in a mosaic, one of its pictures).
  String? selectedMenuEventId;
  SelectableEventViewWidget? selectedEventView;

  String? highlightedEventId;
  TimelineViewEntryState? highlightedEventState;
  GlobalKey? highlightedEventOffstageKey;
  int? highlightedEventOffstageIndex;
  Timer? highlightClearTimer;

  /// How long a jumped-to event stays highlighted.
  static const highlightDuration = Duration(seconds: 3);

  /// Vommet Deep Search: how long a jump waits for an unloaded message's
  /// /context before showing an error.
  static const jumpContextTimeout = Duration(seconds: 15);

  String get jumpContextFailed => Intl.message(
      "Couldn’t load that message. Check your connection and try again.",
      name: "jumpContextFailed",
      desc: "Shown when jumping to an older message timed out or failed");

  String get jumpContextNotFound => Intl.message(
      "That message isn’t available anymore.",
      name: "jumpContextNotFound",
      desc: "Shown when a message to jump to could not be found in the room");
  List<StreamSubscription>? subscriptions;

  // Vommet issue 345: cancelled in dispose. EventBus.jumpToEvent lives for
  // the whole app session, so a left-over listener kept every room view ever
  // opened (and its chat, timeline keys and subscriptions) alive, and ran
  // each jump in all of them.
  StreamSubscription<String>? jumpSubscription;

  bool wasLastScrollAttachedToBottom = false;
  bool loading = false;

  bool get attachedToBottom => controller.hasClients
      ? controller.offset - controller.positions.first.minScrollExtent < 50 ||
          animatingToBottom
      : true;

  bool isLoadingFuture = false;
  bool isLoadingHistory = false;

  /// Vommet: history pages fetched in a row that added nothing shown on its
  /// own (only membership/profile changes, which fold into one summary row).
  /// Such pages never fill the view, so scrolling-driven loading would page
  /// back through the whole room; after [emptyHistoryPagesBeforePause] it
  /// pauses and offers a button instead.
  static const int emptyHistoryPagesBeforePause = 3;
  int emptyHistoryPages = 0;
  bool historyPaused = false;

  /// Vommet: set by "Load older messages": from then on this timeline keeps
  /// loading until the view fills or the room's start, however many empty
  /// pages that takes, instead of pausing again.
  bool historyPauseDismissed = false;

  String get labelTimelineHistoryPaused => Intl.message(
      "No messages in the last few pages of history, only membership and profile changes.",
      desc:
          "Shown at the top of the timeline when loading older history paused because recent pages had no messages",
      name: "labelTimelineHistoryPaused");

  String get promptTimelineLoadOlderMessages => Intl.message(
      "Load older messages",
      desc:
          "Button that resumes loading older history after it paused on pages without messages",
      name: "promptTimelineLoadOlderMessages");

  MessageEffectComponent? effects;
  String? lastReadEventId;

  /// Vommet issue 634: the scroll offset that puts the room's saved position
  /// back on screen, used once the first frame is laid out.
  double? restoreOffset;
  Timer? savePositionTimer;

  /// Vommet: the @ and ♥ buttons ([UnreadJumpTargets]) count from the read
  /// marker the room had when it was opened, until the room is reopened.
  String? jumpTargetsReadUpTo;
  final Set<String> seenJumpTargets = {};
  UnreadJumpTargets jumpTargets = UnreadJumpTargets.empty;
  final Map<String, bool> mentionsMeCache = {};
  Timer? jumpTargetsTimer;

  String get scrollPositionKey => RoomScrollPositions.key(
      timeline.client.identifier, timeline.room.identifier);

  @override
  void initState() {
    effects = widget.timeline.client.getComponent<MessageEffectComponent>();
    jumpTargetsReadUpTo = widget.timeline.room.lastRead;

    initFromTimeline(widget.timeline);
    restoreSavedPosition();

    controller = ScrollController(initialScrollOffset: -999999);
    jumpSubscription = EventBus.jumpToEvent.stream.listen(onJumpSignal);
    EventBus.openThreadRootId.addListener(scheduleJumpTargetsScan);
    WidgetsBinding.instance.addPostFrameCallback(onAfterFirstFrame);
    super.initState();
  }

  void initFromTimeline(Timeline timeline) {
    if (subscriptions != null) {
      for (var sub in subscriptions!) {
        sub.cancel();
      }
    }

    String? targetEventId = timeline.room.lastRead;

    this.timeline = timeline;
    emptyHistoryPages = 0;
    historyPaused = false;
    historyPauseDismissed = false;
    var index = timeline.events.indexWhere((i) => i.eventId == targetEventId);

    if (index > 0) {
      // Find the next message after the latest read event

      int? viewIndex = null;
      for (int i = index; i >= 1; i--) {
        var eventType =
            TimelineViewEntryState.eventToDisplayType(timeline.events[i - 1]);

        if (eventType == TimelineEventWidgetDisplayType.message) {
          lastReadEventId = timeline.events[i - 1].eventId;
          viewIndex = i - 1;
        }
      }

      isLoadingFuture = false;
      isLoadingHistory = false;

      recentItemsCount = max(1, viewIndex ?? index);
    } else {
      if (timeline.events.length > 1) {
        recentItemsCount = 1;
      }
    }

    var receipts = timeline.room.getComponent<ReadReceiptComponent>();
    subscriptions = [
      timeline.onEventAdded.stream.listen(onEventAdded),
      timeline.onChange.stream.listen(onEventChanged),
      timeline.onRemove.stream.listen(onEventRemoved),
      timeline.onLoadingStatusChanged.listen(onLoadingStatusChanged),
      if (receipts != null)
        receipts.onReadReceiptsUpdated.listen(onReadReceiptUpdated),
    ];

    if (preferences.messageEffectsEnabled.value) {
      for (int i = 0; i < 5; i++) {
        if (i >= timeline.events.length) break;

        var event = timeline.events[i];
        if (effects?.hasEffect(event) == true) {
          effects?.doEffect(event);
          break;
        }
      }
    }

    eventKeys = List.from(
        timeline.events
            .map((e) => (GlobalKey(debugLabel: e.eventId), e.eventId)),
        growable: true);
  }

  @override
  void dispose() {
    highlightClearTimer?.cancel();
    jumpTargetsTimer?.cancel();
    for (var element in subscriptions!) {
      element.cancel();
    }
    jumpSubscription?.cancel();
    EventBus.openThreadRootId.removeListener(scheduleJumpTargetsScan);

    super.dispose();
  }

  /// Vommet issue 634: opens the room where it was left, if it was scrolled
  /// up and that event is still in the timeline.
  void restoreSavedPosition() {
    if (widget.isThreadTimeline) return;
    final saved = RoomScrollPositions.get(scrollPositionKey);
    if (saved == null) return;
    final index = timeline.events.indexWhere((e) => e.eventId == saved.eventId);
    if (index == -1) return;
    // The saved event becomes the first history item, so its bottom edge sits
    // on the centre line; the offset moves that line up from the bottom.
    recentItemsCount = index;
    restoreOffset = -saved.gapToBottom;
  }

  void scheduleSavePosition() {
    savePositionTimer?.cancel();
    savePositionTimer = Timer(const Duration(milliseconds: 150), () {
      saveScrollPosition();
      markVisibleJumpTargetsSeen();
    });
  }

  void scheduleJumpTargetsScan() {
    if (widget.isThreadTimeline) return;
    jumpTargetsTimer?.cancel();
    jumpTargetsTimer =
        Timer(const Duration(milliseconds: 300), scanJumpTargets);
  }

  /// Vommet: finds what the @ and ♥ buttons lead to. Only a live timeline
  /// holds every message since the read marker; while the view shows older
  /// history the buttons keep their last counts.
  void scanJumpTargets() {
    if (!mounted || widget.isThreadTimeline) return;
    final source = [timeline, liveTimeline, widget.timeline]
        .firstWhereOrNull((t) => t != null && !t.canLoadFuture);
    if (source == null) return;

    final room = source.room;
    final openThread = EventBus.openThreadRootId.value;
    jumpTargets = UnreadJumpTargets.scan(
      source.events.map((e) {
        final reactsTo =
            e is TimelineEventAddReaction ? e.reactedToEventId : null;
        // Vommet issue 826: a thread reply counts only when it names me.
        final threadRoot = room.threadRootIdOf(e);
        final mentionsMe = reactsTo == null &&
            mentionsMeCache.putIfAbsent(
                e.eventId,
                () => threadRoot == null
                    ? room.eventMentionsMe(e)
                    : room.threadReplyMentionsMe(e));
        // The thread is open in the side panel: it was seen there. Added
        // before the scan looks at this event, so it is left out.
        if (mentionsMe && threadRoot != null && threadRoot == openThread) {
          seenJumpTargets.add(e.eventId);
        }
        return JumpScanEvent(
            eventId: e.eventId,
            senderId: e.senderId,
            reactsTo: reactsTo,
            mentionsMe: mentionsMe);
      }),
      me: source.client.self?.identifier,
      readUpTo: jumpTargetsReadUpTo,
      senderOf: (id) => source.tryGetEvent(id)?.senderId,
      seen: seenJumpTargets,
    );
    showJumpTargets();
    // Something that came in on screen was seen as it arrived.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => markVisibleJumpTargetsSeen());
  }

  void showJumpTargets() {
    var overlayState = overlayKey.currentState as TimelineOverlayState?;
    overlayState?.setJumpTargets(jumpTargets);
  }

  void markJumpTargetsSeen(Iterable<JumpTarget> targets) {
    final seen = targets.toList();
    if (seen.isEmpty) return;
    for (final target in seen) {
      seenJumpTargets
        ..add(target.eventId)
        ..addAll(target.sources);
    }
    jumpTargets = UnreadJumpTargets(
        mentions: jumpTargets.mentions.where((t) => !seen.contains(t)).toList(),
        reactions:
            jumpTargets.reactions.where((t) => !seen.contains(t)).toList());
    showJumpTargets();
  }

  /// Vommet: a mention or reacted message counts as seen once its row is on
  /// screen.
  void markVisibleJumpTargetsSeen() {
    if (!mounted || jumpTargets.isEmpty) return;
    final viewport = stackKey.globalPaintBounds;
    if (viewport == null) return;
    final keys = {for (final (key, id) in eventKeys) id: key};
    bool visible(JumpTarget target) {
      final bounds = keys[target.eventId]?.globalPaintBounds;
      return bounds != null && !bounds.isEmpty && bounds.overlaps(viewport);
    }

    markJumpTargetsSeen([
      ...jumpTargets.mentions.where(visible),
      ...jumpTargets.reactions.where(visible),
    ]);
  }

  /// Vommet: the @ or ♥ button jumps to its oldest target.
  void jumpToTarget(bool reactions) {
    final targets = reactions ? jumpTargets.reactions : jumpTargets.mentions;
    final target = targets.firstOrNull;
    if (target == null) return;
    markJumpTargetsSeen([target]);
    // Vommet issue 826: a mention in a thread opens that thread.
    final event = [timeline, liveTimeline, widget.timeline]
        .map((t) => t?.tryGetEvent(target.eventId))
        .firstWhereOrNull((e) => e != null);
    final threadRoot =
        event == null ? null : timeline.room.threadRootIdOf(event);
    if (threadRoot != null) {
      EventBus.openThread.add(
          (timeline.client.identifier, timeline.room.identifier, threadRoot));
      return;
    }
    jumpToEvent(target.eventId);
  }

  void markTargetsSeen(bool reactions) => markJumpTargetsSeen(
      reactions ? jumpTargets.reactions : jumpTargets.mentions);

  // Runs after scrolling settles; a timer left over from a closed room view
  // finds it unmounted and does nothing.
  void saveScrollPosition() {
    if (!mounted || widget.isThreadTimeline || firstFrame) return;
    if (attachedToBottom) {
      RoomScrollPositions.forget(scrollPositionKey);
      return;
    }
    final viewport = stackKey.globalPaintBounds;
    if (viewport == null) return;
    final anchor = RoomScrollPositions.anchorFor(viewport, [
      for (final (key, eventId) in eventKeys)
        if (key.currentContext != null)
          if (key.globalPaintBounds case Rect bounds) (eventId, bounds),
    ]);
    if (anchor != null) RoomScrollPositions.save(scrollPositionKey, anchor);
  }

  void onEventAdded(int index, {bool cascade = true}) {
    scheduleJumpTargetsScan();
    eventKeys.insert(index, (
      GlobalKey(debugLabel: timeline.events[index].eventId),
      timeline.events[index].eventId
    ));

    if (index == 0 || index < recentItemsCount) {
      recentItemsCount += 1;
    }

    if (index == 0) {
      if (attachedToBottom) {
        scrollToBottom();

        widget.markAsRead?.call(timeline.events[0]);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          scrollToBottom();

          widget.markAsRead?.call(timeline.events[0]);
        });
      }

      if (preferences.messageEffectsEnabled.value) {
        effects?.doEffect(timeline.events[index]);
      }
    }

    if (cascade) {
      if (index > 0) {
        onEventChanged(index - 1, cascade: false);
      }

      if (index < timeline.events.length - 1) {
        onEventChanged(index + 1, cascade: false);
      }

      refreshMediaGroupRuns(index);
    }

    setState(() {});
  }

  /// Media mosaics are drawn by the oldest post of a run, and one change can
  /// regroup every post in the run (a picture joining or splitting it, or an
  /// older one shifting the groups of ten). Refresh every entry of the runs
  /// around [index] that the ±1 cascade didn't reach, so no post keeps a
  /// stale role (a stale child draws nothing).
  void refreshMediaGroupRuns(int index) {
    if (!preferences.groupConsecutiveMedia.value) return;
    final threads = timeline.room.client.getComponent<ThreadsComponent>();
    final entries = <int>{};
    for (final i in [index + 1, index, index - 1]) {
      if (i < 0 || i >= timeline.events.length) continue;
      final (newest, oldest) = mediaGroupRunAt(i, timeline,
          threads: threads, isThreadTimeline: widget.isThreadTimeline);
      for (var j = newest; j <= oldest; j++) {
        if ((j - index).abs() > 1) entries.add(j);
      }
    }
    for (final j in entries) {
      if (j < eventKeys.length) onEventChanged(j, cascade: false);
    }
  }

  /// The index of the entry that draws the event at [index]: the root of
  /// its media mosaic, or [index] itself.
  int mosaicRootIndexOf(int index) {
    if (!preferences.groupConsecutiveMedia.value ||
        !timeline.room.shouldPreviewMedia) {
      return index;
    }
    final position = mediaGroupPositionAt(index, timeline,
        threads: timeline.room.client.getComponent<ThreadsComponent>(),
        isThreadTimeline: widget.isThreadTimeline);
    return position.role == MediaGroupRole.child
        ? position.rootIndex ?? index
        : index;
  }

  void onEventChanged(int index, {bool cascade = true}) {
    scheduleJumpTargetsScan();
    var event = timeline.events[index];
    var existing = eventKeys[index];
    eventKeys[index] = (existing.$1, event.eventId);

    var key = eventKeys.firstWhere(
      (element) => element.$2 == event.eventId,
    );

    assert(event.eventId == key.$2);

    var state = key.$1.currentState;

    if (state is TimelineEventViewWidget) {
      (state as TimelineEventViewWidget).update(index);
    } else {
      Log.w("Failed to get state");
    }

    if (index == 0) {
      if (attachedToBottom) {
        scrollToBottom();

        widget.markAsRead?.call(timeline.events[0]);
      }
    }

    if (cascade) {
      if (index > 0) {
        onEventChanged(index - 1, cascade: false);
      }

      if (index < timeline.events.length - 1) {
        onEventChanged(index + 1, cascade: false);
      }

      refreshMediaGroupRuns(index);
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Vommet: the timeline may be gone (room closed) or not attached yet
      // by the next frame; position would throw.
      if (!mounted || !controller.hasClients) return;
      controller.animateTo(controller.position.minScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutExpo);
    });
  }

  void onEventRemoved(int index) {
    scheduleJumpTargetsScan();
    if (index < recentItemsCount) {
      recentItemsCount -= 1;
    }

    var removed = eventKeys.removeAt(index);

    assert(timeline.events[index].eventId == removed.$2);

    // A removed picture can split or shrink a media mosaic; once the list has
    // settled, refresh the neighbours and the roots of the affected runs.
    if (preferences.groupConsecutiveMedia.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || timeline.events.isEmpty) return;
        final last = min(timeline.events.length, eventKeys.length) - 1;
        for (final i in [index - 1, index]) {
          if (i >= 0 && i <= last) onEventChanged(i, cascade: false);
        }
        refreshMediaGroupRuns(index.clamp(0, last));
      });
    }

    setState(() {});
  }

  /// Vommet issue 919: frames [onAfterFirstFrame] has waited for the scroll
  /// view to be laid out.
  int firstFrameRetries = 0;
  static const int maxFirstFrameRetries = 10;

  void onAfterFirstFrame(_) {
    if (!mounted) return;
    // Vommet issue 919: the scroll view may not be laid out yet (no client,
    // or a client without sizes). Giving up here left the list offstage, and
    // the room blank, for good. Retry on the next frame instead; after
    // [maxFirstFrameRetries] show the list anyway, but keep waiting for the
    // sizes so the restore (issue 634), centering and pending jumps below
    // still run, once.
    if (!controller.hasClients ||
        !controller.position.hasContentDimensions ||
        !controller.position.hasViewportDimension) {
      if (firstFrameRetries == 0) {
        Log.w("Timeline view not laid out after its first frame "
            "(${controller.hasClients ? "no sizes" : "no scroll client"}), "
            "retrying");
      }
      firstFrameRetries++;
      if (firstFrameRetries == maxFirstFrameRetries) {
        Log.w("Timeline view still not laid out after "
            "$maxFirstFrameRetries frames, showing it anyway");
        controller = ScrollController();
        scrollViewKey = GlobalKey();
        controller.addListener(onScroll);
        setState(() {
          firstFrame = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback(onAfterFirstFrame);
      // A frame may not be coming by itself.
      if (firstFrameRetries < maxFirstFrameRetries) {
        WidgetsBinding.instance.scheduleFrame();
      }
      return;
    }

    if (controller.hasClients) {
      double extent = controller.position.minScrollExtent;

      if (restoreOffset case double offset) {
        extent = max(extent, offset);
        restoreOffset = null;
      } else if (controller.position.viewportDimension < -extent) {
        extent = -controller.position.viewportDimension / 2;
      }

      controller = ScrollController(initialScrollOffset: extent);
      scrollViewKey = GlobalKey();
      controller.addListener(onScroll);
      setState(() {
        firstFrame = false;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      onScroll();
    });
    scheduleJumpTargetsScan();

    // Vommet issue 665: the room was opened from a link to a message.
    if (!widget.isThreadTimeline) {
      final pending = EventBus.takePendingJump(timeline.room.identifier);
      if (pending != null) jumpToEvent(pending);
    } else {
      // Vommet Deep Search: the thread was opened at one of its replies.
      // Only a reply this thread has loaded: a far jump would swap in the
      // room's own timeline.
      final pending = EventBus.takePendingThreadJump(timeline.room.identifier);
      if (pending != null &&
          timeline.events.any((event) => event.eventId == pending)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) jumpToEvent(pending);
        });
      }
    }
  }

  void onJumpSignal(String eventId) {
    // Vommet issue 665: a pending jump this view now makes needn't wait for
    // the next view of the room.
    if (!widget.isThreadTimeline) {
      EventBus.takePendingJump(timeline.room.identifier);
    }
    jumpToEvent(eventId);
  }

  void onScroll() {
    // Vommet: also called after a frame once history loaded, by which time
    // the room may be closed or its timeline rebuilt (#102's reload).
    if (!mounted || !controller.hasClients) return;
    widget.onViewScrolled?.call(
        offset: controller.offset,
        maxScrollExtent: controller.position.maxScrollExtent,
        minScrollExtent: controller.position.minScrollExtent);

    var overlayState = overlayKey.currentState as TimelineOverlayState?;
    overlayState?.setAttachedToBottom(attachedToBottom);

    if (wasLastScrollAttachedToBottom == false && attachedToBottom) {
      widget.onAttachedToBottom?.call();
    }

    wasLastScrollAttachedToBottom = attachedToBottom;
    scheduleSavePosition();

    double loadingThreshold = 500;

    // When the history items are empty, the sliver takes up exactly the height of the viewport, so we should use that height instead
    if (historyItemsCount == 0) {
      var renderBox = stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        loadingThreshold = renderBox.size.height;
      }
    }

    if (controller.offset >
            controller.position.maxScrollExtent - loadingThreshold &&
        !historyPaused &&
        !timeline.isLoadingHistory &&
        timeline.canLoadHistory) {
      loadHistoryPage();
    }

    if (controller.offset <
            (controller.position.minScrollExtent + loadingThreshold) &&
        !timeline.isLoadingFuture &&
        timeline.canLoadFuture) {
      timeline.loadMoreFuture();
    }
  }

  void loadHistoryPage() {
    var countBefore = timeline.events.length;
    var loadingTimeline = timeline;
    timeline.loadMoreHistory().then((_) {
      if (!mounted || loadingTimeline != timeline) return;
      notePageLoaded(countBefore);
      WidgetsBinding.instance.addPostFrameCallback((_) => onScroll());
    });
  }

  /// Older events are appended at the end of [Timeline.events]; a page counts
  /// as empty when none of them is shown as its own row.
  void notePageLoaded(int countBefore) {
    var added = timeline.events.skip(countBefore);
    var showsSomething = added.any((e) =>
        TimelineViewEntryState.eventToDisplayType(e) !=
            TimelineEventWidgetDisplayType.generic &&
        TimelineViewEntryState.eventToDisplayType(e) !=
            TimelineEventWidgetDisplayType.hidden);

    if (showsSomething) {
      emptyHistoryPages = 0;
      return;
    }

    emptyHistoryPages += 1;
    if (!historyPauseDismissed &&
        emptyHistoryPages >= emptyHistoryPagesBeforePause) {
      setState(() {
        historyPaused = true;
      });
    }
  }

  void resumeHistory() {
    setState(() {
      historyPaused = false;
      historyPauseDismissed = true;
      emptyHistoryPages = 0;
    });
    if (!timeline.isLoadingHistory && timeline.canLoadHistory) {
      loadHistoryPage();
    }
  }

  void animateAndSnapToBottom() {
    controller.position.hold(() {});

    setState(() {
      initFromTimeline(liveTimeline ?? widget.timeline);
    });

    var overlayState = overlayKey.currentState as TimelineOverlayState?;
    overlayState?.setAttachedToBottom(attachedToBottom);
    widget.onAttachedToBottom?.call();

    animatingToBottom = true;

    controller
        .animateTo(controller.position.minScrollExtent,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutExpo)
        .then((_) {
      if (!mounted) return;
      setState(() {
        // Vommet issue 726: after a long scroll back, rows that grew since
        // they were laid out (pictures, previews) leave the history list's
        // offsets stale. At offset 0 Flutter fixes them one row per layout,
        // moving the view up each time, so the jump stopped short of the
        // newest message. A fresh list lays out from the newest row.
        centerKey = GlobalKey();
        controller.jumpTo(0);
        animatingToBottom = false;
      });
    });

    setState(() {
      recentItemsCount = 0;
    });
  }

  /// Vommet: the live timeline [jumpToLatest] loaded, until the chat hands it
  /// down as [RoomTimelineWidgetView.timeline].
  Timeline? liveTimeline;
  bool loadingLatest = false;

  // Vommet: a timeline opened around an older message (after a jump, or with
  // "open rooms at last read message") only holds the pages near it, so its
  // bottom isn't the room's newest message: newer pages kept loading and
  // "Jump to latest" needed a second click. Load a live timeline first, as
  // jumpToEvent does for events it hasn't loaded.
  void jumpToLatest() async {
    if (loadingLatest) return;
    var current = liveTimeline ?? widget.timeline;
    if (current.canLoadFuture && !widget.isThreadTimeline) {
      setState(() {
        loading = true;
        loadingLatest = true;
      });
      try {
        var live = await current.room.getTimeline();
        liveTimeline = live;
        EventBus.liveTimelineLoaded.add(live);
      } catch (e, s) {
        Log.onError(e, s, content: "Failed to load the latest messages");
      }
      if (!mounted) return;
      setState(() {
        loading = false;
        loadingLatest = false;
      });
    }

    animateAndSnapToBottom();
  }

  void eventHovered(String eventId) {
    var key = eventKeys.firstWhere(
      (element) => element.$2 == eventId,
    );

    assert(eventId == key.$2);

    var state = key.$1.currentState;

    if (state is SelectableEventViewWidget) {
      var selectable = state as SelectableEventViewWidget;

      // Vommet issue 741: in a picture mosaic the menu follows the picture
      // under the pointer.
      final entry = state is TimelineViewEntryState ? state : null;
      final event = entry?.menuEvent ?? timeline.tryGetEvent(eventId)!;
      if (selectable != selectedEventView ||
          event.eventId != selectedMenuEventId) {
        if (selectable != selectedEventView) {
          deselectEvent();

          selectable.select(selectedEventLayerLink);
          selectedEventView = selectable;
        }
        selectedMenuEventId = event.eventId;

        var overlayState = overlayKey.currentState as TimelineOverlayState?;
        overlayState?.setMenu(TimelineEventMenu(
          timeline: timeline,
          context: context,
          isThreadTimeline: widget.isThreadTimeline,
          event: event,
          deleteTogether: entry?.deleteTogether,
          reactionTarget: entry?.menuReactionTarget,
          onReactionPicking: entry?.onMenuReactionPicking,
          selectTogether: entry?.shownEventIds,
          mosaicEvents: entry?.mosaicEvents,
          setEditingEvent: (event) => widget.setEditingEvent?.call(event),
          setReplyingEvent: (event) => widget.setReplyingEvent?.call(event),
        ));
      }
    } else {
      Log.w("Failed to get selectable state");
    }
  }

  void deselectEvent() {
    var overlayState = overlayKey.currentState as TimelineOverlayState?;
    overlayState?.clearSelection();

    selectedEventView?.deselect();
    selectedEventView = null;
    selectedMenuEventId = null;
  }

  @override
  Widget build(BuildContext context) {
    syncKeysWithTimeline();
    TimelineKeyboardScroll.maybeOf(context)
        ?.attach(() => controller, animateAndSnapToBottom);
    return Material(
      color: Colors.transparent,
      child: MouseRegion(
        onExit: (_) => deselectEvent(),
        child: ClipRect(
          child: Stack(
            key: stackKey,
            children: [
              Offstage(
                offstage: firstFrame,
                child: CustomScrollView(
                  key: firstFrame ? firstFrameScrollViewKey : scrollViewKey,
                  controller: controller,
                  reverse: true,
                  center: centerKey,
                  slivers: <Widget>[
                    if (isLoadingFuture)
                      SliverList(
                          delegate: SliverChildBuilderDelegate(childCount: 1,
                              (BuildContext context, int index) {
                        return const SizedBox(
                          height: 200,
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      })),
                    // The slivers are split into recent and history events and
                    // are rendered separately. This prevents the timeline from
                    // jumping around and allows jumping to specific indices
                    // with more reliability.
                    SliverList(
                      key: recentItemsKey,
                      // Recent Items
                      delegate: SliverChildBuilderDelegate(
                        childCount: recentItemsCount,
                        addAutomaticKeepAlives: false,
                        (BuildContext context, int sliverIndex) {
                          int timelineIndex =
                              recentItemsCount - sliverIndex - 1;
                          numBuilds += 1;

                          var key;

                          key = eventKeys[timelineIndex];

                          assert(
                              key.$2 == timeline.events[timelineIndex].eventId);

                          return Container(
                            alignment: Alignment.center,
                            color: preferences.developerMode.value &&
                                    BuildConfig.DEBUG
                                ? Colors.blue[200 + sliverIndex % 4 * 100]!
                                    .withAlpha(30)
                                : null,
                            child: TimelineViewEntry(
                                key: key.$1,
                                timeline: timeline,
                                onEventHovered: eventHovered,
                                canCollapse: true,
                                setEditingEvent: widget.setEditingEvent,
                                setReplyingEvent: widget.setReplyingEvent,
                                isThreadTimeline: widget.isThreadTimeline,
                                highlightedEventId: highlightedEventId,
                                lastReadEventId: lastReadEventId,
                                previewMedia:
                                    widget.timeline.room.shouldPreviewMedia,
                                jumpToEvent: jumpToEvent,
                                initialIndex: timelineIndex),
                          );
                        },
                        findChildIndexCallback: (key) {
                          var timelineIndex = eventKeys
                              .indexWhere((element) => element.$1 == key);
                          if (timelineIndex == -1) {
                            Log.w(
                                "Failed to get timeline index for key: $timelineIndex");
                            return null;
                          }

                          return recentItemsCount - timelineIndex - 1;
                        },
                      ),
                    ),
                    SliverList(
                      key: centerKey,
                      // History Items
                      delegate: SliverChildBuilderDelegate(
                        addAutomaticKeepAlives: false,
                        childCount: historyItemsCount,
                        (BuildContext context, int sliverIndex) {
                          numBuilds += 1;
                          // ignore: avoid_print
                          var timelineIndex = recentItemsCount + sliverIndex;

                          var key;

                          key = eventKeys[timelineIndex];

                          assert(
                              key.$2 == timeline.events[timelineIndex].eventId);

                          return Container(
                            alignment: Alignment.center,
                            color: preferences.developerMode.value &&
                                    BuildConfig.DEBUG
                                ? Colors.red[200 + sliverIndex % 4 * 100]!
                                    .withAlpha(30)
                                : null,
                            child: TimelineViewEntry(
                                key: key.$1,
                                onEventHovered: eventHovered,
                                timeline: timeline,
                                canCollapse: true,
                                setEditingEvent: widget.setEditingEvent,
                                setReplyingEvent: widget.setReplyingEvent,
                                isThreadTimeline: widget.isThreadTimeline,
                                highlightedEventId: highlightedEventId,
                                previewMedia:
                                    widget.timeline.room.shouldPreviewMedia,
                                lastReadEventId: lastReadEventId,
                                jumpToEvent: jumpToEvent,
                                initialIndex: timelineIndex),
                          );
                        },
                        findChildIndexCallback: (key) {
                          var timelineIndex = eventKeys
                              .indexWhere((element) => element.$1 == key);
                          if (timelineIndex == -1) {
                            Log.w(
                                "Failed to get timeline index for key: $timelineIndex");
                            return null;
                          }

                          return timelineIndex - recentItemsCount;
                        },
                      ),
                    ),
                    if (historyPaused &&
                        !isLoadingHistory &&
                        timeline.canLoadHistory)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              tiamat.Text.labelLow(labelTimelineHistoryPaused),
                              const SizedBox(height: 10),
                              tiamat.Button.secondary(
                                text: promptTimelineLoadOlderMessages,
                                onTap: resumeHistory,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (isLoadingHistory)
                      SliverList(
                          delegate: SliverChildBuilderDelegate(childCount: 1,
                              (BuildContext context, int index) {
                        return const SizedBox(
                          height: 200,
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      })),
                    // Vommet: at the very start of a room that continues an
                    // older one, a link back to it.
                    if (!isLoadingHistory &&
                        !timeline.canLoadHistory &&
                        !widget.isThreadTimeline &&
                        timeline.room.replacement?.predecessor != null)
                      SliverToBoxAdapter(
                          child: RoomPredecessorBanner(timeline.room)),
                  ],
                ),
              ),
              TimelineOverlay(
                  key: overlayKey,
                  showMessageMenu: MediaQuery.of(context).desktop,
                  jumpToLatest: jumpToLatest,
                  jumpToTarget: jumpToTarget,
                  markTargetsSeen: markTargetsSeen,
                  onScrolled: (event) {
                    controller.jumpTo(controller.offset - event.scrollDelta.dy);
                  },
                  link: selectedEventLayerLink),
              if (highlightedEventOffstageIndex != null &&
                  highlightedEventOffstageKey != null)
                Offstage(
                  offstage: true,
                  child: Column(
                    children: [
                      Container(
                        color: Colors.red,
                        child: TimelineViewEntry(
                          key: highlightedEventOffstageKey,
                          timeline: timeline,
                          canCollapse: true,
                          isThreadTimeline: widget.isThreadTimeline,
                          initialIndex: highlightedEventOffstageIndex!,
                        ),
                      ),
                    ],
                  ),
                ),
              if (loading)
                Container(
                    color: Colors.black.withAlpha(50),
                    child: const Center(child: CircularProgressIndicator()))
            ],
          ),
        ),
      ),
    );
  }

  void jumpToEvent(String eventId, {bool highlight = true}) async {
    // Clear the previous highlight fully, id included: entries re-derive it
    // from highlightedEventId, and a jump to an event that can't be found
    // returns early without setting a new one.
    if (highlight) clearHighlight();

    int index = timeline.events.indexWhere((event) => event.eventId == eventId);
    if (index == -1) {
      setState(() {
        loading = true;
      });
      // Vommet Deep Search: a far jump loads the message's /context; give up
      // after a while with an error instead of spinning forever.
      Timeline? newTimeline;
      try {
        newTimeline = await timeline.room
            .getTimeline(contextEventId: eventId)
            .timeout(jumpContextTimeout);
      } catch (e, s) {
        Log.onError(e, s, content: "Failed to load a message to jump to");
      }

      index =
          newTimeline?.events.indexWhere((event) => event.eventId == eventId) ??
              -1;

      if (newTimeline == null || index == -1) {
        if (!mounted) return;
        setState(() {
          loading = false;
        });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text(newTimeline == null
                ? jumpContextFailed
                : jumpContextNotFound)));
        return;
      }
      if (!mounted) return;

      final loaded = newTimeline;
      setState(() {
        initFromTimeline(loaded);
      });
    }

    // A picture inside a media mosaic draws nothing; the mosaic is drawn
    // (and highlighted) by its oldest post. Vommet issue 894: the
    // highlight keeps the picture's own id, so the mosaic rings just it.
    final jumpedEventId = timeline.events[index].eventId;
    index = mosaicRootIndexOf(index);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      var key = eventKeys[index].$1;
      final state = key.currentState;

      if (highlight && state is TimelineViewEntryState) {
        state.setHighlighted(true);
        highlightedEventState = state;
      }

      var boundsSize = stackKey.globalPaintBounds?.height;
      var offset = 0.0;
      if (boundsSize != null) {
        offset = -(boundsSize / 2);
      }

      final eventHeight =
          highlightedEventOffstageKey?.globalPaintBounds?.height;
      if (eventHeight != null) {
        offset += eventHeight / 2;
      }

      controller.animateTo(offset,
          duration: const Duration(milliseconds: 300),
          curve: Easing.emphasizedDecelerate);

      if (mounted) {
        setState(() {
          highlightedEventOffstageIndex = null;
          highlightedEventOffstageKey = null;
        });
      }
    });

    setState(() {
      recentItemsCount = index;
      if (highlight) {
        highlightedEventId = jumpedEventId;
        highlightedEventOffstageIndex = index;
        highlightedEventOffstageKey = GlobalKey();
      }
      loading = false;
    });

    if (highlight) {
      // Another jump may have started a timer while this one awaited the
      // timeline; this jump's highlight is the one that counts.
      highlightClearTimer?.cancel();
      highlightClearTimer = Timer(highlightDuration, clearHighlight);
    }
  }

  void clearHighlight() {
    highlightClearTimer?.cancel();
    highlightClearTimer = null;
    if (!mounted) return;

    if (highlightedEventState?.mounted == true) {
      highlightedEventState!.setHighlighted(false);
    }

    setState(() {
      highlightedEventState = null;
      // Entries re-derive their highlight from this id when they rebuild.
      highlightedEventId = null;
    });
  }

  void onLoadingStatusChanged(void event) {
    setState(() {
      isLoadingFuture = timeline.isLoadingFuture;
      isLoadingHistory = timeline.isLoadingHistory;
    });
  }

  void onReadReceiptUpdated(String event) {
    var key = eventKeys.firstWhereOrNull(
      (element) => element.$2 == event,
    );

    if (key == null) return;

    assert(event == key.$2);

    var state = key.$1.currentState;

    var index = timeline.events.indexWhere((i) => i.eventId == event);

    if (index == -1) {
      Log.w("Could not find the event in the timeline view");
    }

    if (state is TimelineEventViewWidget) {
      (state as TimelineEventViewWidget).update(index);
    } else {
      Log.w("Failed to get state");
    }
  }
}

extension GlobalKeyExtension on GlobalKey {
  Rect? get globalPaintBounds {
    final renderObject = currentContext?.findRenderObject();
    final translation = renderObject?.getTransformTo(null).getTranslation();
    if (translation != null && renderObject?.paintBounds != null) {
      final offset = Offset(translation.x, translation.y);
      return renderObject!.paintBounds.shift(offset);
    } else {
      return null;
    }
  }
}
