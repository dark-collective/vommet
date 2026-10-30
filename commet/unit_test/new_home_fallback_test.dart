// Vommet (New Home): "Add it to a tab" on the page People or the Rooms
// browser opens on when no Home tab holds it (Vommet issue 607).
import 'package:commet/ui/organisms/new_home/new_home_fallback.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final withoutPeople = HomeTabs.defaults.removeTab(HomeTabs.people);

  test("onto an existing tab: added at the bottom of its main page", () {
    expect(withoutPeople.tabHolding(HomeLayout.peoplePage), isNull);
    final (next, id) = addBlockToTab(withoutPeople, HomeLayout.peoplePage,
        tabId: HomeTabs.overview);
    expect(id, HomeTabs.overview);
    final overview = next.tab(HomeTabs.overview)!;
    expect(overview.main.visible.last.type, HomeLayout.peoplePage);
    expect(next.tabHolding(HomeLayout.peoplePage)?.id, HomeTabs.overview);
    expect(next.tabs.length, withoutPeople.tabs.length);
  });

  test("a new tab brings back the removed default tab that held it", () {
    final (next, id) = addBlockToTab(withoutPeople, HomeLayout.peoplePage);
    expect(id, HomeTabs.people);
    expect(next.tab(HomeTabs.people)?.name, "People");
    expect(next.tabHolding(HomeLayout.peoplePage)?.id, HomeTabs.people);
  });

  test("a new tab when no removed default held it", () {
    // The Rooms browser moved off its tab: the Rooms tab is still there.
    final rooms = HomeTabs.defaults.tab(HomeTabs.rooms)!;
    final moved = HomeTabs.defaults.replaceTab(rooms.copyWith(
        main: rooms.main.remove(rooms.main.visible
            .firstWhere((c) => c.type == HomeLayout.roomsPage)
            .id)));
    expect(moved.tabHolding(HomeLayout.roomsPage), isNull);
    final (next, id) = addBlockToTab(moved, HomeLayout.roomsPage);
    expect(next.tabs.length, moved.tabs.length + 1);
    expect(next.tab(id)?.name, "Rooms browser");
    expect(next.tabHolding(HomeLayout.roomsPage)?.id, id);
  });
}
