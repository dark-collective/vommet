import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/space_child.dart';
import 'package:commet/ui/pages/get_or_create_room/existing_room_picker.dart';
import 'package:flutter_test/flutter_test.dart';

class _Room implements Room {
  _Room(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Space implements Space {
  _Space(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DirectMessages implements DirectMessagesComponent<Client> {
  _DirectMessages(this.dmIds);

  final Set<String> dmIds;

  @override
  bool isRoomDirectMessage(Room room) => dmIds.contains(room.identifier);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test("Vommet issue 837: finds the direct messages among the rooms", () {
    final ids = idsOfDirectMessages(_DirectMessages({"!dm", "!space"}), [
      SpaceChildRoom(_Room("!dm")),
      SpaceChildRoom(_Room("!group")),
      SpaceChildSpace(_Space("!space")),
    ]);

    expect(ids, {"!dm"});
  });

  test("Vommet issue 837: no direct messages without the component", () {
    expect(idsOfDirectMessages(null, [SpaceChildRoom(_Room("!dm"))]), isEmpty);
  });
}
