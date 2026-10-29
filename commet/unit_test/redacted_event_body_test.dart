// Vommet issue 475: redacted mode rebuilds room event lines other than
// joins and leaves with the redacted sender name and text.
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_create_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_pinned_messages.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_power_levels.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_tombstone.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

class _FakeSdkClient extends Fake implements matrix.Client {}

class _FakeClient extends Fake implements MatrixClient {}

final _room = matrix.Room(id: "!room:example.org", client: _FakeSdkClient());

matrix.Event _event(String type, Map<String, dynamic> content,
        {Map<String, dynamic>? prev}) =>
    matrix.Event.fromJson({
      "type": type,
      "event_id": "\$event",
      "sender": "@grin:example.org",
      "origin_server_ts": 1700000000000,
      "room_id": "!room:example.org",
      "state_key": "",
      "content": content,
      if (prev != null) "unsigned": {"prev_content": prev},
    }, _room);

String _hide(String name, String userId) => "User ${userId.substring(1, 3)}";

String _bars(String text) => text.replaceAll(RegExp(r"\S"), "#");

void main() {
  // Known to the room, so its name doesn't have to be fetched.
  setUpAll(() => _room.states[matrix.EventTypes.RoomMember] = {
        "@grin:example.org": matrix.Event.fromJson({
          "type": matrix.EventTypes.RoomMember,
          "event_id": "\$member",
          "room_id": "!room:example.org",
          "sender": "@grin:example.org",
          "origin_server_ts": 1700000000000,
          "state_key": "@grin:example.org",
          "content": {"membership": "join", "displayname": "Grin"},
        }, _room),
      });

  test("room created names the redacted sender", () {
    final event = MatrixTimelineEventCreateRoom(
        _event(matrix.EventTypes.RoomCreate, {}),
        client: _FakeClient());
    expect(event.getBody(), contains("Grin"));
    final body = event.redactedBody(_hide, _bars);
    expect(body, contains("User gr"));
    expect(body, isNot(contains("Grin")));
  });

  test("a pin names the redacted sender", () {
    final event = MatrixTimelineEventPinnedMessages(
        _event(matrix.EventTypes.RoomPinnedEvents, {
          "pinned": ["\$a", "\$b"]
        }, prev: {
          "pinned": ["\$a"]
        }),
        client: _FakeClient());
    final body = event.redactedBody(_hide, _bars);
    expect(body, contains("User gr"));
    expect(body, isNot(contains("Grin")));
  });

  test("power levels name the redacted sender", () {
    final event = MatrixTimelineEventPowerLevels(
        _event(matrix.EventTypes.RoomPowerLevels, {}),
        client: _FakeClient());
    final body = event.redactedBody(_hide, _bars);
    expect(body, contains("User gr"));
    expect(body, isNot(contains("Grin")));
  });

  test("a replaced room hides the sender and redacts its message", () {
    final event = MatrixTimelineEventTombstone(
        _event(matrix.EventTypes.RoomTombstone, {
          "replacement_room": "!new:example.org",
          "body": "Moving house",
        }),
        client: _FakeClient());
    expect(event.getBody(), contains("Moving house"));
    final body = event.redactedBody(_hide, _bars);
    expect(body, contains("User gr"));
    expect(body, contains("###### #####"));
    expect(body, isNot(contains("Moving")));
    expect(body, isNot(contains("Grin")));
  });
}
