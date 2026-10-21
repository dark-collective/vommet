// Vommet issue 490: redacted mode hides the names in membership events.
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_membership.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

class _FakeSdkClient extends Fake implements matrix.Client {}

class _FakeClient extends Fake implements MatrixClient {}

final _room = matrix.Room(id: "!room:example.org", client: _FakeSdkClient());

MatrixTimelineEventMembership _membership(
    Map<String, dynamic>? prev, Map<String, dynamic> content,
    {String sender = "@grin:example.org"}) {
  return MatrixTimelineEventMembership(
      matrix.Event.fromJson({
        "type": matrix.EventTypes.RoomMember,
        "event_id": "\$event",
        "sender": sender,
        "origin_server_ts": 1700000000000,
        "state_key": "@grin:example.org",
        "content": content,
        if (prev != null) "unsigned": {"prev_content": prev},
      }, _room),
      client: _FakeClient());
}

String _hide(String name, String userId) => "User ${userId.substring(1, 3)}";

void main() {
  test("a join shows the mapped name, not the display name", () {
    final event = _membership(
        {"membership": "leave"}, {"membership": "join", "displayname": "Grin"});
    expect(event.getBody(), contains("Grin"));
    final body = event.bodyWithNames(_hide);
    expect(body, contains("User gr"));
    expect(body, isNot(contains("Grin")));
  });

  test("a display name change shows neither the old nor the new name", () {
    final event = _membership({"membership": "join", "displayname": "Grin"},
        {"membership": "join", "displayname": "Grin Two"});
    final body = event.bodyWithNames(_hide);
    expect(body, contains("User gr"));
    expect(body, isNot(contains("Grin")));
    expect(body, isNot(contains("@grin")));
  });

  test("an avatar change shows the mapped name", () {
    final event = _membership({
      "membership": "join",
      "displayname": "Grin",
      "avatar_url": "mxc://a/1"
    }, {
      "membership": "join",
      "displayname": "Grin",
      "avatar_url": "mxc://a/2"
    });
    final body = event.bodyWithNames(_hide);
    expect(body, contains("User gr"));
    expect(body, isNot(contains("Grin")));
  });

  test("the sender of a kick is mapped too", () {
    final event = _membership({
      "membership": "join",
      "displayname": "Grin"
    }, {
      "membership": "leave",
      "displayname": "Grin"
    }, sender: "@mod:example.org");
    final body = event.bodyWithNames(_hide);
    expect(body, isNot(contains("@mod")));
    expect(body, isNot(contains("Grin")));
  });
}
