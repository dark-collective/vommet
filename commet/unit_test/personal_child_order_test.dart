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
}
