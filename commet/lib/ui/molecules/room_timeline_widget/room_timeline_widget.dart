import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/utils/timeline_selection.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:commet/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:flutter/material.dart';
import 'package:commet/ui/molecules/room_timeline_widget/chat_on_screen.dart';

class RoomTimelineWidget extends StatefulWidget {
  const RoomTimelineWidget(
      {required this.timeline,
      this.setEditingEvent,
      this.setReplyingEvent,
      this.isThreadTimeline = false,
      this.clearNotifications,
      super.key});
  final Timeline timeline;
  final Function(TimelineEvent? event)? setReplyingEvent;
  final Function(TimelineEvent? event)? setEditingEvent;
  final Function(Room room)? clearNotifications;
  final bool isThreadTimeline;

  @override
  State<RoomTimelineWidget> createState() => _RoomTimelineWidgetState();
}

class _RoomTimelineWidgetState extends State<RoomTimelineWidget>
    with WidgetsBindingObserver {
  GlobalKey timelineViewKey = GlobalKey();

  StreamSubscription? sub;

  // Vommet: while messages are selected the timeline has no text selection,
  // so a drag that turned into message selection stops selecting text.
  MessageSelection? messageSelection;
  bool selectingMessages = false;

  void onMessageSelectionChanged() {
    final active = messageSelection?.active == true;
    if (!mounted || active == selectingMessages) return;
    setState(() => selectingMessages = active);
  }

  @override
  void initState() {
    sub = widget.timeline.onEventAdded.stream.listen(onEventReceived);
    WidgetsBinding.instance.addObserver(this);
    // The room view's selection stays the same for this widget's life.
    messageSelection = MessageSelectionScope.maybeOf(context)
      ?..addListener(onMessageSelectionChanged);
    selectingMessages = messageSelection?.active == true;
    super.initState();
  }

  // Vommet: the chat can hand over a new timeline ("Jump to latest" loads a
  // live one); listen to that one for new messages to mark read.
  @override
  void didUpdateWidget(covariant RoomTimelineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeline != widget.timeline) {
      sub?.cancel();
      sub = widget.timeline.onEventAdded.stream.listen(onEventReceived);
    }
  }

  @override
  void dispose() {
    messageSelection?.removeListener(onMessageSelectionChanged);
    sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    chatOnScreen?.removeListener(onChatVisibilityChanged);
    super.dispose();
  }

  // Vommet issue 408: the phone layout says whether this chat is on screen.
  ValueNotifier<bool>? chatOnScreen;
  bool get isOnScreen => chatOnScreen?.value ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = ChatOnScreen.of(context);
    if (notifier != chatOnScreen) {
      chatOnScreen?.removeListener(onChatVisibilityChanged);
      chatOnScreen = notifier?..addListener(onChatVisibilityChanged);
    }
  }

  void onEventReceived(int index) {
    if (index == 0) {
      var state = timelineViewKey.currentState as RoomTimelineWidgetViewState?;
      if (state?.attachedToBottom == true) {
        markAsRead(widget.timeline.events[index]);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed && isOnScreen) {
      var state = timelineViewKey.currentState as RoomTimelineWidgetViewState?;
      if (state?.attachedToBottom == true) {
        markAsRead(widget.timeline.events.first);
        widget.clearNotifications?.call(widget.timeline.room);
      }
    }

    super.didChangeAppLifecycleState(state);
  }

  Future<void> markAsRead(TimelineEvent event) async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (!isOnScreen) return;

    shownTimeline.markAsRead(event);
  }

  @override
  Widget build(BuildContext context) {
    Widget result = RoomTimelineWidgetView(
      key: timelineViewKey,
      timeline: widget.timeline,
      onAttachedToBottom: onAttachedToBottomOnScreen,
      isThreadTimeline: widget.isThreadTimeline,
      setReplyingEvent: widget.setReplyingEvent,
      setEditingEvent: widget.setEditingEvent,
      markAsRead: markAsRead,
    );

    if (MediaQuery.of(context).desktop && !selectingMessages) {
      result = SelectionArea(
        child: result,
        // Right-click opens the message menu, which offers "Copy selection"
        // from TimelineSelection; Flutter's own toolbar would fight it.
        onSelectionChanged: (content) =>
            TimelineSelection.update(content?.plainText),
        contextMenuBuilder: (context, selectableRegionState) {
          return Container();
        },
      );
    }

    // Vommet experiment: lets the image viewer page through this
    // timeline's pictures and videos.
    result = LightboxGalleryScope(timeline: widget.timeline, child: result);

    return result;
  }

  // Vommet: the view's own timeline, which "Jump to latest" may have just
  // replaced with a live one before the chat hands that one down.
  Timeline get shownTimeline =>
      (timelineViewKey.currentState as RoomTimelineWidgetViewState?)
          ?.timeline ??
      widget.timeline;

  void onAttachedToBottom() {
    var timeline = shownTimeline;
    if (timeline.events.isNotEmpty) {
      markAsRead(timeline.events.first);
      widget.clearNotifications?.call(timeline.room);
    }
  }

  // Vommet issue 408: a chat hidden behind the room list isn't read yet.
  void onAttachedToBottomOnScreen() {
    if (isOnScreen) onAttachedToBottom();
  }

  void onChatVisibilityChanged() {
    if (!isOnScreen) return;
    var state = timelineViewKey.currentState as RoomTimelineWidgetViewState?;
    if (state?.attachedToBottom == true) onAttachedToBottom();
  }
}
