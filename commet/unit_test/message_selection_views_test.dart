import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/timeline_events/message_text_selection.dart';
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

  test("a long press on a ticked message selects its text instead", () {
    final room = _FakeRoom();
    final selection = MessageSelection(room);
    addTearDown(() {
      MessageTextSelection.active.value = null;
      selection.dispose();
    });

    selection.start(["e1"]);
    selection.toggle(["e2"]);
    // Not ticked, or a group (a media mosaic): nothing happens here.
    expect(selection.selectText(["e3"]), isFalse);
    expect(selection.selectText(["e1", "e2"]), isFalse);
    expect(MessageTextSelection.active.value, isNull);

    expect(selection.selectText(["e2"]), isTrue);
    expect(selection.active, isFalse);
    expect(selection.ticked.isEmpty, isTrue);
    expect(MessageTextSelection.active.value, "e2");

    // Not selecting messages: nothing to do.
    expect(selection.selectText(["e2"]), isFalse);
  });
}
