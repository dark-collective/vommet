import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/url_preview/outgoing_url_preview.dart';
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
    List<OutgoingUrlPreview>? urlPreviews,
  });

  TimelineEvent? getFirstReplyToThread(TimelineEvent event, Timeline timeline);

  /// Vommet: one page of the room's threads, newest activity first.
  /// [participated] limits it to threads you started or replied in.
  Future<ThreadListPage> listThreads(Room room,
      {bool participated = false, String? from, int limit = 25});

  /// Vommet: whether [thread] has replies you haven't read, judged by your
  /// read receipts (threaded and unthreaded) in [room].
  bool isThreadUnread(Room room, ThreadSummary thread);

  /// Vommet: the thread headed by [root] as its card shows it: the summary
  /// the server bundled with the root, plus replies that arrived since.
  /// Null when [root] heads no thread.
  ThreadSummary? getThreadSummary(TimelineEvent root, Timeline timeline);

  /// Vommet: what a thread card needs beyond [getThreadSummary]: the newest
  /// repliers, the newest reply (decrypted), and the reply that opened the
  /// thread when [withFirstReply]. Cached per thread and refreshed when a
  /// new reply arrives.
  Future<ThreadPreviewExtras> loadThreadPreviewExtras(
      Room room, ThreadSummary thread,
      {bool withFirstReply = false});

  /// Vommet: ids of rooms where a thread may have changed in a way its card
  /// can't see, such as a reply being deleted; reload their previews.
  Stream<String> get onThreadsChanged;
}

/// Vommet: see [ThreadsComponent.loadThreadPreviewExtras].
class ThreadPreviewExtras {
  ThreadPreviewExtras(
      {this.firstReply,
      this.latestReply,
      this.replyCount,
      this.recentSenderIds = const []});

  /// The reply that opened the thread; null unless it was asked for.
  final TimelineEvent? firstReply;

  /// The newest reply, as the server has it now.
  final TimelineEvent? latestReply;

  /// How many replies the server counts now; null when it couldn't say.
  /// The summary bundled with a stored root can be out of date.
  final int? replyCount;

  /// Up to three people who replied most recently, newest first.
  final List<String> recentSenderIds;
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
