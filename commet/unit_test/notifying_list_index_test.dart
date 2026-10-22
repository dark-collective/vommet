// Vommet: NotifyingListIndex must answer exactly what a scan of the list
// would, whatever happens to the list.
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/notifying_list_index.dart';
import 'package:flutter_test/flutter_test.dart';

class _Item {
  _Item(this.id);
  final String id;
  @override
  String toString() => "$id#${identityHashCode(this)}";
}

void main() {
  late NotifyingList<_Item> list;
  late NotifyingListIndex<_Item> index;

  setUp(() {
    list = NotifyingList.empty(growable: true);
    index = NotifyingListIndex(list, (item) => item.id);
  });

  void expectMatchesScan(Iterable<String> ids) {
    for (final id in ids) {
      final scanned = list.where((i) => i.id == id).firstOrNull;
      expect(index[id], same(scanned), reason: id);
      expect(index.containsKey(id), scanned != null, reason: id);
    }
  }

  const ids = ["a", "b", "c", "d"];

  test("add, insert and remove", () {
    final a = _Item("a"), b = _Item("b"), c = _Item("c");
    list.add(a);
    expectMatchesScan(ids);
    list.addAll([b, c]);
    expectMatchesScan(ids);
    list.remove(b);
    expectMatchesScan(ids);
    list.insert(0, b);
    expectMatchesScan(ids);
    list.removeAt(0);
    expectMatchesScan(ids);
    list.removeLast();
    expectMatchesScan(ids);
    list.removeWhere((i) => i.id == "a");
    expectMatchesScan(ids);
    expect(index["a"], isNull);
  });

  test("clear, replace in place, retainWhere", () {
    list.addAll([_Item("a"), _Item("b"), _Item("c")]);
    expectMatchesScan(ids);
    list[1] = _Item("d");
    expectMatchesScan(ids);
    list.retainWhere((i) => i.id != "a");
    expectMatchesScan(ids);
    list.clear();
    expectMatchesScan(ids);
    list.add(_Item("a"));
    expectMatchesScan(ids);
  });

  test("a mutation without events (length) is noticed", () {
    list.addAll([_Item("a"), _Item("b"), _Item("c")]);
    expectMatchesScan(ids);
    list.length = 1;
    expectMatchesScan(ids);
  });

  test("duplicate ids answer the first, as a scan does", () {
    final first = _Item("a"), second = _Item("a");
    list.addAll([_Item("b"), first, second]);
    expectMatchesScan(ids);
    expect(index["a"], same(first));

    list.remove(first);
    expectMatchesScan(ids);
    expect(index["a"], same(second));

    list.insert(0, first);
    expectMatchesScan(ids);
    expect(index["a"], same(first));

    // The same object twice.
    list.add(first);
    list.removeAt(0);
    expectMatchesScan(ids);
    list.removeWhere((i) => i.id == "a");
    expectMatchesScan(ids);
    expect(index.containsKey("a"), isFalse);
  });

  test("a lookup while the list reports a change sees the change", () {
    final seen = <bool>[];
    list.onListUpdated.listen((_) => seen.add(index.containsKey("a")));
    final a = _Item("a");
    list.add(a);
    list.remove(a);
    expect(seen, [true, false]);
    expectMatchesScan(ids);
  });

  test("an index made after the list was filled sees everything", () {
    list.addAll([_Item("a"), _Item("b")]);
    final late = NotifyingListIndex(list, (item) => item.id);
    expect(late["b"], same(list[1]));
    expect(late.containsKey("c"), isFalse);
  });
}
