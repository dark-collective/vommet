import 'package:commet/ui/organisms/room_quick_access_menu/room_actions_bar.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RoomActionPlace place(IconData icon) => RoomActionsBar.placeOf(
      RoomQuickAccessMenuEntry(name: "x", action: null, icon: icon));

  test('the top row keeps Invite, Call, Search (and desktop\'s panel toggle)',
      () {
    for (final icon in [
      Icons.person_add,
      Icons.call,
      Icons.search,
      Icons.chevron_left,
      Icons.chevron_right,
    ]) {
      expect(place(icon), RoomActionPlace.row, reason: "$icon");
    }
  });

  test('pins and threads leave the row: the member panel has tabs for them',
      () {
    expect(place(Icons.push_pin), RoomActionPlace.tab);
    expect(place(Icons.forum_outlined), RoomActionPlace.tab);
  });

  test('widgets, calendar, classic call and anything new go in the ▾ menu', () {
    expect(place(Icons.widgets), RoomActionPlace.menu);
    expect(place(Icons.calendar_month), RoomActionPlace.menu);
    expect(place(Icons.phone_callback), RoomActionPlace.menu);
    expect(place(Icons.star), RoomActionPlace.menu);
  });
}
