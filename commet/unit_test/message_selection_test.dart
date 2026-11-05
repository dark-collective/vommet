import 'package:commet/utils/selection_set.dart';
import 'package:test/test.dart';

// Newest first, like a timeline.
const _ordered = ["e5", "e4", "e3", "e2", "e1"];

void main() {
  group("toggle", () {
    test("ticks then unticks one message", () {
      final set = SelectionSet();
      expect(set.toggle(["e1"]), isTrue);
      expect(set.contains("e1"), isTrue);
      expect(set.lastToggled, "e1");
      expect(set.toggle(["e1"]), isFalse);
      expect(set.isEmpty, isTrue);
    });

    test("a group ticks together and counts as ticked only when whole", () {
      final set = SelectionSet();
      set.setAll(["e1"], true);
      expect(set.containsAll(["e1", "e2"]), isFalse);
      // Partly ticked: the tap ticks the rest.
      expect(set.toggle(["e1", "e2"]), isTrue);
      expect(set.containsAll(["e1", "e2"]), isTrue);
      expect(set.toggle(["e1", "e2"]), isFalse);
      expect(set.isEmpty, isTrue);
    });

    test("an empty group is never ticked", () {
      final set = SelectionSet();
      expect(set.containsAll([]), isFalse);
      expect(set.toggle([]), isFalse);
      expect(set.lastToggled, isNull);
    });
  });

  group("range", () {
    test("is inclusive and order-independent", () {
      expect(SelectionSet.range(_ordered, "e4", "e2"), ["e4", "e3", "e2"]);
      expect(SelectionSet.range(_ordered, "e2", "e4"), ["e4", "e3", "e2"]);
      expect(SelectionSet.range(_ordered, "e3", "e3"), ["e3"]);
    });

    test("is empty when an end is missing", () {
      expect(SelectionSet.range(_ordered, "e4", "gone"), isEmpty);
      expect(SelectionSet.range(_ordered, "gone", "e4"), isEmpty);
    });
  });

  group("shift+click", () {
    test("ticks everything between the last toggled and the clicked", () {
      final set = SelectionSet();
      set.toggle(["e1"]);
      set.tickRange(_ordered, ["e4"]);
      expect(set.inOrder(_ordered), ["e4", "e3", "e2", "e1"]);
      expect(set.lastToggled, "e4");
    });

    test("only ticks, even over unticked-by-hand rows", () {
      final set = SelectionSet();
      set.toggle(["e5"]);
      set.toggle(["e3"]);
      set.toggle(["e3"]); // unticked again, but now the last toggled
      set.tickRange(_ordered, ["e1"]);
      expect(set.inOrder(_ordered), ["e5", "e3", "e2", "e1"]);
    });

    test("without a last toggled row it toggles the clicked one", () {
      final set = SelectionSet();
      set.tickRange(_ordered, ["e2"]);
      expect(set.inOrder(_ordered), ["e2"]);
    });
  });

  group("drag", () {
    test("ticks every row passed, including skipped ones", () {
      final set = SelectionSet();
      set.dragStart(["e1"]);
      expect(set.dragging, isTrue);
      set.dragOver(_ordered, ["e2"]);
      set.dragOver(_ordered, ["e4"]); // fast drag skipped e3
      set.dragEnd();
      expect(set.dragging, isFalse);
      expect(set.inOrder(_ordered), ["e4", "e3", "e2", "e1"]);
    });

    test("starting on a ticked row unticks the rows passed", () {
      final set = SelectionSet();
      set.setAll(_ordered, true);
      set.dragStart(["e2"]);
      set.dragOver(_ordered, ["e4"]);
      set.dragEnd();
      expect(set.inOrder(_ordered), ["e5", "e1"]);
    });

    test("moving back unticks the rows no longer covered", () {
      final set = SelectionSet();
      set.dragStart(["e1"]);
      set.dragOver(_ordered, ["e4"]);
      set.dragOver(_ordered, ["e2"]);
      expect(set.inOrder(_ordered), ["e2", "e1"]);
      set.dragEnd();
      expect(set.inOrder(_ordered), ["e2", "e1"]);
    });

    test("moving back restores what was ticked before the drag", () {
      final set = SelectionSet();
      set.setAll(["e4"], true);
      set.dragStart(["e1"]);
      set.dragOver(_ordered, ["e5"]);
      set.dragOver(_ordered, ["e2"]);
      set.dragEnd();
      expect(set.inOrder(_ordered), ["e4", "e2", "e1"]);
    });

    test("moving past the start follows the pointer to the other side", () {
      final set = SelectionSet();
      set.dragStart(["e3"]);
      set.dragOver(_ordered, ["e5"]);
      set.dragOver(_ordered, ["e1"]);
      set.dragEnd();
      expect(set.inOrder(_ordered), ["e3", "e2", "e1"]);
    });

    test("back on the start row leaves only it flipped", () {
      final set = SelectionSet();
      set.dragStart(["e3"]);
      set.dragOver(_ordered, ["e5"]);
      set.dragOver(_ordered, ["e3"]);
      set.dragEnd();
      expect(set.inOrder(_ordered), ["e3"]);
    });

    test("does nothing outside a drag", () {
      final set = SelectionSet();
      set.dragOver(_ordered, ["e2"]);
      expect(set.isEmpty, isTrue);
    });
  });

  group("edge scroll", () {
    test("is still away from the edges", () {
      expect(SelectionSet.edgeScroll(300, 0, 600, 48), 0);
      expect(SelectionSet.edgeScroll(48, 0, 600, 48), 0);
      expect(SelectionSet.edgeScroll(552, 0, 600, 48), 0);
    });

    test("scrolls up near the top and down near the bottom", () {
      expect(SelectionSet.edgeScroll(40, 0, 600, 48), greaterThan(0));
      expect(SelectionSet.edgeScroll(560, 0, 600, 48), lessThan(0));
    });

    test("speeds up past the edge, to a limit", () {
      final near = SelectionSet.edgeScroll(40, 0, 600, 48);
      final past = SelectionSet.edgeScroll(-20, 0, 600, 48);
      expect(past, greaterThan(near));
      expect(SelectionSet.edgeScroll(-1000, 0, 600, 48), 24);
      expect(SelectionSet.edgeScroll(5000, 0, 600, 48), -24);
    });
  });

  test("inOrder follows the given order and drops unknown ids", () {
    final set = SelectionSet();
    set.setAll(["e1", "gone", "e5", "e3"], true);
    expect(set.inOrder(_ordered), ["e5", "e3", "e1"]);
    expect(set.inOrder(_ordered.reversed.toList()), ["e1", "e3", "e5"]);
  });

  test("clear empties and forgets the last toggled row", () {
    final set = SelectionSet();
    set.toggle(["e1"]);
    set.dragStart(["e2"]);
    set.clear();
    expect(set.isEmpty, isTrue);
    expect(set.lastToggled, isNull);
    expect(set.dragging, isFalse);
  });

  test("deletableCount counts what passes the check", () {
    final mine = {"e1", "e3"};
    expect(SelectionSet.deletableCount(_ordered, mine.contains), 2);
    expect(SelectionSet.deletableCount(<String>[], mine.contains), 0);
  });

  test("copyText writes one Sender: text line per message", () {
    expect(SelectionSet.copyText([("Alice", "hi"), ("Bob", "hello there")]),
        "Alice: hi\nBob: hello there");
    expect(SelectionSet.copyText([]), "");
  });

  test("copyText copies a single message without its sender", () {
    expect(SelectionSet.copyText([("Alice", "hi")]), "hi");
  });
}
