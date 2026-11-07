// Vommet issue 330: emotes (/me) showed their original text after an edit,
// and an edit sent from Commet would have turned the emote into a plain
// message.

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_emote.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
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

class _FakeMember extends Fake implements Member {
  @override
  final String displayName = "Alice";
}

class _FakeRoom extends Fake implements Room {
  @override
  Member getMemberOrFallback(String id) => _FakeMember();
}

class _FakeTimeline extends Fake implements MatrixTimeline {
  _FakeTimeline(this.matrixTimeline);

  @override
  final matrix.Timeline matrixTimeline;

  @override
  final Room room = _FakeRoom();
}

class _FakeMatrixClient extends Fake implements MatrixClient {}

class _FakeMessage extends Fake implements TimelineEventMessage {}

final _sdkRoom = _FakeSdkRoom();

matrix.Event _emote(String body) => matrix.Event(
      content: {"msgtype": matrix.MessageTypes.Emote, "body": body},
      type: matrix.EventTypes.Message,
      eventId: "\$emote",
      senderId: _me,
      originServerTs: DateTime(2026, 10, 15),
      room: _sdkRoom,
    );

matrix.Event _edit(String body,
        {String sender = _me, String id = "\$edit", int minute = 1}) =>
    matrix.Event(
      content: {
        "msgtype": matrix.MessageTypes.Emote,
        "body": "* $body",
        "m.new_content": {"msgtype": matrix.MessageTypes.Emote, "body": body},
        "m.relates_to": {"rel_type": "m.replace", "event_id": "\$emote"},
      },
      type: matrix.EventTypes.Message,
      eventId: id,
      senderId: sender,
      originServerTs: DateTime(2026, 10, 15, 0, minute),
      room: _sdkRoom,
    );

void main() {
  late _FakeSdkTimeline sdkTimeline;
  late _FakeTimeline timeline;
  late MatrixTimelineEventEmote emote;

  setUp(() {
    sdkTimeline = _FakeSdkTimeline();
    timeline = _FakeTimeline(sdkTimeline);
    emote =
        MatrixTimelineEventEmote(_emote("waves"), client: _FakeMatrixClient());
  });

  test("an emote without edits shows its own text", () {
    expect(emote.getPlaintextBody(timeline), "waves");
    expect(emote.getBody(timeline: timeline), "*Alice waves");
  });

  test("an edited emote shows the latest edit", () {
    sdkTimeline.addEdit(_edit("waves hello", id: "\$edit1", minute: 1));
    sdkTimeline.addEdit(_edit("waves goodbye", id: "\$edit2", minute: 2));

    expect(emote.getPlaintextBody(timeline), "waves goodbye");
    expect(emote.getBody(timeline: timeline), "*Alice waves goodbye");
  });

  test("an edit by someone else is ignored", () {
    sdkTimeline.addEdit(_edit("is hacked", sender: "@mallory:example.org"));

    expect(emote.getPlaintextBody(timeline), "waves");
  });

  test("without a timeline the original text is shown", () {
    sdkTimeline.addEdit(_edit("waves hello"));

    expect(emote.getBody(), "*alice waves");
  });

  test("emotes can be edited", () {
    expect(emote.editable, isTrue);
  });

  test("an edit of an emote is sent as an emote", () {
    expect(MatrixRoom.messageTypeFor(replaceEvent: emote),
        matrix.MessageTypes.Emote);
  });

  test("messages and edits of messages are sent as text", () {
    expect(MatrixRoom.messageTypeFor(), matrix.MessageTypes.Text);
    expect(MatrixRoom.messageTypeFor(replaceEvent: _FakeMessage()),
        matrix.MessageTypes.Text);
  });
}
