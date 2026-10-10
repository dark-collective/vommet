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
}
