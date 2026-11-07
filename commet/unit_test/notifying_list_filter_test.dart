// A room added while the room list is open showed up twice: the base list
// reports an update before it reports the add, so the filter picked the room
// up on the update and then added it again on the add.

import 'dart:async';

import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/notifying_list_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("an item added to the base list appears once", () {
    final base = NotifyingList<int>.empty(growable: true);
    final filter = NotifyingListFilter<int>(base,
        where: (i) => i.isEven, onFilterParamsChanged: [base.onListUpdated]);

    base.add(2);
    base.add(3);
    base.add(4);

    expect(filter.toList(), [2, 4]);
  });

  test("an item already in the base list isn't added again", () {
    final base = NotifyingList<int>.empty(growable: true)..add(2);
    final paramsChanged = StreamController<void>.broadcast(sync: true);
    final filter = NotifyingListFilter<int>(base,
        where: (i) => i.isEven, onFilterParamsChanged: [paramsChanged.stream]);

    paramsChanged.add(null);
    base.add(6);
    paramsChanged.add(null);

    expect(filter.toList(), [2, 6]);
  });

  test("a filter change still adds and removes items", () {
    var limit = 2;
    final base = NotifyingList<int>.empty(growable: true)..addAll([1, 2, 3]);
    final paramsChanged = StreamController<void>.broadcast(sync: true);
    final filter = NotifyingListFilter<int>(base,
        where: (i) => i <= limit,
        onFilterParamsChanged: [paramsChanged.stream]);
    expect(filter.toList(), [1, 2]);

    limit = 3;
    paramsChanged.add(null);
    expect(filter.toList(), [1, 2, 3]);

    limit = 1;
    paramsChanged.add(null);
    expect(filter.toList(), [1]);
  });
}
