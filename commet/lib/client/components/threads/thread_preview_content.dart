// Vommet issue 982: displayable replies are distinct from thread activity.
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_emote.dart';
import 'package:commet/client/timeline_events/timeline_event_encrypted.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:intl/intl.dart';

bool isThreadReplyPreview(TimelineEvent event) =>
    event is TimelineEventMessage ||
    event is TimelineEventEmote ||
    event is TimelineEventSticker ||
    event is TimelineEventEncrypted;

String threadEventCount(int count) => count == 1
    ? Intl.message("1 event reported",
        name: "threadSingleEventCount",
        desc: "One thread relation reported, not necessarily a message reply")
    : Intl.message("$count events reported",
        args: [count],
        name: "threadEventCount",
        desc:
            "Last reported untyped thread relation total, including control events");

String get threadPreviewUnavailable =>
    Intl.message("No reply preview in loaded activity",
        name: "threadPreviewUnavailable",
        desc: "A bounded thread sample contains no displayable reply");

String get threadPreviewSample => Intl.message(
    "Reply preview from loaded activity",
    name: "threadPreviewSample",
    desc:
        "A reply sampled from loaded thread relations, not necessarily the last reply");

String get threadActivityLabel => Intl.message("Thread activity",
    name: "threadActivityLabel",
    desc: "A thread whose event total is unavailable");

String get threadFirstPreviewUnavailable =>
    Intl.message("First reply preview unavailable",
        name: "threadFirstPreviewUnavailable",
        desc: "The oldest sampled relation is not a displayable reply");
