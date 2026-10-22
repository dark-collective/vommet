import 'package:commet/utils/room_list_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issues 290/499: Alt+Up/Down and Alt+Shift+Up/Down pick the room.
void main() {
  const rooms = ["a", "b", "c", "d"];
  bool unread(String r) => r == "a" || r == "d";

  test("next and previous room", () {
    expect(RoomListNavigation.step(rooms, "b", forward: true), "c");
    expect(RoomListNavigation.step(rooms, "b", forward: false), "a");
  });

  test("stops at either end instead of wrapping", () {
    expect(RoomListNavigation.step(rooms, "d", forward: true), isNull);
    expect(RoomListNavigation.step(rooms, "a", forward: false), isNull);
  });

  test("with no open room in the list, starts from the first or last", () {
    expect(RoomListNavigation.step(rooms, null, forward: true), "a");
    expect(RoomListNavigation.step(rooms, null, forward: false), "d");
    expect(RoomListNavigation.step(rooms, "x", forward: true), "a");
    expect(RoomListNavigation.step(rooms, "x", forward: false), "d");
  });

  test("unread rooms skip the read ones", () {
    expect(
        RoomListNavigation.step(rooms, "b", forward: true, where: unread), "d");
    expect(RoomListNavigation.step(rooms, "c", forward: false, where: unread),
        "a");
    expect(RoomListNavigation.step(rooms, "d", forward: true, where: unread),
        isNull);
  });

  test("empty list", () {
    expect(RoomListNavigation.step(<String>[], null, forward: true), isNull);
  });
}
