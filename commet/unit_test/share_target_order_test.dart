import 'package:commet/utils/share_target_order.dart';
import 'package:flutter_test/flutter_test.dart';

class _R {
  _R(this.name, this.t, {this.fav = false, this.dm = false});
  final String name;
  final int t;
  final bool fav;
  final bool dm;
}

List<String> _order(List<_R> rooms, {int recentCount = 7}) => orderShareTargets(
      rooms,
      lastActivity: (r) => DateTime.fromMillisecondsSinceEpoch(r.t),
      isFavorite: (r) => r.fav,
      isDirectMessage: (r) => r.dm,
      recentCount: recentCount,
    ).map((r) => r.name).toList();

void main() {
  test('favorites, then recent, then DMs, then the rest', () {
    final rooms = [
      _R('oldRoom', 1),
      _R('oldDm', 2, dm: true),
      _R('newRoom', 9),
      _R('favOld', 0, fav: true),
      _R('favNew', 5, fav: true, dm: true),
      _R('midDm', 6, dm: true),
      _R('midRoom', 7),
    ];
    expect(_order(rooms, recentCount: 2), [
      'favNew',
      'favOld',
      'newRoom',
      'midRoom',
      'midDm',
      'oldDm',
      'oldRoom',
    ]);
  });

  test('each room appears once; fewer rooms than the recent count', () {
    final rooms = [_R('a', 1, dm: true), _R('b', 2), _R('c', 3, fav: true)];
    expect(_order(rooms), ['c', 'b', 'a']);
  });

  test('empty list', () {
    expect(_order([]), isEmpty);
  });
}
