import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_related.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/utils/media_group.dart';

/// Whether [event] may join a media mosaic, and the facts needed to decide
/// which neighbours it groups with. Conservative on purpose: anything that
/// would be hidden or ambiguous inside a mosaic (a caption, a reply quote,
/// reactions, a thread reply in the main timeline, a failed send) keeps the
/// post on its own.
MediaGroupMember mediaGroupMemberFor(
  TimelineEvent event,
  Timeline timeline, {
  ThreadsComponent? threads,
  bool isThreadTimeline = false,
}) {
  return MediaGroupMember(event.senderId, event.originServerTs,
      groupable: _groupable(event, timeline, threads, isThreadTimeline));
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

  // In Matrix media events the body is the filename unless a caption was
  // written; a caption would be lost inside the mosaic.
  final body = event.body?.trim();
  if (body != null && body.isNotEmpty && body != attachment.name) return false;

  if (event is TimelineEventFeatureRelated &&
      (event as TimelineEventFeatureRelated).relationshipType ==
          EventRelationshipType.reply) {
    return false;
  }

  if (event is TimelineEventFeatureReactions &&
      (event as TimelineEventFeatureReactions).hasReactions(timeline)) {
    return false;
  }

  if (!isThreadTimeline &&
      threads?.isEventInResponseToThread(event, timeline) == true) {
    return false;
  }

  return true;
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
