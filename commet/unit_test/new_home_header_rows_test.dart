// Vommet: New Home's controls don't waste rows. Rooms' "Collapse all" sits
// in the first section's header (it had a row of its own, Vommet issue 846),
// People's "Add contact" sits beside "Search contacts" (it had a row of its
// own above the field, Vommet issue 847), and Overview's "Add a card" tile
// only shows on a page with no cards (the header's Customize does the same).
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_overview.dart';
import 'package:commet/ui/organisms/new_home/new_home_people.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_model.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

/// Home's first tab showing just [cards] (by type).
void showCards(List<String> cards) {
  final tabs = HomeTabs.parse({
    "version": HomeTabs.version,
    "tabs": [
      {
        "id": HomeTabs.overview,
        "cards": [
          for (final card in cards) {"id": card}
        ],
      }
    ],
  });
  newHomeTab.value = HomeTabs.overview;
  HomeLayoutStore.instance.tabs.value = tabs;
  HomeLayoutStore.instance.layout.value = tabs.tabs.first.main;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;
  late ClientManager manager;

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient("new-home-header-rows");
    await sync(client, join: {
      for (var r = 0; r < 3; r++)
        "!standalone$r:example.com":
            joined("!standalone$r:example.com", name: "Room $r"),
    });
    manager = ClientManager();
    manager.clients.add(client);
  });

  tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
    await tester.pump();
  }

  testWidgets("Rooms: Collapse all is on the Standalone rooms header line",
      (tester) async {
    await pump(tester,
        NewHomeRooms(clientManager: manager, filterClient: null, phone: false));
    final collapse = find.byKey(const ValueKey("NewHomeRoomsCollapseAll"));
    expect(collapse, findsOneWidget);
    final header = tester.getRect(find.text("Standalone rooms"));
    final button = tester.getRect(collapse);
    expect(button.center.dy, moreOrLessEquals(header.center.dy, epsilon: 2));
    expect(button.left, greaterThan(header.right));
    // Below the search field, not on a row between it and the tree.
    final search =
        tester.getRect(find.byKey(const ValueKey("NewHomeRoomsSearch")));
    expect(button.top, greaterThan(search.bottom));

    await tester.tap(collapse);
    await tester.pump();
    expect(find.text("Expand all"), findsOneWidget);
    expect(find.text("Room 0"), findsNothing);
    await tester.tap(collapse);
    await tester.pump();
    expect(find.text("Collapse all"), findsOneWidget);
    expect(find.text("Room 0"), findsOneWidget);
  });

  for (final only in [null, PeopleTab.contacts]) {
    testWidgets("People (only: $only): Add contact beside Search contacts",
        (tester) async {
      newHomePeopleTab.value = PeopleTab.contacts;
      await pump(
          tester,
          PeopleView(
              clientManager: manager,
              filterClient: null,
              phone: false,
              only: only));
      final search =
          tester.getRect(find.byKey(const ValueKey("NewHomePeopleSearch")));
      final add =
          tester.getRect(find.byKey(const ValueKey("NewHomePeopleAdd")));
      expect(add.center.dy, moreOrLessEquals(search.center.dy, epsilon: 2));
      expect(add.left, greaterThan(search.right));
      // The field leaves room for the button instead of spanning the page.
      expect(search.width, lessThan(1200 - 40 - add.width));
      // Let the invites refresh PeopleView schedules on open run out.
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets("Overview: no Add a card tile on a page with cards",
      (tester) async {
    showCards([HomeLayout.otherRooms]);
    await pump(
        tester,
        NewHomeOverview(
            clientManager: manager, filterClient: null, phone: false));
    expect(find.text("Standalone rooms"), findsOneWidget);
    expect(find.byKey(const ValueKey("NewHomeAddCardTile")), findsNothing);
  });

  testWidgets("Overview: an empty page still offers Add a card",
      (tester) async {
    showCards([]);
    await pump(
        tester,
        NewHomeOverview(
            clientManager: manager, filterClient: null, phone: false));
    expect(find.byKey(const ValueKey("NewHomeAddCardTile")), findsOneWidget);
  });
}
