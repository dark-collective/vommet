import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_unknown.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: every thread in a room, newest activity first (the Threads tab
/// and the Threads side panel).
class RoomThreadsListWidget extends StatefulWidget {
  const RoomThreadsListWidget(
      {required this.room,
      this.onThreadOpened,
      this.shrinkWrap = false,
      super.key});
  final Room room;

  /// Called after a thread was opened from the list.
  final void Function(String rootId)? onThreadOpened;

  /// Size to the content, for use inside another scroll view.
  final bool shrinkWrap;

  @override
  State<RoomThreadsListWidget> createState() => RoomThreadsListWidgetState();
}

enum ThreadListFilter { all, mine }

class RoomThreadsListWidgetState extends State<RoomThreadsListWidget> {
  ThreadsComponent? get component =>
      widget.room.client.getComponent<ThreadsComponent>();

  ThreadListFilter filter = ThreadListFilter.all;
  List<ThreadSummary>? threads;
  String? nextBatch;
  bool loadingMore = false;
  Object? error;

  final List<StreamSubscription> _subs = [];
  Timer? _refreshTimer;

  // Bumped by every reload so a slow, superseded request can't overwrite
  // a newer result.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _subs.add(widget.room.onUpdate.listen((_) {
      // Receipts and member names change with sync.
      if (mounted) setState(() {});
    }));
    final timeline = widget.room.timeline;
    if (timeline != null) {
      _subs.add(timeline.onEventAdded.stream.listen((index) {
        if (index < 0 || index >= timeline.events.length) return;
        final event = timeline.events[index];
        if (component?.isEventInResponseToThread(event, timeline) == true) {
          _scheduleRefresh();
        }
      }));
    }
    reload();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(seconds: 1), reload);
  }

  Future<void> reload() async {
    final component = this.component;
    if (component == null) return;
    final generation = ++_generation;
    try {
      final page = await component.listThreads(widget.room,
          participated: filter == ThreadListFilter.mine);
      if (!mounted || generation != _generation) return;
      setState(() {
        threads = page.threads;
        nextBatch = page.nextBatch;
        error = null;
      });
    } catch (e, s) {
      Log.onError(e, s, content: "Could not load the room's threads");
      if (!mounted || generation != _generation) return;
      setState(() {
        threads ??= [];
        error = e;
      });
    }
  }

  Future<void> loadMore() async {
    final component = this.component;
    final from = nextBatch;
    if (component == null || from == null || loadingMore) return;
    final generation = _generation;
    setState(() => loadingMore = true);
    try {
      final page = await component.listThreads(widget.room,
          participated: filter == ThreadListFilter.mine, from: from);
      if (!mounted || generation != _generation) return;
      setState(() {
        final known = {for (final t in threads ?? []) t.rootId};
        threads = [
          ...?threads,
          ...page.threads.where((t) => !known.contains(t.rootId)),
        ];
        nextBatch = page.nextBatch;
      });
    } catch (e, s) {
      Log.onError(e, s, content: "Could not load more threads");
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  void setFilter(ThreadListFilter value) {
    if (value == filter) return;
    setState(() {
      filter = value;
      threads = null;
      nextBatch = null;
    });
    reload();
  }

  void open(ThreadSummary thread) {
    EventBus.openThread.add((
      widget.room.client.identifier,
      widget.room.identifier,
      thread.rootId,
    ));
    widget.onThreadOpened?.call(thread.rootId);
  }

  bool isUnread(ThreadSummary thread) =>
      preferences.experimentThreadReadState.value &&
      (component?.isThreadUnread(widget.room, thread) ?? false);

  @override
  Widget build(BuildContext context) {
    final threads = this.threads;
    final Widget body;
    if (threads == null) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (threads.isEmpty) {
      body =
          _EmptyThreads(filter: filter, failed: error != null, onRetry: reload);
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) loadMore();
          return false;
        },
        child: ListView.builder(
          key: const ValueKey("room-threads-list"),
          shrinkWrap: widget.shrinkWrap,
          physics:
              widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          itemCount: threads.length + (nextBatch != null ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= threads.length) {
              if (widget.shrinkWrap) {
                return Center(
                  child: TextButton(
                      onPressed: loadingMore ? null : loadMore,
                      child: const Text("Load more")),
                );
              }
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }
            final thread = threads[index];
            return ThreadListTile(
              key: ValueKey("thread-${thread.rootId}"),
              room: widget.room,
              thread: thread,
              unread: isUnread(thread),
              onTap: () => open(thread),
            );
          },
        ),
      );
    }

    return Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              for (final value in ThreadListFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: ValueKey("thread-filter-${value.name}"),
                    label: Text(value == ThreadListFilter.all
                        ? "All threads"
                        : "My threads"),
                    selected: filter == value,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setFilter(value),
                  ),
                ),
            ],
          ),
        ),
        if (widget.shrinkWrap) body else Expanded(child: body),
      ],
    );
  }
}

class _EmptyThreads extends StatelessWidget {
  const _EmptyThreads(
      {required this.filter, required this.failed, required this.onRetry});
  final ThreadListFilter filter;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (title, detail) = failed
        ? ("Couldn't load threads", "Your server didn't answer. Try again.")
        : filter == ThreadListFilter.mine
            ? (
                "No threads of yours",
                "Threads you start or reply in show up here."
              )
            : (
                "No threads yet",
                "Start one with \"Reply In Thread\" in a message's menu."
              );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined,
              size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          tiamat.Text.labelEmphasised(title),
          const SizedBox(height: 4),
          Text(detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (failed)
            TextButton(onPressed: onRetry, child: const Text("Try again")),
        ],
      ),
    );
  }
}

/// One thread in the list: who started it and what they said, then the reply
/// count and the newest reply.
class ThreadListTile extends StatelessWidget {
  const ThreadListTile(
      {required this.room,
      required this.thread,
      this.unread = false,
      this.onTap,
      super.key});
  final Room room;
  final ThreadSummary thread;
  final bool unread;
  final VoidCallback? onTap;

  static String bodyOf(TimelineEvent event) {
    if (event is TimelineEventUnknown) return "Message deleted";
    final body = event.plainTextBody.trim();
    return body.isEmpty ? "Message" : body;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final root = thread.root;
    final starter = room.getMemberOrFallback(root.senderId);
    final latest = thread.latestReply;
    final replier =
        latest == null ? null : room.getMemberOrFallback(latest.senderId);
    final replies =
        thread.replyCount == 1 ? "1 reply" : "${thread.replyCount} replies";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Avatar(
                  image: starter.avatar,
                  placeholderText: starter.displayName,
                  placeholderColor: starter.defaultColor,
                  radius: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: tiamat.Text(
                              starter.displayName,
                              color: starter.defaultColor,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              autoAdjustBrightness: true,
                            ),
                          ),
                          const SizedBox(width: 6),
                          tiamat.Text.labelLow(
                            TextUtils.timestampToLocalizedTime(
                                root.originServerTs, context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bodyOf(root),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: unread ? FontWeight.w700 : null),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.forum_outlined,
                              size: 14,
                              color:
                                  unread ? scheme.primary : scheme.secondary),
                          const SizedBox(width: 4),
                          Text(
                            replies,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                    color: unread
                                        ? scheme.primary
                                        : scheme.secondary,
                                    fontWeight: FontWeight.w600),
                          ),
                          if (latest != null && replier != null) ...[
                            const SizedBox(width: 8),
                            tiamat.Avatar(
                              image: replier.avatar,
                              placeholderText: replier.displayName,
                              placeholderColor: replier.defaultColor,
                              radius: 8,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: tiamat.Text.labelLow(
                                "${replier.displayName}: ${bodyOf(latest)}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            tiamat.Text.labelLow(
                              TextUtils.timestampToLocalizedTime(
                                  latest.originServerTs, context),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (unread)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 0, 0),
                    child: Container(
                      key: const ValueKey("thread-unread-dot"),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: scheme.primary, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
