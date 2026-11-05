import 'package:commet/client/space.dart';
import 'package:commet/utils/space_for_room.dart';
import 'package:test/test.dart';

class _FakeSpace implements Space {
  _FakeSpace(this.identifier, {this.roomIds = const [], this.topLevel = true});

  @override
  final String identifier;

  final List<String> roomIds;
  final bool topLevel;
  final List<Space> subs = [];

  @override
  bool get isTopLevel => topLevel;

  @override
  List<Space> get subspaces => subs;

  @override
  bool containsRoom(String identifier) => roomIds.contains(identifier);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('opens the top-level space, not the subspace holding the room', () {
    final sub = _FakeSpace('!sub', roomIds: ['!room'], topLevel: false);
    final top = _FakeSpace('!top')..subs.add(sub);

    expect(spaceForRoom([sub, top], '!room'), top);
  });

  test('finds the room several subspaces down', () {
    final inner = _FakeSpace('!inner', roomIds: ['!room'], topLevel: false);
    final middle = _FakeSpace('!middle', topLevel: false)..subs.add(inner);
    final top = _FakeSpace('!top')..subs.add(middle);

    expect(spaceForRoom([inner, middle, top], '!room'), top);
  });

  test('stays in the open space when the room is in it', () {
    final sub = _FakeSpace('!sub', roomIds: ['!room'], topLevel: false);
    final first = _FakeSpace('!first')..subs.add(sub);
    final second = _FakeSpace('!second')..subs.add(sub);

    expect(spaceForRoom([first, second], '!room', current: second), second);
    expect(spaceForRoom([first, second], '!room', current: sub), sub);
  });

  test('ignores an open space the room is not in', () {
    final other = _FakeSpace('!other');
    final top = _FakeSpace('!top', roomIds: ['!room']);

    expect(spaceForRoom([other, top], '!room', current: other), top);
  });

  test('falls back to the subspace when no top-level space holds it', () {
    final sub = _FakeSpace('!sub', roomIds: ['!room'], topLevel: false);

    expect(spaceForRoom([sub], '!room'), sub);
    expect(spaceForRoom([sub], '!elsewhere'), isNull);
  });

  test('survives a space loop', () {
    final a = _FakeSpace('!a');
    final b = _FakeSpace('!b', topLevel: false);
    a.subs.add(b);
    b.subs.add(a);

    expect(spaceForRoom([a, b], '!room'), isNull);
  });
}
