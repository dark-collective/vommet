import 'package:commet/client/client.dart';
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
  _Space(this.identifier, {this.roomIds = const {}, this.subspaces = const []});

  @override
  final String identifier;

  final Set<String> roomIds;

  @override
  final List<Space> subspaces;

  @override
  bool containsRoom(String identifier) => roomIds.contains(identifier);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Client implements Client {
  _Client(this.spaces);

  @override
  final List<Space> spaces;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test("Vommet issue 732: finds rooms and subspaces already in a space", () {
    final sub = _Space("!sub");
    final loose = _Space("!loose");
    final parent = _Space("!parent", roomIds: {"!a"}, subspaces: [sub]);
    final client = _Client([parent, sub, loose]);

    final ids = idsInAnySpace(client, [
      SpaceChildRoom(_Room("!a")),
      SpaceChildRoom(_Room("!b")),
      SpaceChildSpace(sub),
      SpaceChildSpace(loose),
    ]);

    expect(ids, {"!a", "!sub"});
  });
}
