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

/// Vommet issue 1077: follow or unfollow a thread. Shown in the open
/// thread's corner as "Follow" / "Following" and in a message's menu.
class ThreadFollowButton extends StatefulWidget {
  const ThreadFollowButton({
    required this.room,
    required this.rootId,
    super.key,
  });
  final Room room;
  final String rootId;

  static String get labelFollow => Intl.message(
        "Follow",
        name: "threadFollowButtonFollow",
        desc: "Button in an open thread: follow this thread",
      );

  static String get labelFollowing => Intl.message(
        "Following",
        name: "threadFollowButtonFollowing",
        desc:
            "Button in an open thread that you follow; tapping it unfollows the thread",
      );

  static String get tooltipFollow => Intl.message(
        "Follow this thread",
        name: "threadFollowButtonTooltipFollow",
        desc: "Tooltip on the Follow button of a thread you don't follow",
      );

  static String get tooltipUnfollow => Intl.message(
        "Unfollow this thread",
        name: "threadFollowButtonTooltipUnfollow",
        desc: "Tooltip on the Following button of a thread you follow",
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
    final scheme = Theme.of(context).colorScheme;
    final style = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      shape: const StadiumBorder(),
      backgroundColor: followed
          ? scheme.primaryContainer
          : scheme.surfaceContainerHigh.withAlpha(230),
      foregroundColor:
          followed ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      side: BorderSide(color: followed ? scheme.primary : scheme.outline),
    );
    return Tooltip(
      message: followed
          ? ThreadFollowButton.tooltipUnfollow
          : ThreadFollowButton.tooltipFollow,
      child: OutlinedButton.icon(
        key: const ValueKey("thread-follow-button"),
        style: style,
        onPressed: () => unawaited(_toggle()),
        icon: Icon(
          followed
              ? Icons.notifications_active
              : Icons.notifications_none_outlined,
          size: 18,
        ),
        label: Text(
          followed
              ? ThreadFollowButton.labelFollowing
              : ThreadFollowButton.labelFollow,
        ),
      ),
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
