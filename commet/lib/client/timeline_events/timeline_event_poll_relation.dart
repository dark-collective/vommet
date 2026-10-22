import 'package:commet/client/timeline_events/timeline_event.dart';

/// A vote in a poll, or the end of one. It only counts towards its poll and
/// is never a timeline row of its own.
abstract class TimelineEventPollRelation extends TimelineEvent {}
