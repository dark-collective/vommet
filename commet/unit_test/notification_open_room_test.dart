import 'package:commet/utils/custom_uri.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 595: notification taps open the notification's room.
void main() {
  test('a notification from the background client opens the account', () {
    final payload = OpenRoomURI(
            roomId: "!room:example.org",
            clientId: "background_matrix_client:account-1")
        .toString();
    final uri = CustomURI.parse(payload);
    expect(uri, isA<OpenRoomURI>());
    expect((uri as OpenRoomURI).clientId, "account-1");
    expect(uri.roomId, "!room:example.org");
  });

  test('an account client id is kept as is', () {
    expect(accountClientId("account-1"), "account-1");
  });

  // A room asked for before the main page listens is kept and sent once it
  // does, instead of being dropped.
  test('open room sent before anything listens arrives on the first listen',
      () async {
    EventBus.doOpenRoom("!early:example.org", clientId: "client");

    final received = <RoomOpenArgs>[];
    final sub = EventBus.openRoom.stream.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    expect(received.map((a) => a.roomId), ["!early:example.org"]);
    expect(received.single.clientId, "client");

    EventBus.doOpenRoom("!later:example.org");
    await Future<void>.delayed(Duration.zero);
    expect(received.map((a) => a.roomId),
        ["!early:example.org", "!later:example.org"]);

    await sub.cancel();

    // Sent once only: a new listener doesn't get the early room again.
    final again = <RoomOpenArgs>[];
    final sub2 = EventBus.openRoom.stream.listen(again.add);
    await Future<void>.delayed(Duration.zero);
    expect(again, isEmpty);
    await sub2.cancel();
  });
}
