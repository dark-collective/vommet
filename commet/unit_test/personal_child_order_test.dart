import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/utils/personal_child_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved siblings first; new siblings append in default order', () {
    final defaults = ['a', 'b', 'c', 'd'];
    expect(PersonalChildOrder.project(defaults, ['c', 'a'], (s) => s),
        ['c', 'a', 'b', 'd']);
    expect(defaults, ['a', 'b', 'c', 'd']);
    expect(PersonalChildOrder.project(defaults, null, (s) => s), defaults);
  });
  test('missing and duplicate IDs do not hide or duplicate live children', () {
    expect(PersonalChildOrder.project(['a', 'b'], ['c', 'b', 'b'], (s) => s),
        ['b', 'a']);
    expect(PersonalChildOrder.project(['a', 'b', 'c'], ['c', 'b'], (s) => s),
        ['c', 'b', 'a']);
  });
  test('editing retains dormant positions for rejoin or lazy hydration', () {
    final saved = ['c', 'unknown', 'a'];
    final next = PersonalChildOrder.preserveMissing(saved, ['a', 'c', 'new']);
    expect(next, ['a', 'unknown', 'c', 'new']);
    expect(
        PersonalChildOrder.project(
            ['c', 'a', 'unknown', 'new'], next, (s) => s),
        next);
  });
  test('malformed account data falls back and reset preserves unknown fields',
      () {
    expect(PersonalChildOrder.parse({'order': 42}), isNull);
    expect(
        PersonalChildOrder.parse({
          'order': ['b', 2, '', 'b', 'a']
        }),
        ['b', 'a']);
    final previous = <String, Object?>{
      'order': ['b'],
      'future': {'kept': true}
    };
    expect(PersonalChildOrder.content(previous, null), {
      'future': {'kept': true}
    });
    expect(previous['order'], ['b']);
    expect(PersonalChildOrder.content(previous, ['a'])['future'],
        previous['future']);
  });
  test('unified pane interleaves room, subspace and preview in sibling order',
      () {
    const room = ChatEntry(key: 'acct:a', roomId: 'a', name: 'A');
    const sub = SpaceEntry(key: 'acct:s', spaceId: 's', name: 'Sub');
    const preview = ChatPreviewEntry(roomId: 'p', name: 'Preview');
    const space = SpaceEntry(
        key: 'acct:r',
        spaceId: 'r',
        name: 'Root',
        rooms: [room],
        subspaces: [sub],
        previews: [preview],
        childOrder: ['s', 'p', 'a']);
    expect(buildSpacePaneRows(space).map((r) => r.runtimeType),
        [SubspaceRow, SpacePreviewRow, SpaceRoomRow]);
    expect(chatListStops([SpaceTopRow(space)]).single.chat, room);
    const stalePreview = ChatPreviewEntry(roomId: 'a', name: 'Stale preview');
    const sameChild = SpaceEntry(
        key: 'acct:r',
        spaceId: 'r',
        name: 'Root',
        rooms: [room],
        previews: [stalePreview],
        childOrder: ['a']);
    expect(buildSpacePaneRows(sameChild).single, isA<SpaceRoomRow>());
  });
}
