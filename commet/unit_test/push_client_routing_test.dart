import 'package:commet/client/components/push_notification/push_client_routing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a Matrix push names the account under devices[].data', () {
    // What a UnifiedPush gateway forwards: the homeserver's notification.
    final message = <String, dynamic>{
      "room_id": "!room:example.org",
      "event_id": r"$event",
      "counts": {"unread": 1},
      "devices": [
        {
          "app_id": "chat.commet.commetapp.android",
          "pushkey": "https://ntfy.example/up123",
          "data": {"local_client_id": "account-2"},
        }
      ],
    };
    expect(PushClientRouting.localClientId(message), "account-2");
  });

  test('a flattened push (old gateway) still works', () {
    expect(
        PushClientRouting.localClientId(
            {"room_id": "!room:example.org", "local_client_id": "account-1"}),
        "account-1");
  });

  test('no account named: null, so the rooms are checked instead', () {
    expect(PushClientRouting.localClientId({"room_id": "!r:x"}), isNull);
    expect(
        PushClientRouting.localClientId({
          "devices": [
            "junk",
            {"data": "junk"},
            {"data": {}},
          ]
        }),
        isNull);
  });
}
