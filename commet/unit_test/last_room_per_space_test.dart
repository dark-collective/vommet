import 'package:commet/ui/pages/main/last_room_per_space.dart';
import 'package:test/test.dart';

void main() {
  test("remembers the room you left a space in", () {
    final last = LastRoomPerSpace();
    last.leave("a", "!space", roomId: "!room", roomInSpace: true);

    expect(last.lookup("a", "!space")?.roomId, "!room");
    expect(last.lookup("a", "!space")?.textView, false);
  });

  test("leaving from the main page forgets the room", () {
    final last = LastRoomPerSpace();
    last.leave("a", "!space", roomId: "!room", roomInSpace: true);
    last.leave("a", "!space");

    expect(last.lookup("a", "!space"), null);
  });

  test("a room outside the space keeps the earlier entry", () {
    final last = LastRoomPerSpace();
    last.leave("a", "!space", roomId: "!room", roomInSpace: true);
    last.leave("a", "!space", roomId: "!elsewhere", roomInSpace: false);

    expect(last.lookup("a", "!space")?.roomId, "!room");
  });

  test("keeps the voice room's chat view", () {
    final last = LastRoomPerSpace();
    last.leave("a", "!space",
        roomId: "!voice", roomInSpace: true, textView: true);

    expect(last.lookup("a", "!space")?.textView, true);
  });

  test("accounts don't share entries", () {
    final last = LastRoomPerSpace();
    last.leave("a", "!space", roomId: "!room", roomInSpace: true);

    expect(last.lookup("b", "!space"), null);
  });

  test("kept across restarts", () {
    String? saved;
    final first = LastRoomPerSpace(onChanged: (json) => saved = json);
    first.leave("a", "!space",
        roomId: "!voice", roomInSpace: true, textView: true);
    first.leave("a", "!other", roomId: "!room", roomInSpace: true);

    final next = LastRoomPerSpace(saved: saved);
    expect(next.lookup("a", "!space")?.roomId, "!voice");
    expect(next.lookup("a", "!space")?.textView, true);
    expect(next.lookup("a", "!other")?.roomId, "!room");
    expect(next.lookup("a", "!other")?.textView, false);
  });

  test("unreadable saved data starts empty", () {
    for (final bad in ["", "not json", "[]", '{"a/!s": 5}']) {
      expect(LastRoomPerSpace(saved: bad).lookup("a", "!s"), null);
    }
  });

  test("forgetting a space is saved too", () {
    String? saved;
    final last = LastRoomPerSpace(onChanged: (json) => saved = json);
    last.leave("a", "!space", roomId: "!room", roomInSpace: true);
    last.leave("a", "!space");

    expect(LastRoomPerSpace(saved: saved).lookup("a", "!space"), null);
  });

  test("keeps the most recent spaces only", () {
    String? saved;
    final last = LastRoomPerSpace(onChanged: (json) => saved = json);
    for (var i = 0; i <= LastRoomPerSpace.maxEntries; i++) {
      last.leave("a", "!s$i", roomId: "!r$i", roomInSpace: true);
    }

    final next = LastRoomPerSpace(saved: saved);
    expect(next.lookup("a", "!s0"), null);
    expect(next.lookup("a", "!s1")?.roomId, "!r1");
    expect(next.lookup("a", "!s${LastRoomPerSpace.maxEntries}")?.roomId,
        "!r${LastRoomPerSpace.maxEntries}");
  });

  test("nothing to save when nothing changed", () {
    var saves = 0;
    final last = LastRoomPerSpace(onChanged: (_) => saves++);
    last.leave("a", "!space");
    last.leave("a", "!space", roomId: "!elsewhere", roomInSpace: false);

    expect(saves, 0);
  });
}
