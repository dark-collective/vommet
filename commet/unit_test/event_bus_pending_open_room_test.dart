import 'package:commet/utils/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 595: a room asked for before the main page listens is kept
// and sent once it does, instead of being dropped.
void main() {
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
