import 'dart:async';

import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The follow bell in the open thread's header.
class ThreadFollowButton extends StatefulWidget {
  const ThreadFollowButton({
    required this.room,
    required this.rootId,
    super.key,
  });
  final Room room;
  final String rootId;

  static String get tooltipFollow => Intl.message(
        "Follow this thread",
        name: "threadFollowButtonTooltipFollow",
        desc: "Tooltip on the follow bell of a thread you don't follow",
      );

  static String get tooltipUnfollow => Intl.message(
        "Unfollow this thread",
        name: "threadFollowButtonTooltipUnfollow",
        desc: "Tooltip on the follow bell of a thread you follow",
      );

  @override
  State<ThreadFollowButton> createState() => _ThreadFollowButtonState();
}

class _ThreadFollowButtonState extends State<ThreadFollowButton> {
  ThreadsComponent? get component =>
      widget.room.client.getComponent<ThreadsComponent>();

  bool? followed;

  @override
  void initState() {
    super.initState();
    final component = this.component;
    if (component == null) return;
    followed = component.isThreadFollowed(
      widget.room,
      widget.rootId,
      root: widget.room.timeline?.tryGetEvent(widget.rootId),
    );
    component.threadFollowsChanged.addListener(_refresh);
    _refresh();
  }

  @override
  void didUpdateWidget(ThreadFollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootId != widget.rootId) _refresh();
  }

  @override
  void dispose() {
    component?.threadFollowsChanged.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final rootId = widget.rootId;
    final value = await component?.loadThreadFollowed(widget.room, rootId);
    if (!mounted || value == null || rootId != widget.rootId) return;
    setState(() => followed = value);
  }

  Future<void> _toggle() async {
    final follow = followed != true;
    setState(() => followed = follow);
    try {
      await component?.setThreadFollowed(widget.room, widget.rootId, follow);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not change a thread's follow");
      if (mounted) setState(() => followed = !follow);
    }
  }

  @override
  Widget build(BuildContext context) {
    final followed = this.followed;
    if (component == null || followed == null) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey("thread-follow-button"),
      isSelected: followed,
      tooltip: followed
          ? ThreadFollowButton.tooltipUnfollow
          : ThreadFollowButton.tooltipFollow,
      style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.padded),
      iconSize: 18,
      onPressed: () => unawaited(_toggle()),
      icon: const Icon(Icons.notifications_none_outlined),
      selectedIcon: const Icon(Icons.notifications_active),
    );
  }
}

/// Vommet issue 1077: "Follow thread" / "Unfollow thread" in the menu of a
/// thread's root (main timeline) or any message in an open thread.
class ThreadFollowMenu {
  static String get promptFollowThread => Intl.message(
        "Follow thread",
        name: "promptFollowThread",
        desc: "Message menu option: follow the thread this message is in",
      );

  static String get promptUnfollowThread => Intl.message(
        "Unfollow thread",
        name: "promptUnfollowThread",
        desc: "Message menu option: unfollow the thread this message is in",
      );

  static TimelineEventMenuEntry? entry(
    Timeline timeline,
    TimelineEvent event,
    void Function()? onActionFinished,
  ) {
    final room = timeline.room;
    final component = room.client.getComponent<ThreadsComponent>();
    if (component == null ||
        event.status != TimelineEventStatus.synced ||
        event.eventId.isEmpty) {
      return null;
    }
    final String rootId;
    final TimelineEvent? root;
    var participated = false;
    if (timeline is MatrixThreadTimeline) {
      rootId = timeline.threadRootId;
      root = timeline.tryGetEvent(rootId);
      final me = room.client.self?.identifier;
      participated = timeline.events.any((e) => e.senderId == me);
    } else if (component.isHeadOfThread(event, timeline)) {
      rootId = event.eventId;
      root = event;
    } else {
      return null;
    }
    final followed = component.isThreadFollowed(
      room,
      rootId,
      root: root,
      participated: participated,
    );
    return TimelineEventMenuEntry(
      name: followed ? promptUnfollowThread : promptFollowThread,
      icon: followed
          ? Icons.notifications_off_outlined
          : Icons.notifications_active_outlined,
      action: (context) {
        onActionFinished?.call();
        unawaited(
          component.setThreadFollowed(room, rootId, !followed).catchError((
            Object e,
            StackTrace s,
          ) {
            Log.onError(e, s, content: "Could not change a thread's follow");
          }),
        );
      },
    );
  }
}
