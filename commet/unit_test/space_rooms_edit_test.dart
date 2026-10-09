import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/ui/pages/manage_space_rooms/space_rooms_edit.dart';
import 'package:test/test.dart';

SpaceRoomsEdit start() => SpaceRoomsEdit({
      "root": ["lobby", "rules", "workshop", "art"],
      "workshop": ["pebble", "bridge"],
      "bridge": ["voice", "feed"],
      "art": ["sketch"],
    });

void main() {
  test("no edits, no operations", () {
    expect(start().plan(), isEmpty);
    expect(start().hasChanges, isFalse);
  });

  test("reorder within a space is one order operation", () {
    final e = start()..reorder("root", 0, 2); // lobby after rules
    expect(e.childrenOf("root"), ["rules", "lobby", "workshop", "art"]);
    final ops = e.plan();
    expect(ops, hasLength(1));
    expect((ops.single as OrderChildrenOp).children,
        ["rules", "lobby", "workshop", "art"]);
    expect(e.summary(), "1 change: 1 reordered");
  });

  test("move up and down", () {
    final e = start()
      ..moveDown("bridge", "voice")
      ..moveUp("root", "rules");
    expect(e.childrenOf("bridge"), ["feed", "voice"]);
    expect(e.childrenOf("root").first, "rules");
  });

  test("removal is undoable and only removes on save", () {
    final e = start()..remove("root", "rules");
    expect(e.isRemoved("root", "rules"), isTrue);
    expect(e.childrenOf("root"), contains("rules"));
    expect(e.plan().single, isA<RemoveChildOp>());
    expect(e.summary(), "1 change: 1 removed");
    e.undoRemove("root", "rules");
    expect(e.plan(), isEmpty);
  });

  test("moving between subspaces adds before it removes", () {
    final e = start()..moveTo("feed", "bridge", "art");
    expect(e.isMovedIn("art", "feed"), isTrue);
    final ops = e.plan();
    expect(ops.first, isA<AddChildOp>());
    expect(ops.last, isA<RemoveChildOp>());
    expect(ops.whereType<OrderChildrenOp>(), isEmpty,
        reason: "appended at the end, no explicit order needed");
    expect(e.summary(), "1 change: 1 moved");
  });

  test("a moved child placed before others gets an order", () {
    final e = start()
      ..moveTo("feed", "bridge", "art")
      ..moveUp("art", "feed");
    final ops = e.plan();
    final add = ops.indexWhere((o) => o is AddChildOp);
    final order = ops.indexWhere((o) => o is OrderChildrenOp);
    final remove = ops.indexWhere((o) => o is RemoveChildOp);
    expect(add < order && order < remove, isTrue, reason: "$ops");
    expect((ops[order] as OrderChildrenOp).children, ["feed", "sketch"]);
  });

  test("moving into a space that already has it just takes it out", () {
    final e = SpaceRoomsEdit({
      "a": ["x"],
      "b": ["x", "y"],
    })
      ..moveTo("x", "a", "b");
    expect(e.childrenOf("b"), ["x", "y"]);
    expect(e.plan().single, isA<RemoveChildOp>());
  });

  test("removing a child doesn't reorder the rest", () {
    final e = start()..remove("root", "lobby");
    expect(e.plan().whereType<OrderChildrenOp>(), isEmpty);
  });

  test("commit makes the edit the new start", () {
    final e = start()
      ..remove("root", "rules")
      ..moveTo("feed", "bridge", "art")
      ..commit();
    expect(e.plan(), isEmpty);
    expect(e.childrenOf("root"), ["lobby", "workshop", "art"]);
    expect(e.childrenOf("art"), ["sketch", "feed"]);
  });

  test("a move remembers where it came from", () {
    final e = start()..moveTo("feed", "bridge", "art");
    expect((e.plan().first as AddChildOp).from, "bridge");
  });

  test("moving into a space that already has it counts as a move", () {
    final e = SpaceRoomsEdit({
      "a": ["x"],
      "b": ["x", "y"],
    })
      ..moveTo("x", "a", "b");
    expect(e.summary(), "1 change: 1 moved");
  });

  test("move up skips crossed-out neighbours", () {
    final e = start()
      ..remove("root", "rules")
      ..moveUp("root", "workshop");
    // Rules (crossed out) sat between Lobby and Workshop: Workshop jumps
    // over it and swaps with Lobby.
    expect(e.childrenOf("root"), ["workshop", "lobby", "rules", "art"]);
    expect(e.plan().whereType<OrderChildrenOp>().single.children,
        ["workshop", "lobby", "art"]);
  });

  test("a subspace being removed isn't reachable as a move target", () {
    final e = start()..remove("root", "workshop");
    expect(e.reachable("root"), isNot(contains("workshop")));
    expect(e.reachable("root"), isNot(contains("bridge")),
        reason: "inside the removed subspace");
    expect(e.reachable("root"), contains("art"));
  });

  test("a space that contains itself doesn't loop", () {
    final e = SpaceRoomsEdit({
      "root": ["s"],
      "s": ["root", "x"],
    });
    expect(e.reachable("root"), {"root", "s"});
  });

  group("mergeChildOrder", () {
    test("hidden children keep their slots", () {
      // h1, h2 aren't joined, so the app can't show them.
      expect(
          MatrixSpace.mergeChildOrder(
              ["a", "h1", "b", "h2", "c"], ["c", "a", "b"]),
          ["c", "h1", "a", "h2", "b"]);
    });
    test("a just-added child goes at the end", () {
      expect(MatrixSpace.mergeChildOrder(["a", "h", "b"], ["b", "a", "new"]),
          ["b", "h", "a", "new"]);
    });
  });
}
