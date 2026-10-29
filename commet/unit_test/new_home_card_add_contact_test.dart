// Vommet: the Overview's People and Contacts cards have an "Add contact"
// button in their header. The People card shows no search line (where the
// page keeps Add contact), so an empty card would otherwise offer no way to
// add anyone.
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_overview.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

/// Home's first tab showing [cards] under a Recent card (a People card
/// alone on a page shows as the whole People page, not as a card).
void showCards(List<Map<String, dynamic>> cards) {
  cards = [
    {"id": HomeLayout.recent},
    ...cards
  ];
  final tabs = HomeTabs.parse({
    "version": HomeTabs.version,
    "tabs": [
      {"id": HomeTabs.overview, "cards": cards}
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
    client = await signedInClient("new-home-card-add-contact");
    await sync(client, join: {
      "!lobby:example.com": joined("!lobby:example.com", name: "Lobby"),
    });
    manager = ClientManager();
    manager.clients.add(client);
  });

  tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: NewHomeOverview(
                clientManager: manager, filterClient: null, phone: false))));
    // The People card fills in over a few frames.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  final add = find.byKey(const ValueKey("NewHomeCardAddContact"));

  for (final card in [
    {"id": HomeLayout.peoplePage},
    {"id": HomeLayout.peoplePage, "part": "contacts"},
    {"id": HomeLayout.contacts},
  ]) {
    testWidgets("$card: an empty card has Add contact in its header",
        (tester) async {
      showCards([card]);
      await pump(tester);
      expect(add, findsOneWidget);
      await tester.tap(add);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text("Add contact"), findsWidgets);
      // Let the invites refresh the People card schedules run out.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets("customize mode hides Add contact", (tester) async {
    showCards([
      {"id": HomeLayout.peoplePage}
    ]);
    newHomeCustomizing.value = true;
    addTearDown(() => newHomeCustomizing.value = false);
    await pump(tester);
    expect(add, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  for (final part in ["invites", "blocked"]) {
    testWidgets("People card showing $part: no Add contact", (tester) async {
      showCards([
        {"id": HomeLayout.peoplePage, "part": part}
      ]);
      await pump(tester);
      expect(add, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
