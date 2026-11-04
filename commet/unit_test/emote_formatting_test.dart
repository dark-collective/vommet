// Vommet issue 325: emotes (/me) ignored their formatted_body, so a rainbow
// /me from Element lost its colors, and there was no /rainbowme to send one.

import 'package:commet/client/matrix/components/command_component/matrix_command_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_emote.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/room.dart';
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
  _FakeMember(this.displayName);

  @override
  final String displayName;
}

class _FakeRoom extends Fake implements Room {
  _FakeRoom(this.name);

  final String name;

  @override
  Member getMemberOrFallback(String id) => _FakeMember(name);
}

class _FakeTimeline extends Fake implements MatrixTimeline {
  _FakeTimeline(this.matrixTimeline, {String name = "Alice"})
      : room = _FakeRoom(name);

  @override
  final matrix.Timeline matrixTimeline;

  @override
  final Room room;
}

class _FakeMatrixClient extends Fake implements MatrixClient {}

final _sdkRoom = _FakeSdkRoom();

matrix.Event _emote(Map<String, dynamic> content) => matrix.Event(
      content: {"msgtype": matrix.MessageTypes.Emote, ...content},
      type: matrix.EventTypes.Message,
      eventId: "\$emote",
      senderId: _me,
      originServerTs: DateTime(2026, 10, 26),
      room: _sdkRoom,
    );

MatrixTimelineEventEmote _event(Map<String, dynamic> content) =>
    MatrixTimelineEventEmote(_emote(content), client: _FakeMatrixClient());

void main() {
  late _FakeSdkTimeline sdkTimeline;

  setUp(() => sdkTimeline = _FakeSdkTimeline());

  test("a plain emote has no formatted body", () {
    final emote = _event({"body": "waves"});

    expect(
        emote.getFormattedBody(timeline: _FakeTimeline(sdkTimeline)), isNull);
  });

  test("a formatted emote shows its HTML after the sender's name", () {
    final emote = _event({
      "body": "waves",
      "format": "org.matrix.custom.html",
      "formatted_body": '<font data-mx-color="#ff0000">waves</font>',
    });

    expect(emote.getFormattedBody(timeline: _FakeTimeline(sdkTimeline)),
        '*Alice <font data-mx-color="#ff0000">waves</font>');
  });

  test("the sender's name is escaped in the HTML", () {
    final emote = _event({
      "body": "waves",
      "format": "org.matrix.custom.html",
      "formatted_body": "<b>waves</b>",
    });

    expect(
        emote.getFormattedBody(
            timeline: _FakeTimeline(sdkTimeline, name: "<i>Al</i>")),
        "*&lt;i&gt;Al&lt;/i&gt; <b>waves</b>");
  });

  test("an edited emote shows the edit's formatted body", () {
    final emote = _event({"body": "waves"});
    sdkTimeline.addEdit(matrix.Event(
      content: {
        "msgtype": matrix.MessageTypes.Emote,
        "body": "* waves hello",
        "m.new_content": {
          "msgtype": matrix.MessageTypes.Emote,
          "body": "waves hello",
          "format": "org.matrix.custom.html",
          "formatted_body": "waves <b>hello</b>",
        },
        "m.relates_to": {"rel_type": "m.replace", "event_id": "\$emote"},
      },
      type: matrix.EventTypes.Message,
      eventId: "\$edit",
      senderId: _me,
      originServerTs: DateTime(2026, 10, 26, 0, 1),
      room: _sdkRoom,
    ));

    expect(emote.getFormattedBody(timeline: _FakeTimeline(sdkTimeline)),
        "*Alice waves <b>hello</b>");
  });

  test("rainbow HTML colors each character and escapes it", () {
    expect(
        MatrixCommandComponent.rainbowHtml("a<"),
        '<span data-mx-color="#ff0000">a</span>'
        '<span data-mx-color="#00ffff">&lt;</span>');
  });
}
