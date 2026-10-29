// Vommet issue 823: the quote above a reply showed the quoted message's
// original text instead of its latest edit.

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_reply.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _me = "@alice:example.org";

class _FakeSdkRoom extends Fake implements matrix.Room {
  @override
  final String id = "!room:example.org";
}

class _FakeSdkTimeline extends Fake implements matrix.Timeline {
  @override
  final Map<String, Map<String, Set<matrix.Event>>> aggregatedEvents = {};

  void addEdit(matrix.Event edit) {
    aggregatedEvents
        .putIfAbsent(edit.relationshipEventId!, () => {})
        .putIfAbsent(matrix.RelationshipTypes.edit, () => {})
        .add(edit);
  }
}

class _FakeTimeline extends Fake implements MatrixTimeline {
  _FakeTimeline(this.matrixTimeline);

  @override
  final matrix.Timeline matrixTimeline;
}

class _FakeMatrixClient extends Fake implements MatrixClient {}

final _sdkRoom = _FakeSdkRoom();

matrix.Event _message(String body) => matrix.Event(
      content: {"msgtype": matrix.MessageTypes.Text, "body": body},
      type: matrix.EventTypes.Message,
      eventId: "\$original",
      senderId: _me,
      originServerTs: DateTime(2026, 10, 27),
      room: _sdkRoom,
    );

matrix.Event _edit(String body) => matrix.Event(
      content: {
        "msgtype": matrix.MessageTypes.Text,
        "body": "* $body",
        "m.new_content": {"msgtype": matrix.MessageTypes.Text, "body": body},
        "m.relates_to": {"rel_type": "m.replace", "event_id": "\$original"},
      },
      type: matrix.EventTypes.Message,
      eventId: "\$edit",
      senderId: _me,
      originServerTs: DateTime(2026, 10, 27, 0, 1),
      room: _sdkRoom,
    );

void main() {
  late _FakeSdkTimeline sdkTimeline;
  late _FakeTimeline timeline;
  late MatrixTimelineEventMessage message;

  setUp(() {
    sdkTimeline = _FakeSdkTimeline();
    timeline = _FakeTimeline(sdkTimeline);
    message = MatrixTimelineEventMessage(_message("see you at 5"),
        client: _FakeMatrixClient());
  });

  test("an unedited message is quoted as sent", () {
    expect(
        TimelineEventViewReply.quotedText(message, timeline), "see you at 5");
  });

  test("an edited message is quoted with its latest text", () {
    sdkTimeline.addEdit(_edit("see you at 6"));
    expect(
        TimelineEventViewReply.quotedText(message, timeline), "see you at 6");
  });
}
