// Vommet: the space join picker's tree (paging, caps, loops, tri-state
// selection) and the background join queue. No network: a fake hierarchy.

import 'package:commet/utils/space_hierarchy/room_action_queue.dart';
import 'package:commet/utils/space_hierarchy/space_tree.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHierarchy {
  final Map<String, HierarchyRoomInfo> rooms = {};
  final Map<String, List<String>> children = {};
  final List<(String, int)> requests = [];

  void space(String id, List<String> kids, {Set<String> suggested = const {}}) {
    children[id] = kids;
    rooms[id] =
        HierarchyRoomInfo(roomId: id, name: id, roomType: "m.space", children: [
      for (final k in kids)
        HierarchyChildLink(k,
            suggested: suggested.contains(k), via: const ["example.org"])
    ]);
  }

  void room(String id, {String? type}) {
    rooms[id] = HierarchyRoomInfo(roomId: id, name: id, roomType: type);
  }

  Future<HierarchyPage> fetch(String spaceId,
      {String? from, required int limit}) async {
    requests.add((spaceId, limit));
    expect(limit, lessThanOrEqualTo(SpaceTree.pageSize));
    final kids = children[spaceId] ?? const [];
    final start = from == null ? 0 : int.parse(from);
    final page = <HierarchyRoomInfo>[];
    var room = limit;
    if (from == null) {
      page.add(rooms[spaceId]!);
      room--;
    }
    final end = (start + room).clamp(0, kids.length);
    for (var i = start; i < end; i++) {
      page.add(rooms[kids[i]]!);
    }
    return HierarchyPage(page, nextBatch: end < kids.length ? "$end" : null);
  }
}

SpaceTree treeOf(FakeHierarchy h, {Set<String> joined = const {}}) => SpaceTree(
    spaceId: "!root", fetch: h.fetch, isJoined: (id) => joined.contains(id));

List<String> roomsNamed(String prefix, int n) =>
    [for (var i = 0; i < n; i++) "$prefix$i"];

void main() {
  test('pages of 50 until the space is loaded', () async {
    final h = FakeHierarchy();
    final kids = roomsNamed("!r", 120);
    kids.forEach(h.room);
    h.space("!root", kids);

    final tree = treeOf(h);
    await tree.loadRoot();

    expect(tree.root.children.map((n) => n.roomId), kids);
    expect(tree.loadedCount, 120);
    expect(h.requests.length, 3);
    expect(tree.canLoadMore, false);
  });

  test('stops at 500 per Load more and 5,000 in total', () async {
    final h = FakeHierarchy();
    final kids = roomsNamed("!r", 6000);
    kids.forEach(h.room);
    h.space("!root", kids);

    final tree = treeOf(h);
    await tree.loadRoot();
    expect(tree.loadedCount, 500);
    expect(tree.canLoadMore, true);

    await tree.loadMore();
    expect(tree.loadedCount, 1000);

    for (var i = 0; i < 20; i++) {
      await tree.loadMore();
    }
    expect(tree.loadedCount, SpaceTree.totalCap);
    expect(tree.canLoadMore, false);
    expect(tree.hitTotalCap, true);
    expect(tree.root.children.length, SpaceTree.totalCap);
  });

  test('subspaces load only when opened', () async {
    final h = FakeHierarchy();
    h.room("!a");
    h.room("!b");
    h.space("!sub", ["!a", "!b"]);
    h.space("!root", ["!sub"]);

    final tree = treeOf(h);
    await tree.loadRoot();
    expect(h.requests.map((r) => r.$1), ["!root"]);
    final sub = tree.node("!sub")!;
    expect(sub.children, isEmpty);
    expect(sub.childCount, 2);

    await tree.expand(sub);
    expect(sub.children.map((n) => n.roomId), ["!a", "!b"]);
    expect(tree.visibleRows().map((n) => n.roomId), ["!sub", "!a", "!b"]);
  });

  test('a space inside itself and a room listed twice show once', () async {
    final h = FakeHierarchy();
    h.room("!r");
    h.space("!loop", ["!root", "!r", "!loop"]);
    h.space("!root", ["!loop", "!r"]);

    final tree = treeOf(h);
    await tree.loadRoot();
    final loop = tree.node("!loop")!;
    await tree.expand(loop);

    // !r already sits under the root; !root and !loop are already shown.
    expect(loop.children, isEmpty);
    expect(tree.visibleRows().map((n) => n.roomId), ["!loop", "!r"]);
    expect(tree.loadedCount, 2);
  });

  test('nesting deeper than 8 levels is not opened', () async {
    final h = FakeHierarchy();
    for (var i = 12; i > 0; i--) {
      h.space("!s$i", i == 12 ? [] : ["!s${i + 1}"]);
    }
    h.space("!root", ["!s1"]);

    final tree = treeOf(h);
    await tree.loadRoot();
    var n = tree.node("!s1")!;
    while (tree.canExpand(n)) {
      await tree.expand(n);
      n = n.children.single;
    }
    expect(n.depth, SpaceTree.maxDepth);
    expect(tree.node("!s9"), isNull);
  });

  test('suggested rooms are ticked by default, joined ones never', () async {
    final h = FakeHierarchy();
    ["!welcome", "!general", "!offtopic", "!lfg", "!screens"].forEach(h.room);
    h.room("!voice", type: "org.matrix.msc3417.call");
    h.space("!gaming", ["!lfg", "!voice", "!screens"],
        suggested: {"!lfg", "!voice"});
    h.space("!root", ["!welcome", "!general", "!gaming", "!offtopic"],
        suggested: {"!welcome", "!general", "!gaming"});

    final tree = treeOf(h, joined: {"!welcome"});
    await tree.loadRoot();

    expect(tree.selected, {"!general", "!gaming", "!lfg", "!voice"});
    final gaming = tree.node("!gaming")!;
    expect(gaming.expanded, true);
    expect(tree.stateOf(gaming), isNull); // !screens isn't ticked
    expect(tree.stateOf(tree.node("!welcome")!), true); // joined
    expect(tree.selectable(tree.node("!welcome")!), false);

    tree.toggle(gaming);
    expect(tree.stateOf(gaming), true);
    expect(
        tree.selected, containsAll(["!gaming", "!lfg", "!voice", "!screens"]));

    tree.toggle(tree.node("!screens")!);
    expect(tree.stateOf(gaming), isNull);

    tree.toggle(gaming);
    expect(tree.stateOf(gaming), true);
    tree.toggle(gaming);
    expect(tree.stateOf(gaming), false);
    expect(tree.selected, {"!general"});

    tree.selectNone();
    expect(tree.selected, isEmpty);
    tree.selectSuggested();
    expect(tree.selected, {"!general", "!gaming", "!lfg", "!voice"});

    // Tree order: a subspace before its rooms.
    expect(tree.selectedInOrder.map((n) => n.roomId),
        ["!general", "!gaming", "!lfg", "!voice"]);
    expect(tree.viaFor(tree.node("!lfg")!), ["example.org"]);
  });

  test('ticking an unopened subspace ticks its rooms as they load', () async {
    final h = FakeHierarchy();
    h.room("!a");
    h.room("!b");
    h.space("!sub", ["!a", "!b"]);
    h.space("!root", ["!sub"]);

    final tree = treeOf(h, joined: {"!b"});
    await tree.loadRoot();
    tree.toggle(tree.node("!sub")!);
    expect(tree.selected, {"!sub"});
    await tree.expand(tree.node("!sub")!);
    expect(tree.selected, {"!sub", "!a"});
    expect(tree.stateOf(tree.node("!sub")!), true);
  });

  test('select all ticks at most 100 and stays within the batch', () async {
    final h = FakeHierarchy();
    final hubs = roomsNamed("!hub", 20);
    for (final hub in hubs) {
      final kids = roomsNamed("$hub-r", 50);
      kids.forEach(h.room);
      h.space(hub, kids);
    }
    h.space("!root", hubs);

    final tree = treeOf(h);
    await tree.loadRoot();
    expect(tree.loadedCount, 20);

    await tree.selectAll();
    // 20 hubs + their rooms, but never past the first 500 entries.
    expect(tree.loadedCount, lessThanOrEqualTo(SpaceTree.batchCap));
    expect(tree.selected.length, SpaceTree.actionCap);
    expect(tree.truncatedFrom, tree.loadedCount);
    expect(tree.canLoadMore, true);

    final calls = h.requests.length;
    await tree.selectAll();
    expect(h.requests.length, calls); // nothing left in this batch
  });

  test('filter keeps matches and the subspaces they sit in', () async {
    final h = FakeHierarchy();
    ["!routes", "!pb", "!general"].forEach(h.room);
    h.space("!speed", ["!routes", "!pb"]);
    h.space("!root", ["!general", "!speed"]);

    final tree = treeOf(h);
    await tree.loadRoot();
    await tree.expand(tree.node("!speed")!);
    expect(tree.visibleRows(filter: "rout").map((n) => n.roomId),
        ["!speed", "!routes"]);
  });

  group('RoomActionQueue', () {
    test('runs two at a time', () async {
      var running = 0;
      var peak = 0;
      final queue = RoomActionQueue<int>(
        items: List.generate(7, (i) => i),
        run: (i) async {
          running++;
          if (running > peak) peak = running;
          await Future.delayed(const Duration(milliseconds: 2));
          running--;
        },
      );
      await queue.start();
      expect(peak, 2);
      expect(queue.done, 7);
      expect(queue.failures, isEmpty);
    });

    test('backs off and retries when rate limited', () async {
      final waits = <Duration>[];
      var tries = 0;
      final queue = RoomActionQueue<String>(
        items: ["!a"],
        run: (_) async {
          if (tries++ < 2) throw "slow down";
        },
        retryAfter: (e) => e == "slow down" ? Duration.zero : null,
        sleep: (d) async => waits.add(d),
      );
      await queue.start();
      expect(tries, 3);
      expect(queue.failures, isEmpty);
      expect(waits.where((w) => w > Duration.zero), isNotEmpty);
    });

    test('other errors fail the item without stopping the rest', () async {
      final queue = RoomActionQueue<String>(
        items: ["!a", "!b", "!c"],
        run: (id) async {
          if (id == "!b") throw "forbidden";
        },
        retryAfter: (_) => null,
      );
      await queue.start();
      expect(queue.done, 3);
      expect(queue.failures.map((f) => f.item), ["!b"]);
    });

    test('the last item waits for the others (space left last)', () async {
      final finished = <String>[];
      final queue = RoomActionQueue<String>(
        items: ["!a", "!b", "!c", "!space"],
        lastAlone: true,
        run: (id) async {
          await Future.delayed(Duration(milliseconds: id == "!a" ? 20 : 1));
          finished.add(id);
        },
      );
      await queue.start();
      expect(finished.last, "!space");
    });

    test('cancel stops new work', () async {
      late RoomActionQueue<int> queue;
      queue = RoomActionQueue<int>(
        items: List.generate(10, (i) => i),
        run: (i) async {
          if (i == 1) queue.cancel();
        },
      );
      await queue.start();
      expect(queue.done, lessThan(10));
    });
  });
}
