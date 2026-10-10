import 'package:commet/utils/media_group.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime(2026, 10, 5, 12);

  // Builds a newest-first timeline from oldest-first specs.
  MediaGroupPosition Function(int) timeline(
      List<(String, int, bool)> oldestFirst) {
    final events = [
      for (final (sender, sec, ok) in oldestFirst.reversed)
        MediaGroupMember(sender, t0.add(Duration(seconds: sec)), groupable: ok)
    ];
    return (i) => MediaGroups.position(i, (j) => events[j], events.length);
  }

  test("four photos in a row: oldest is root, the rest are children", () {
    final pos = timeline(
        [("a", 0, true), ("a", 5, true), ("a", 6, true), ("a", 9, true)]);
    // index 3 is the oldest
    final root = pos(3);
    expect(root.role, MediaGroupRole.root);
    expect(root.members, [3, 2, 1, 0]);
    for (final i in [0, 1, 2]) {
      expect(pos(i).role, MediaGroupRole.child);
      expect(pos(i).rootIndex, 3);
    }
  });

  test("a single photo is not grouped", () {
    final pos = timeline([("a", 0, true)]);
    expect(pos(0).role, MediaGroupRole.none);
  });

  test("different senders, long gaps and non-media break runs", () {
    final pos = timeline([
      ("a", 0, true),
      ("b", 1, true), // other sender
      ("b", 2, true),
      ("b", 200, true), // > 60 s later
      ("b", 201, false), // text message / captioned / reacted
      ("b", 202, true),
    ]);
    // newest-first indices: 5:a0 4:b1 3:b2 2:b200 1:b201(no) 0:b202
    expect(pos(5).role, MediaGroupRole.none);
    expect(pos(4).role, MediaGroupRole.root);
    expect(pos(4).members, [4, 3]);
    expect(pos(3).role, MediaGroupRole.child);
    expect(pos(2).role, MediaGroupRole.none);
    expect(pos(1).role, MediaGroupRole.none);
    expect(pos(0).role, MediaGroupRole.none);
  });

  test("runs longer than maxSize split into groups of maxSize", () {
    final n = MediaGroups.maxSize + 3;
    final pos = timeline([for (var i = 0; i < n; i++) ("a", i, true)]);
    final oldest = n - 1;
    expect(pos(oldest).role, MediaGroupRole.root);
    expect(pos(oldest).members.length, MediaGroups.maxSize);
    final secondRoot = oldest - MediaGroups.maxSize;
    expect(pos(secondRoot).role, MediaGroupRole.root);
    expect(
        pos(secondRoot).members, [secondRoot, secondRoot - 1, secondRoot - 2]);
    expect(pos(0).rootIndex, secondRoot);
  });

  test("a lone leftover after a full group is not grouped", () {
    final n = MediaGroups.maxSize + 1;
    final pos = timeline([for (var i = 0; i < n; i++) ("a", i, true)]);
    expect(pos(0).role, MediaGroupRole.none);
    expect(pos(n - 1).members.length, MediaGroups.maxSize);
  });

  test("runExtent covers the whole run, past the groups of ten", () {
    final events = [
      for (var s = 11; s >= 0; s--)
        MediaGroupMember("a", t0.add(Duration(seconds: s)), groupable: true),
      MediaGroupMember("a", t0, groupable: false), // index 12: text
    ];
    at(int j) => events[j];
    // index 0 is the newest picture, 11 the oldest; 12 doesn't join.
    expect(MediaGroups.runExtent(5, at, events.length), (0, 11));
    expect(MediaGroups.runExtent(0, at, events.length), (0, 11));
    expect(MediaGroups.runExtent(12, at, events.length), (12, 12));
    // The run is split into two groups, yet a refresh of the run reaches
    // both roots and every child.
    expect(
        MediaGroups.position(11, at, events.length).role, MediaGroupRole.root);
    expect(
        MediaGroups.position(1, at, events.length).role, MediaGroupRole.root);
  });
}
