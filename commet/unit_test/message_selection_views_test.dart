import 'package:commet/client/client.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClient implements Client {
  @override
  String get identifier => "client";

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  final _client = _FakeClient();

  @override
  Client get client => _client;

  @override
  String get identifier => "!room";

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("a room and its thread select separately; keys go to the last used", () {
    final room = _FakeRoom();
    final main = MessageSelection(room)..register();
    final thread = MessageSelection(room);

    main.start(["e1"]);
    expect(main.ownsKeys, isTrue);
    expect(MessageSelection.activeIn(room), main);

    thread.start(["t1"]);
    expect(thread.ownsKeys, isTrue);
    expect(main.ownsKeys, isFalse);
    // Separate: neither has the other's message, and the header keeps the
    // room's selection.
    expect(main.ticked.contains("t1"), isFalse);
    expect(thread.ticked.contains("e1"), isFalse);
    expect(MessageSelection.activeIn(room), main);

    main.toggle(["e2"]);
    expect(main.ownsKeys, isTrue);

    main.exit();
    expect(thread.ownsKeys, isTrue);
    expect(MessageSelection.activeIn(room), isNull);

    // Closing the thread ends its selection.
    thread.dispose();
    expect(thread.ownsKeys, isFalse);
    main.dispose();
  });
}
