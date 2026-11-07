import 'package:commet/client/attachment.dart';
import 'package:commet/client/matrix/send_batch.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_related.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_unknown.dart';
import 'package:commet/ui/molecules/timeline_events/deleted_message_placeholder.dart';
import 'package:commet/utils/media_group.dart';

/// Whether [event] may join a media mosaic, and the facts needed to decide
/// which neighbours it groups with. Conservative on purpose: anything that
/// would be hidden or ambiguous inside a mosaic (a caption, a thread reply
/// in the main timeline or a thread's first post, a failed send) keeps the
/// post on its own. Reactions show on their picture's tile (Vommet issue
/// 741). Replies group only with replies to the same event from the same
/// send (Vommet issue 707); the mosaic shows that quote once.
MediaGroupMember mediaGroupMemberFor(
  TimelineEvent event,
  Timeline timeline, {
  ThreadsComponent? threads,
  bool isThreadTimeline = false,
}) {
  final replyTo = replyTargetOf(event);
  return MediaGroupMember(event.senderId, event.originServerTs,
      groupable: _groupable(event, timeline, threads, isThreadTimeline),
      replyTo: replyTo,
      sendBatch: replyTo == null ? null : SendBatch.of(event));
}

/// The event [event] replies to, or null when it isn't a reply.
String? replyTargetOf(TimelineEvent event) {
  if (event is! TimelineEventFeatureRelated) return null;
  final related = event as TimelineEventFeatureRelated;
  if (related.relationshipType != EventRelationshipType.reply) return null;
  return related.relatedEventId;
}

bool _groupable(TimelineEvent event, Timeline timeline,
    ThreadsComponent? threads, bool isThreadTimeline) {
  if (event is! TimelineEventMessage) return false;
  if (event.status == TimelineEventStatus.error) return false;
  if (timeline.isEventRedacted(event)) return false;

  final attachments = event.attachments;
  if (attachments == null || attachments.length != 1) return false;
  final attachment = attachments.first;
  if (attachment is! ImageAttachment && attachment is! VideoAttachment) {
    return false;
  }

  // Vommet: a spoiler (MSC4193) keeps its own full-size cover and reason.
  if ((attachment as FileAttachment).spoiler != null) return false;

  // In Matrix media events the body is the filename unless a caption was
  // written; a caption would be lost inside the mosaic.
  final body = event.body?.trim();
  if (body != null && body.isNotEmpty && body != attachment.name) return false;

  if (!isThreadTimeline &&
      threads?.isEventInResponseToThread(event, timeline) == true) {
    return false;
  }

  // A thread's first post shows the thread's summary under it, which a
  // mosaic picture has no room for.
  if (threads?.isHeadOfThread(event, timeline) == true) return false;

  return true;
}

/// Vommet issue 707: whether the event at [index] continues the reply just
/// before it: the same sender's same send (im.vommet.send_batch), replying
/// to the same event. The earlier part already shows the reply quote, so
/// this one leaves it out (e.g. the text after a reply's pictures).
bool continuesReplyAt(int index, Timeline timeline) {
  final events = timeline.events;
  if (index < 0 || index >= events.length) return false;
  final event = events[index];
  final batch = SendBatch.of(event);
  final target = replyTargetOf(event);
  if (batch == null || target == null) return false;
  for (var i = index + 1; i < events.length && i <= index + 4; i++) {
    final prev = events[i];
    // Not shown in the timeline (as the sender header check skips them).
    if (prev is TimelineEventUnknown &&
        !showsDeletedPlaceholder(timeline, prev)) {
      continue;
    }
    return prev.senderId == event.senderId &&
        SendBatch.of(prev) == batch &&
        replyTargetOf(prev) == target;
  }
  return false;
}

/// Position of the event at [index] within its media group, if any.
MediaGroupPosition mediaGroupPositionAt(
  int index,
  Timeline timeline, {
  ThreadsComponent? threads,
  bool isThreadTimeline = false,
}) {
  return MediaGroups.position(
    index,
    (i) => mediaGroupMemberFor(timeline.events[i], timeline,
        threads: threads, isThreadTimeline: isThreadTimeline),
    timeline.events.length,
  );
}

/// Indices (newest, oldest) of the run of joinable posts around [index].
(int, int) mediaGroupRunAt(
  int index,
  Timeline timeline, {
  ThreadsComponent? threads,
  bool isThreadTimeline = false,
}) {
  return MediaGroups.runExtent(
    index,
    (i) => mediaGroupMemberFor(timeline.events[i], timeline,
        threads: threads, isThreadTimeline: isThreadTimeline),
    timeline.events.length,
  );
}
