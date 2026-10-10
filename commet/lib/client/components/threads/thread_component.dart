import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';

abstract class ThreadsComponent<T extends Client> implements Component<T> {
  bool isEventInResponseToThread(TimelineEvent event, Timeline timeline);

  bool isHeadOfThread(TimelineEvent event, Timeline timeline);

  Future<Timeline?> getThreadTimeline(
      {required Timeline roomTimeline, required String threadRootEventId});

  Future<TimelineEvent?> sendMessage({
    required String threadRootEventId,
    required Room room,
    String? message,
    TimelineEvent? inReplyTo,
    TimelineEvent? replaceEvent,
    List<ProcessedAttachment>? processedAttachments,
  });

  TimelineEvent? getFirstReplyToThread(TimelineEvent event, Timeline timeline);

  /// Vommet: one page of the room's threads, newest activity first.
  /// [participated] limits it to threads you started or replied in.
  Future<ThreadListPage> listThreads(Room room,
      {bool participated = false, String? from, int limit = 25});

  /// Vommet: whether [thread] has replies you haven't read, judged by your
  /// read receipts (threaded and unthreaded) in [room].
  bool isThreadUnread(Room room, ThreadSummary thread);
}

/// Vommet: a thread as the room's thread list shows it.
class ThreadSummary {
  ThreadSummary({
    required this.root,
    required this.replyCount,
    this.latestReply,
    this.participated = false,
  });

  final TimelineEvent root;
  final int replyCount;
  final TimelineEvent? latestReply;

  /// You started the thread or replied in it.
  final bool participated;

  String get rootId => root.eventId;

  /// When the thread was last active: its newest reply, else the root.
  DateTime get lastActivity =>
      latestReply?.originServerTs ?? root.originServerTs;
}

/// Vommet: one page of [ThreadsComponent.listThreads].
class ThreadListPage {
  ThreadListPage(this.threads, {this.nextBatch});

  final List<ThreadSummary> threads;

  /// Pass to [ThreadsComponent.listThreads] as `from` for the next page;
  /// null when there are no more.
  final String? nextBatch;
}
