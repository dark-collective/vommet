// Vommet issue 494: voting in a poll added "Unknown Event Type:
// org.matrix.msc3381.poll.response" rows to the timeline. Votes and poll ends
// only count towards their poll, so they are hidden, with a readable label
// where they do show (developer mode's hidden events).

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_poll_relation.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

class _FakeSdkRoom extends Fake implements matrix.Room {
  @override
  final String id = "!room:example.org";
}

class _FakeMatrixClient extends Fake implements MatrixClient {}

final _sdkRoom = _FakeSdkRoom();

MatrixTimelineEventPollRelation _relation(String type,
        {matrix.EventStatus status = matrix.EventStatus.synced}) =>
    MatrixTimelineEventPollRelation(
      matrix.Event(
        content: {
          "m.relates_to": {"rel_type": "m.reference", "event_id": "\$poll"},
        },
        type: type,
        eventId: "\$vote",
        senderId: "@alice:example.org",
        originServerTs: DateTime(2026, 10, 19),
        room: _sdkRoom,
        status: status,
      ),
      client: _FakeMatrixClient(),
    );

void main() {
  test("poll votes and ends, unstable and stable, are poll relations", () {
    for (final type in [
      "org.matrix.msc3381.poll.response",
      "m.poll.response",
      "org.matrix.msc3381.poll.end",
      "m.poll.end",
    ]) {
      expect(MatrixTimelineEventPollRelation.isPollRelationType(type), isTrue,
          reason: type);
    }
    expect(
        MatrixTimelineEventPollRelation.isPollRelationType(
            "org.matrix.msc3381.poll.start"),
        isFalse);
    expect(
        MatrixTimelineEventPollRelation.isPollRelationType(
            matrix.EventTypes.Message),
        isFalse);
  });

  test("a vote is hidden, even when it failed to send", () {
    for (final status in [
      matrix.EventStatus.synced,
      matrix.EventStatus.error,
    ]) {
      expect(
          TimelineViewEntryState.eventToDisplayType(
              _relation("org.matrix.msc3381.poll.response", status: status)),
          TimelineEventWidgetDisplayType.hidden,
          reason: status.name);
    }
    expect(TimelineViewEntryState.eventToDisplayType(_relation("m.poll.end")),
        TimelineEventWidgetDisplayType.hidden);
  });

  test("votes and ends have a label instead of Unknown Event Type", () {
    expect(_relation("org.matrix.msc3381.poll.response").plainTextBody,
        "Voted in a poll");
    expect(_relation("m.poll.response").plainTextBody, "Voted in a poll");
    expect(
        _relation("org.matrix.msc3381.poll.end").plainTextBody, "Ended a poll");
    expect(_relation("m.poll.end").plainTextBody, "Ended a poll");
  });
}
