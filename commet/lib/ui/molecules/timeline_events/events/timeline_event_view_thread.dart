import 'dart:async';

import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_per_message_profile.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/thread_card.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:commet/ui/organisms/room_threads_list/room_threads_list_widget.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: the thread card under a message that started a thread, or, inside
/// the open thread, a "12 replies" divider under its first message.
class TimelineEventViewThread extends StatefulWidget {
  const TimelineEventViewThread(
      {super.key,
      required this.initialIndex,
      required this.timeline,
      required this.component,
      this.inThread = false});

  final int initialIndex;
  final Timeline timeline;
  final ThreadsComponent component;

  /// This message is the first one of the open thread.
  final bool inThread;

  @override
  State<TimelineEventViewThread> createState() =>
      _TimelineEventViewThreadState();
}

class _TimelineEventViewThreadState extends State<TimelineEventViewThread>
    implements TimelineEventViewWidget {
  String? rootId;
  ThreadSummary? summary;
  ThreadPreviewExtras? extras;
  StreamSubscription? _modeSub;
  int _generation = 0;

  ThreadPreviewMode get mode =>
      ThreadPreviewMode.parse(preferences.threadPreviewMode.value);

  @override
  void initState() {
    super.initState();
    _load(widget.initialIndex);
    _modeSub = preferences.threadPreviewMode.onChanged.listen((_) {
      if (!mounted) return;
      setState(() {});
      _loadExtras();
    });
  }

  @override
  void dispose() {
    _modeSub?.cancel();
    super.dispose();
  }

  @override
  void update(int newIndex) {
    setState(() => _load(newIndex));
  }

  void _load(int index) {
    final events = widget.timeline.events;
    if (index < 0 || index >= events.length) return;
    final event = events[index];
    if (event.eventId != rootId) extras = null;
    rootId = event.eventId;
    summary = widget.component.getThreadSummary(event, widget.timeline);
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    final summary = this.summary;
    if (summary == null || widget.inThread) return;
    final generation = ++_generation;
    try {
      final result = await widget.component.loadThreadPreviewExtras(
          widget.timeline.room, summary,
          withFirstReply: mode != ThreadPreviewMode.latest);
      if (!mounted || generation != _generation) return;
      setState(() => extras = result);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not load a thread's preview");
    }
  }

  ThreadCardReply _reply(TimelineEvent event, int maxLines) {
    final room = widget.timeline.room;
    final sender = room.getMemberOrFallback(event.senderId);
    var name = sender.displayName;
    var avatar = sender.avatar;
    var color = sender.defaultColor;
    if (event is TimelineEventFeaturePerMessageProfile) {
      final profile = (event as TimelineEventFeaturePerMessageProfile)
          .getPerMessageProfile(timeline: widget.timeline);
      if (profile != null) {
        if (profile.avatar != null || profile.clearAvatar) {
          avatar = profile.avatar;
        }
        if (profile.hasDisplayName) {
          name = profile.displayName!;
          color = profile.color;
        }
      }
    }
    return ThreadCardReply(
      senderName: name,
      senderColor: color,
      senderAvatar: avatar,
      body: ThreadListTile.bodyOf(event),
      time: TextUtils.timestampToLocalizedTime(event.originServerTs, context),
      maxLines: maxLines,
    );
  }

  void _open() {
    final rootId = this.rootId;
    if (rootId == null) return;
    EventBus.openThread.add((
      widget.timeline.client.identifier,
      widget.timeline.room.identifier,
      rootId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    if (summary == null) return const SizedBox.shrink();
    if (widget.inThread) return _divider(context, summary.replyCount);

    // The newer of what the root carried and what the server said since.
    var latest = summary.latestReply;
    final fetched = extras?.latestReply;
    if (fetched != null &&
        (latest == null ||
            fetched.eventId == latest.eventId ||
            fetched.originServerTs.isAfter(latest.originServerTs))) {
      latest = fetched;
    }
    final first = extras?.firstReply;

    final replies = <ThreadCardReply>[];
    switch (mode) {
      case ThreadPreviewMode.latest:
        if (latest != null) replies.add(_reply(latest, 2));
      case ThreadPreviewMode.first:
        final shown = first ?? latest;
        if (shown != null) replies.add(_reply(shown, 3));
      case ThreadPreviewMode.both:
        if (first != null && first.eventId != latest?.eventId) {
          replies.add(_reply(first, 2));
        }
        if (latest != null) replies.add(_reply(latest, 2));
    }

    final room = widget.timeline.room;
    final faceIds =
        extras?.recentSenderIds ?? [if (latest != null) latest.senderId];
    final faces = [
      for (final id in faceIds)
        () {
          final member = room.getMemberOrFallback(id);
          return ThreadCardFace(
              name: member.displayName,
              color: member.defaultColor,
              avatar: member.avatar);
        }(),
    ];

    return ThreadCard(
      key: ValueKey("thread-card-$rootId"),
      replyCount: summary.replyCount,
      lastReply: latest?.originServerTs,
      faces: faces,
      replies: replies,
      onTap: _open,
    );
  }

  Widget _divider(BuildContext context, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Divider(height: 1, color: scheme.outlineVariant)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: tiamat.Text.labelLow(ThreadCard.countLabel(count)),
        ),
        Expanded(child: Divider(height: 1, color: scheme.outlineVariant)),
      ]),
    );
  }
}
