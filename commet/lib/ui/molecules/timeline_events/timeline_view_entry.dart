import 'package:commet/client/client.dart';
import 'package:commet/utils/timeline_selection.dart';
import 'package:commet/ui/molecules/timeline_events/media_group_member.dart';
import 'package:commet/ui/molecules/timeline_events/media_mosaic.dart';
import 'package:commet/utils/media_group.dart';
import 'package:commet/client/components/polls/poll_component.dart';
import 'package:commet/client/components/read_receipts/read_receipt_component.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_create_room.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_related.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_emote.dart';
import 'package:commet/client/timeline_events/timeline_event_encrypted.dart';
import 'package:commet/client/timeline_events/timeline_event_generic.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_poll_relation.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/diagnostic/benchmark_values.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/emoji_widget.dart';
import 'package:commet/ui/organisms/user_profile/user_profile.dart';
import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_generic.dart';
import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_poll.dart';
import 'package:commet/ui/molecules/timeline_events/deleted_message_placeholder.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_date_time_marker.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu_dialog.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:commet/ui/organisms/message_selection/message_selection_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/atoms/text.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_tombstone.dart';

class TimelineViewEntry extends StatefulWidget {
  const TimelineViewEntry(
      {required this.timeline,
      required this.initialIndex,
      this.onEventHovered,
      this.setEditingEvent,
      this.setReplyingEvent,
      this.jumpToEvent,
      this.showDetailed = false,
      this.singleEvent = false,
      this.isThreadTimeline = false,
      this.previewMedia = false,
      this.lastReadEventId,
      this.highlightedEventId,
      this.canCollapse = false,
      super.key});
  final Timeline timeline;
  final int initialIndex;
  final Function(String eventId)? onEventHovered;
  final Function(TimelineEvent? event)? setReplyingEvent;
  final Function(TimelineEvent? event)? setEditingEvent;
  final Function(String eventId, {bool highlight})? jumpToEvent;
  final bool showDetailed;
  final bool isThreadTimeline;
  final bool canCollapse;
  final String? highlightedEventId;
  final String? lastReadEventId;
  final bool previewMedia;

  // Should be true if we are showing this event on its own, and not as part of a timeline
  final bool singleEvent;

  @override
  State<TimelineViewEntry> createState() => TimelineViewEntryState();
}

// This enum exists because we need to know which type of message to render
// But if we try to check the actual type of the event during build e.g: (`event is TimelineEventMessage`)
// It causes extra widget rebuilds, so we check type only during the event update and store it with this enum
// I thought maybe if we override hashcode of TimelineEventBase it would allow us to just check the type
// But it didnt. I dont know if there is a way to fix that
enum TimelineEventWidgetDisplayType {
  message,
  generic,
  emote,
  roomCreate,
  poll,
  hidden,
  // Vommet issue 306: a deleted message, shown as a placeholder row.
  deleted,
}

enum TimelineEventWidgetCollapseType {
  root,
  child,
}

class TimelineViewEntryState extends State<TimelineViewEntry>
    implements TimelineEventViewWidget, SelectableEventViewWidget {
  String get timelineCopySelection => Intl.message("Copy selection",
      name: "timelineCopySelection",
      desc: "Message context menu in the timeline: copies the selected text");

  String get timelineCopyMessages => Intl.message("Copy messages",
      name: "timelineCopyMessages",
      desc:
          "Message context menu in the timeline: placeholder label for the item that copies the ticked messages");

  String timelineCopyMessageCount(int count) => Intl.plural(count,
      one: "Copy 1 message",
      other: "Copy $count messages",
      args: [count],
      name: "timelineCopyMessageCount",
      desc:
          "Message context menu in the timeline: copies the ticked messages while selecting several");

  late String eventId;
  late TimelineEventStatus status;

  // Note that this index is only reliable on builds - if an item is inserted in to the list, this index will be out of sync until its updated.
  // If you need to get the event which this widget represents, use the ID
  late int index;

  GlobalKey eventKey = GlobalKey();

  bool selected = false;
  bool isThreadReply = false;
  bool highlighted = false;
  bool mentionsMe = false;
  String? _pushHighlightKey;
  bool _pushHighlight = false;
  bool redacted = false;

  TimelineEventWidgetCollapseType? collapse = null;

  // Media mosaic membership (see media_group.dart). Children render nothing;
  // the root renders the whole group.
  MediaGroupPosition mediaGroup = MediaGroupPosition.none;

  // The root's members by event id: their indices shift whenever an event is
  // added or removed below them, and the root isn't always refreshed then.
  List<String> mediaGroupEventIds = const [];

  TimelineEventWidgetDisplayType _widgetType =
      TimelineEventWidgetDisplayType.hidden;
  LayerLink? timelineLayerLink;

  late DateTime time;
  bool showDateSeperator = false;
  bool showUnreadMarker = false;

  ThreadsComponent? threads;
  PollComponent? polls;

  List<String> readReceipts = [];

  String get labelTimelineNewMessagesMarker => Intl.message("New messages",
      desc: "Text that is shown below the last read message",
      name: "labelTimelineNewMessagesMarker");

  @override
  void initState() {
    threads = widget.timeline.room.client.getComponent<ThreadsComponent>();
    polls = widget.timeline.client.getComponent<PollComponent>();

    loadState(widget.initialIndex);
    super.initState();
  }

  @override
  void didUpdateWidget(covariant TimelineViewEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The jumped-to highlight times out by clearing highlightedEventId; an
    // entry built while it was set (scrolled back into view) must follow.
    if (oldWidget.highlightedEventId != widget.highlightedEventId) {
      highlighted = eventId == widget.highlightedEventId;
    }
  }

  void loadState(int eventIndex) {
    var event = widget.timeline.events[eventIndex];
    // Vommet issue 306: a deleted message with a placeholder row isn't
    // hidden; other deleted events are.
    redacted = widget.timeline.isEventRedacted(event) &&
        !showsDeletedPlaceholder(widget.timeline, event);

    // Vommet: rechecked on every update. A file sent in a thread starts as an
    // upload placeholder; the server's copy replaces it at the same index,
    // and checking only once left the picture in the main timeline until the
    // room was reopened (Vommet issue 301).
    isThreadReply =
        threads?.isEventInResponseToThread(event, widget.timeline) ?? false;

    var receipts = widget.timeline.room
        .getComponent<ReadReceiptComponent>()
        ?.getReceipts(event);
    if (receipts != null) {
      readReceipts = receipts;
    }

    eventId = event.eventId;
    status = event.status;
    index = eventIndex;
    time = event.originServerTs;

    _widgetType = displayTypeOf(event);

    bool isCollapsible = false;
    bool isPrevCollapsible = false;
    bool isNextCollapsible = false;

    isCollapsible = isEventTypeCollapsible(_widgetType);

    if (widget.timeline.events.length > eventIndex + 1) {
      var prevEvent = widget.timeline.events[eventIndex + 1];
      var prevEventType = displayTypeOf(prevEvent);

      isPrevCollapsible = isEventTypeCollapsible(prevEventType);
    }

    if (eventIndex > 0) {
      var nextEvent = widget.timeline.events[eventIndex - 1];
      var nextEventType = displayTypeOf(nextEvent);
      isNextCollapsible = isEventTypeCollapsible(nextEventType);
    }

    // Vommet: recomputed on every update; an event that stops being
    // collapsible (e.g. a blocked user's message after unblocking) would
    // otherwise stay collapsed and draw nothing.
    collapse = null;
    if (preferences.collapseStateEvents.value) {
      if (isCollapsible && isNextCollapsible && !isPrevCollapsible) {
        collapse = TimelineEventWidgetCollapseType.root;
      }

      if (isCollapsible && isPrevCollapsible) {
        collapse = TimelineEventWidgetCollapseType.child;
      }
    }

    // Only where pictures are shown inline: a mosaic always loads its
    // pictures, so it must not bypass "don't preview media" rooms.
    mediaGroup = preferences.groupConsecutiveMedia.value &&
            !widget.singleEvent &&
            widget.previewMedia
        ? mediaGroupPositionAt(eventIndex, widget.timeline,
            threads: threads, isThreadTimeline: widget.isThreadTimeline)
        : MediaGroupPosition.none;
    mediaGroupEventIds = [
      for (final i in mediaGroup.members)
        if (i < widget.timeline.events.length) widget.timeline.events[i].eventId
    ];

    showDateSeperator = shouldEventShowDate(eventIndex);
    showUnreadMarker = shouldEventShowUnreadMarker(eventIndex);
    highlighted = event.eventId == widget.highlightedEventId;
    mentionsMe = shouldHighlightAsMention(event);
  }

  /// Messages that mention the user, or reply to one of their messages.
  bool shouldHighlightAsMention(TimelineEvent event) {
    if (_widgetType != TimelineEventWidgetDisplayType.message &&
        _widgetType != TimelineEventWidgetDisplayType.emote) {
      return false;
    }

    final room = widget.timeline.room;
    final me = room.client.self?.identifier;
    if (me == null || event.senderId == me) return false;

    // Push-rule evaluation counts the room's members, so only redo it when
    // the entry shows a different event or the event got decrypted.
    final key = "${event.eventId}/${event.runtimeType}";
    if (_pushHighlightKey != key) {
      _pushHighlightKey = key;
      _pushHighlight = room.eventMentionsMe(event);
    }
    if (_pushHighlight) return true;

    // Replies from clients that don't add the replied-to sender to m.mentions.
    if (event case TimelineEventFeatureRelated related
        when related.relationshipType == EventRelationshipType.reply) {
      final targetId = related.relatedEventId;
      if (targetId == null) return false;
      return widget.timeline.tryGetEvent(targetId)?.senderId == me;
    }

    return false;
  }

  static bool isEventTypeCollapsible(TimelineEventWidgetDisplayType eventType) {
    const collapsibleTypes = [
      TimelineEventWidgetDisplayType.generic,
      TimelineEventWidgetDisplayType.hidden
    ];

    return collapsibleTypes.contains(eventType);
  }

  /// Like [eventToDisplayType], but a deleted event is hidden, or a
  /// placeholder row when it was a message (Vommet issue 306). Hidden deleted
  /// events fold into a run of collapsed server events; placeholders end it.
  TimelineEventWidgetDisplayType displayTypeOf(TimelineEvent event) {
    if (widget.timeline.isEventRedacted(event)) {
      return showsDeletedPlaceholder(widget.timeline, event)
          ? TimelineEventWidgetDisplayType.deleted
          : TimelineEventWidgetDisplayType.hidden;
    }
    return eventToDisplayType(event, polls: polls);
  }

  static TimelineEventWidgetDisplayType eventToDisplayType(TimelineEvent event,
      {PollComponent? polls}) {
    if (event is TimelineEventMessage ||
        event is TimelineEventSticker ||
        event is TimelineEventEncrypted) {
      return TimelineEventWidgetDisplayType.message;
    }

    // Vommet: a tombstone is always shown, like the room's creation.
    if (event is MatrixTimelineEventCreateRoom ||
        event is MatrixTimelineEventTombstone) {
      return TimelineEventWidgetDisplayType.roomCreate;
    }

    if (event is TimelineEventEmote) {
      return TimelineEventWidgetDisplayType.emote;
    }

    if (event is TimelineEventGeneric) {
      return TimelineEventWidgetDisplayType.generic;
    }

    if (polls?.isPollEvent(event) == true) {
      return TimelineEventWidgetDisplayType.poll;
    }

    // Vommet issue 494: a vote or a poll's end only counts towards its poll,
    // even one that failed to send.
    if (event is TimelineEventPollRelation) {
      return TimelineEventWidgetDisplayType.hidden;
    }

    if (event.status == TimelineEventStatus.error) {
      return TimelineEventWidgetDisplayType.generic;
    }

    return TimelineEventWidgetDisplayType.hidden;
  }

  bool shouldEventShowDate(int index) {
    if (widget.singleEvent) {
      return false;
    }

    if (widget.isThreadTimeline) {
      if (threads?.isHeadOfThread(
              widget.timeline.events[index], widget.timeline) ==
          true) {
        return true;
      }
    }

    var offsetIndex = index + 1;

    if (widget.timeline.events.length <= offsetIndex) {
      return false;
    }

    var event = widget.timeline.events[index];
    if (event is! TimelineEventMessage &&
        event is! TimelineEventEmote &&
        event is! TimelineEventSticker) {
      return false;
    }

    if (widget.timeline.events[index].originServerTs.toLocal().day !=
        widget.timeline.events[offsetIndex].originServerTs.toLocal().day) {
      return true;
    }

    if (widget.timeline.events[index].originServerTs
            .difference(widget.timeline.events[offsetIndex].originServerTs)
            .inHours >
        2) return true;

    return false;
  }

  bool shouldEventShowUnreadMarker(int index) {
    return eventId == widget.lastReadEventId;
  }

  @override
  void update(int newIndex) {
    index = newIndex;
    setState(() {
      loadState(newIndex);
    });

    if (eventKey.currentState is TimelineEventViewWidget) {
      (eventKey.currentState as TimelineEventViewWidget).update(newIndex);
    } else {
      Log.w("Failed to get state from event key");
    }
  }

  String selectionMenuCopy(int count) => Intl.plural(count,
      one: "Copy 1 message",
      other: "Copy $count messages",
      args: [count],
      name: "selectionMenuCopy",
      desc:
          "Right-click menu of a ticked message while selecting several: copies them all");

  String selectionMenuForward(int count) => Intl.plural(count,
      one: "Forward 1 message",
      other: "Forward $count messages",
      args: [count],
      name: "selectionMenuForward",
      desc:
          "Right-click menu of a ticked message while selecting several: forwards them all");

  String selectionMenuDelete(int count) => Intl.plural(count,
      one: "Delete 1 message",
      other: "Delete $count messages",
      args: [count],
      name: "selectionMenuDelete",
      desc:
          "Right-click menu of a ticked message while selecting several: deletes them all");

  String get selectionMenuUnselect => Intl.message("Unselect",
      name: "selectionMenuUnselect",
      desc:
          "Right-click menu of a ticked message while selecting several: unticks this one");

  String get selectionMenuClear => Intl.message("Clear selection",
      name: "selectionMenuClear",
      desc:
          "Right-click menu of a ticked message while selecting several: stops selecting");

  /// Vommet: ticks this message (starting a selection if none) on a long
  /// press on desktop; false when it can't be ticked, so the menu opens.
  void openMobileMenu() {
    var event = widget.timeline.tryGetEvent(eventId);
    if (event == null) {
      return;
    }

    showModalBottomSheet(
        showDragHandle: true,
        isScrollControlled: true,
        elevation: 0,
        context: context,
        builder: (context) => TimelineEventMenuDialog(
              event: event,
              timeline: widget.timeline,
              menu: TimelineEventMenu(
                timeline: widget.timeline,
                isThreadTimeline: widget.isThreadTimeline,
                event: event,
                context: context,
                setEditingEvent: widget.setEditingEvent,
                setReplyingEvent: widget.setReplyingEvent,
                selection: MessageSelectionScope.maybeOf(this.context),
                onActionFinished: () => Navigator.of(context).pop(),
              ),
            ));
  }

  /// Vommet: whether a long press on this message starts (or toggles) the
  /// message selection.
  bool get selectsOnLongPress {
    final selection = MessageSelectionScope.maybeOf(context);
    final event = widget.timeline.tryGetEvent(eventId);
    return MessageSelection.enabled &&
        selection != null &&
        !selection.busy &&
        !widget.singleEvent &&
        !widget.isThreadTimeline &&
        event != null &&
        MessageSelection.canTick(event, widget.timeline);
  }

  bool selectOnLongPress() {
    final selection = MessageSelectionScope.maybeOf(context);
    if (selection == null || !selectsOnLongPress) return false;
    if (selection.active) {
      selection.toggle([eventId]);
    } else {
      selection.start([eventId]);
    }
    return true;
  }

  /// Vommet: the right-click menu of a ticked message while selecting:
  /// copy, forward or delete every ticked message. Null otherwise, for the
  /// message's own menu.
  List<ContextMenuItem>? selectionMenuItems() {
    final selection = MessageSelectionScope.maybeOf(context);
    if (selection == null || !selection.isTicked([eventId])) return null;
    final ticked = selection.ticked.length;
    final forwardable = selection.forwardableEvents().length;
    final deletable = selection.deletableCount;
    return [
      ContextMenuItem(
          text: selectionMenuCopy(ticked),
          icon: Icons.copy,
          onPressed: selection.copy),
      if (MatrixForwarding.enabled && forwardable > 0)
        ContextMenuItem(
            text: selectionMenuForward(forwardable),
            icon: Icons.shortcut,
            onPressed: () => selection.forward(context)),
      if (deletable > 0)
        ContextMenuItem(
            text: selectionMenuDelete(deletable),
            icon: Icons.delete,
            color: Theme.of(context).colorScheme.error,
            onPressed: () => selection.delete(context)),
      ContextMenuItem(
          text: selectionMenuUnselect,
          icon: Icons.remove_circle_outline,
          onPressed: () => selection.toggle([eventId])),
      ContextMenuItem(
          text: selectionMenuClear,
          icon: Icons.close,
          onPressed: selection.exit),
    ];
  }

  @override
  Widget build(BuildContext context) {
    BenchmarkValues.numTimelineEventsBuilt += 1;

    if (redacted) return Container();

    if (mediaGroup.role == MediaGroupRole.child) return Container();

    if (widget.canCollapse && collapse == TimelineEventWidgetCollapseType.child)
      return Container();

    if (collapse != null &&
        preferences.showStateEvents.value == false &&
        preferences.developerMode.value == false) return Container();

    var result = buildEvent();

    if (collapse == TimelineEventWidgetCollapseType.root &&
        widget.canCollapse) {
      int endIndex = index;

      List<String> bodies = List.empty(growable: true);

      var count = 0;
      const maxBodies = 3;

      // Vommet: the event that counted, shown alone if it's the only one.
      int visibleIndex = index;
      int counted = 0;

      for (int i = index; i > 0; i--) {
        var event = widget.timeline.events[i];
        var type = displayTypeOf(event);
        if (!isEventTypeCollapsible(type)) {
          break;
        }

        if (type != TimelineEventWidgetDisplayType.hidden ||
            preferences.hiddenEventsShown) {
          count += 1;
          if (bodies.length < maxBodies) {
            bodies.add(event.plainTextBody);
          }
        }

        if (count > counted) {
          counted = count;
          visibleIndex = i;
        }

        endIndex = i;
      }

      if (count == 0) return Container();

      // Vommet: one visible event (the rest hidden) is shown as it is, not
      // behind a dropdown that only repeats it.
      if (count == 1) {
        return TimelineViewEntry(
          key: ValueKey(widget.timeline.events[visibleIndex].eventId),
          timeline: widget.timeline,
          initialIndex: visibleIndex,
          canCollapse: false,
          highlightedEventId: widget.highlightedEventId,
          onEventHovered: widget.onEventHovered,
        );
      }

      var diff = count - bodies.length;
      var text = bodies.join(", ");
      if (diff > 0) {
        text += " and $diff more";
      }
      return ExpansionTile(
        title: Padding(
          padding: const EdgeInsets.fromLTRB(52, 0, 0, 0),
          child: tiamat.Text.labelLow(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        children: [
          Column(
            children: [
              for (int i = index; i >= endIndex; i--)
                TimelineViewEntry(
                  timeline: widget.timeline,
                  initialIndex: i,
                  canCollapse: false,
                  highlightedEventId: widget.highlightedEventId,
                  onEventHovered: widget.onEventHovered,
                )
            ],
          )
        ],
      );
    }

    if (result == null) {
      return Container();
    }

    if (status == TimelineEventStatus.sending ||
        status == TimelineEventStatus.error) {
      result = Opacity(
        opacity: 0.5,
        child: result,
      );
    }

    if (status == TimelineEventStatus.error) {
      result = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Icon(
              Icons.error,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          Expanded(child: result),
        ],
      );
    }

    // Vommet: check circle and tick-on-tap while selecting messages.
    if (!widget.singleEvent && !widget.isThreadTimeline) {
      result = MessageSelectionRow(
          timeline: widget.timeline, eventIds: [eventId], child: result);
    }

    if (MediaQuery.of(context).desktop) {
      result = MouseRegion(
        onEnter: (_) => widget.onEventHovered?.call(eventId),
        child: result,
      );
    }

    if (MediaQuery.of(context).mobile) {
      // Vommet: with "Select several messages" on, a long press selects the
      // message and a tap opens its menu, like Telegram.
      final selects = selectsOnLongPress;
      result = InkWell(
        onTap: selects ? openMobileMenu : null,
        onLongPress: () {
          if (selects && selectOnLongPress()) return;
          openMobileMenu();
        },
        child: result,
      );
    }

    if (MediaQuery.of(context).desktop) {
      var event = widget.timeline.tryGetEvent(eventId);
      if (event != null) {
        var menu = TimelineEventMenu(
            timeline: widget.timeline,
            event: event,
            context: context,
            setEditingEvent: widget.setEditingEvent,
            setReplyingEvent: widget.setReplyingEvent);
        result = AdaptiveContextMenu(items: [
          // Built when the menu opens, so it sees the selection at right-click
          // time; renders nothing when no text is selected.
          tiamat.ContextMenuItem(
            text: timelineCopySelection,
            customBuilder: (context, onClick, {closeMenu}) {
              final selected = TimelineSelection.current.value;
              if (selected == null) return const SizedBox.shrink();
              return tiamat.ContextMenuItem(
                text: timelineCopySelection,
                icon: Icons.content_copy,
              ).build(context, () {
                Clipboard.setData(ClipboardData(text: selected));
                onClick();
              });
            },
          ),
          if (menu.addReactionAction != null)
            ContextMenuItem(
              text: "Add Reaction",
              customBuilder: (context, onClick, {closeMenu}) => Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (var i = 0;
                        i < 3 && i < menu.recentReactions.length;
                        i++)
                      InkWell(
                          onTap: () {
                            widget.timeline.room
                                .addReaction(event, menu.recentReactions[i]);
                            onClick();
                          },
                          child: SizedBox(
                              height: 30,
                              width: 30,
                              child: EmojiWidget(menu.recentReactions[i]))),
                    tiamat.IconButton(
                      icon: Icons.add_reaction,
                      size: 24,
                      onPressed: () {
                        onClick();

                        AdaptiveDialog.show(
                          context,
                          builder: (newContext) {
                            return SizedBox(
                                width: 500,
                                height: 500,
                                child: menu
                                    .addReactionAction!.secondaryMenuBuilder!
                                    .call(
                                  newContext,
                                  () {
                                    Navigator.of(newContext).pop();
                                  },
                                ));
                          },
                        );
                        menu.addReactionAction?.action?.call(context);
                      },
                    )
                  ],
                ),
              ),
            ),
          for (var i in menu.primaryActions)
            ContextMenuItem(
                text: i.name,
                icon: i.icon,
                onPressed: () => i.action?.call(context)),
          for (var i in menu.secondaryActions)
            ContextMenuItem(
                text: i.name,
                icon: i.icon,
                onPressed: () => i.action?.call(context)),
          // Vommet: "Copy N messages" on a ticked message while selecting;
          // built when the menu opens, so it sees the current selection.
          ContextMenuItem(
            text: timelineCopyMessages,
            customBuilder: (context, onClick, {closeMenu}) {
              final selection = MessageSelectionScope.maybeOf(this.context);
              if (selection == null || !selection.isTicked([eventId])) {
                return const SizedBox.shrink();
              }
              return ContextMenuItem(
                text: timelineCopyMessageCount(selection.ticked.length),
                icon: Icons.copy,
              ).build(context, () {
                selection.copy();
                onClick();
              });
            },
          ),
        ], child: result);
        // Vommet: a long left-press starts selecting messages, and a ticked
        // message's menu acts on the whole selection.
        result = (result as AdaptiveContextMenu).withHooks(
            onLongPress: selectOnLongPress, itemsBuilder: selectionMenuItems);
      }
    }

    if (selected) {
      result = Container(
        color: Theme.of(context).hoverColor.withAlpha(5),
        child: result,
      );
    }

    if (mentionsMe && !highlighted) {
      final colors = Theme.of(context).colorScheme;
      // A light background needs a stronger tint to show at all.
      final tint = colors.brightness == Brightness.dark ? 20 : 45;
      result = Container(
        decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colors.tertiary, width: 2)),
            color: colors.tertiary.withAlpha(tint)),
        child: result,
      );
    }

    if (highlighted) {
      result = Container(
        decoration: BoxDecoration(
            border: Border(
                left: BorderSide(
                    color: Theme.of(context).colorScheme.primary, width: 3)),
            color: Theme.of(context).colorScheme.surfaceContainer),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
          child: result,
        ),
      );
    }

    if (timelineLayerLink != null) {
      result = Stack(
        alignment: Alignment.topRight,
        children: [
          CompositedTransformTarget(
              link: timelineLayerLink!, child: const SizedBox()),
          result
        ],
      );
    }

    if (showUnreadMarker) {
      result = Column(children: [
        buildNewMessagesMarker(),
        result,
      ]);
    } else {
      if (showDateSeperator) {
        result = Column(
          children: [TimelineEventDateTimeMarker(time: time), result],
        );
      }
    }

    return result;
  }

  Widget buildNewMessagesMarker() {
    var color = ColorScheme.of(context).primaryContainer;
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 3, 10, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
              child: Divider(
            color: color,
            thickness: 1.0,
          )),
          DecoratedBox(
            decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 15, vertical: 3),
              child: tiamat.Text(
                labelTimelineNewMessagesMarker,
                color: ColorScheme.of(context).primaryContainer,
                type: TextType.labelLow,
              ),
            ),
          ),
          Expanded(
              child: Divider(
            color: color,
            thickness: 1.0,
          )),
        ],
      ),
    );
  }

  Widget? buildEvent() {
    if (redacted) {
      return null;
    }

    if (widget.singleEvent == false &&
        widget.isThreadTimeline == false &&
        isThreadReply) {
      return null;
    }

    if (_widgetType == TimelineEventWidgetDisplayType.message ||
        _widgetType == TimelineEventWidgetDisplayType.deleted)
      return TimelineEventViewMessage(
          key: eventKey,
          timeline: widget.timeline,
          isThreadTimeline: widget.isThreadTimeline,
          detailed: widget.showDetailed || selected,
          onReadReceiptsTapped: onReadReceiptsTapped,
          readReceipts: readReceipts,
          overrideShowSender:
              widget.singleEvent || showDateSeperator || showUnreadMarker,
          jumpToEvent: widget.jumpToEvent,
          previewMedia: widget.previewMedia,
          attachmentsOverride: mediaGroup.role == MediaGroupRole.root
              ? MediaMosaic(
                  timeline: widget.timeline,
                  events: [
                    for (final id in mediaGroupEventIds)
                      if (widget.timeline.tryGetEvent(id) case final event?)
                        event
                  ],
                  isThreadTimeline: widget.isThreadTimeline,
                  setEditingEvent: widget.setEditingEvent,
                  setReplyingEvent: widget.setReplyingEvent,
                )
              : null,
          initialIndex: widget.initialIndex);

    if (_widgetType == TimelineEventWidgetDisplayType.generic &&
        (preferences.showStateEvents.value || preferences.developerMode.value))
      return TimelineEventViewGeneric(
        timeline: widget.timeline,
        initialIndex: widget.initialIndex,
        room: widget.timeline.room,
        readReceipts: readReceipts,
        onReadReceiptsTapped: onReadReceiptsTapped,
        key: eventKey,
      );

    if (_widgetType == TimelineEventWidgetDisplayType.emote ||
        _widgetType == TimelineEventWidgetDisplayType.roomCreate)
      return TimelineEventViewGeneric(
        timeline: widget.timeline,
        initialIndex: widget.initialIndex,
        room: widget.timeline.room,
        readReceipts: readReceipts,
        onReadReceiptsTapped: onReadReceiptsTapped,
        key: eventKey,
      );

    if (_widgetType == TimelineEventWidgetDisplayType.poll) {
      return TimelineEventViewPoll(
        initialIndex: widget.initialIndex,
        timeline: widget.timeline,
        key: eventKey,
      );
    }

    if (!preferences.hiddenEventsShown &&
        _widgetType == TimelineEventWidgetDisplayType.hidden) {
      return null;
    }

    return preferences.hiddenEventsShown
        ? TimelineEventViewGeneric(
            timeline: widget.timeline,
            room: widget.timeline.room,
            initialIndex: widget.initialIndex,
            key: eventKey,
            onReadReceiptsTapped: onReadReceiptsTapped,
            readReceipts: readReceipts,
          )
        : Container(
            key: eventKey,
          );
  }

  @override
  void deselect() {
    if (mounted)
      setState(() {
        selected = false;
        timelineLayerLink = null;
      });
  }

  @override
  void select(LayerLink link) {
    if (mounted)
      setState(() {
        selected = true;
        timelineLayerLink = link;
      });
  }

  void setHighlighted(bool value) {
    if (mounted)
      setState(() {
        highlighted = value;
      });
  }

  onReadReceiptsTapped() {
    AdaptiveDialog.show(context, title: "Read Receipts", builder: (context) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: readReceipts
            .map((i) => UserPanel(
                userId: i,
                client: widget.timeline.client,
                contextRoom: widget.timeline.room,
                // Vommet: close this dialog when the profile opened a
                // direct message (Vommet issue 424).
                onTap: () async {
                  final openedRoom = await UserProfile.show(context,
                      client: widget.timeline.client, userId: i);
                  if (openedRoom == true && context.mounted) {
                    Navigator.of(context).pop();
                  }
                }))
            .toList(),
      );
    });
  }
}
