// Vommet: New Home's Overview builds a card's rows only as they scroll into
// view. Before, the whole page was one Column, so the Standalone rooms card
// kept a live RoomPanel per standalone room (+80 MB peak memory at 250 rooms).
// The look is unchanged: a card as a sliver lays out exactly like the box.
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/room_panel.dart';
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

const roomCount = 1000;

String roomId(int i) => "!standalone$i:example.com";

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

Iterable<Element> builtRows() =>
    find.byType(RoomPanel, skipOffstage: false).evaluate();

/// A row that remembers the label it was first built with.
class _Row extends StatefulWidget {
  const _Row(this.label, {super.key, this.width});
  final String label;
  final double? width;
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  late final String born = widget.label;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: widget.width,
      height: 30 + widget.label.length.toDouble(),
      child: Text(born));
}

NewHomeCard card(List<Widget> rows, {String? empty}) => NewHomeCard(
    title: "Standalone rooms",
    menu: const SizedBox(),
    empty: empty,
    lazyRows: true,
    children: rows);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;
  late ClientManager manager;

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient("new-home-lazy");
    await sync(client, join: {
      for (var r = 0; r < roomCount; r++)
        roomId(r): joined(roomId(r), name: "Room $r"),
    });
    manager = ClientManager();
    manager.clients.add(client);
  });

  tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

  Future<void> pumpOverview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NewHomeOverview(
            clientManager: manager, filterClient: null, phone: false),
      ),
    ));
  }

  testWidgets("1000 standalone rooms: only a screenful of rows is built",
      (tester) async {
    // The card's order: newest first.
    final ordered = manager.singleRooms()
      ..sort((a, b) => b.lastEventTimestamp.compareTo(a.lastEventTimestamp));
    expect(ordered.length, roomCount);
    final first = ordered.first.displayName, last = ordered.last.displayName;
    showCards([HomeLayout.otherRooms, HomeLayout.invites]);
    await pumpOverview(tester);

    final atTop = builtRows().length;
    expect(atTop, greaterThan(5));
    expect(atTop, lessThan(60));
    expect(find.text("Standalone rooms"), findsOneWidget);
    expect(find.text(first), findsOneWidget);
    expect(find.text(last, skipOffstage: false), findsNothing);

    // Scrolled to the end: the oldest room and the Add a card tile, still
    // only a screenful of rows. (The list's length is an estimate until its
    // end has been laid out, so jump again until it settles.)
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    for (var i = 0; i < 10; i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      if (position.pixels == position.maxScrollExtent) break;
    }
    expect(find.text(last), findsOneWidget);
    expect(find.text(first, skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey("NewHomeAddCardTile")), findsOneWidget);
    expect(builtRows().length, lessThan(60));
  });

  testWidgets("customize mode still shows every card's rows", (tester) async {
    showCards([HomeLayout.otherRooms]);
    newHomeCustomizing.value = true;
    addTearDown(() => newHomeCustomizing.value = false);
    await pumpOverview(tester);
    expect(find.text("Standalone rooms"), findsOneWidget);
    expect(
        find.byKey(const ValueKey("NewHomeCard-other_rooms")), findsOneWidget);
  });

  testWidgets("a card as a sliver lays out exactly like the box",
      (tester) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    List<Widget> rows() => [
          for (var i = 0; i < 8; i++)
            _Row("row $i", key: ValueKey("r$i"), width: i.isEven ? 220 : null),
        ];

    Map<String, Rect> rects() => {
          for (var i = 0; i < 8; i++)
            "r$i": tester.getRect(find.byKey(ValueKey("r$i"))),
          "title": tester.getRect(find.text("Standalone rooms")),
        };

    // The old Overview: a ListView holding a Column of cards.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(8), children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: card(rows())),
          ]),
        ]),
      ),
    ));
    final box = rects();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverMainAxisGroup(slivers: [
              SliverPadding(
                  padding: const EdgeInsets.only(bottom: 12),
                  sliver: NewHomeCardSliver(card(rows()))),
            ]),
          ),
        ]),
      ),
    ));
    expect(find.byType(NewHomeCardSliver), findsOneWidget);
    expect(rects(), box);
  });

  testWidgets("an empty lazy card shows its note", (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          NewHomeCardSliver(card(const [], empty: "Nothing here.")),
        ]),
      ),
    ));
    expect(find.text("Nothing here."), findsOneWidget);
  });

  testWidgets("rows keep their state when the list reorders", (tester) async {
    Widget page(List<int> order) => MaterialApp(
          home: Scaffold(
            body: CustomScrollView(slivers: [
              NewHomeCardSliver(card([
                for (final i in order) _Row("row $i", key: ValueKey("r$i")),
              ])),
            ]),
          ),
        );
    await tester.pumpWidget(page([0, 1, 2, 3]));
    await tester.pumpWidget(page([3, 2, 1, 0]));
    for (var i = 0; i < 4; i++) {
      expect(
          find.descendant(
              of: find.byKey(ValueKey("r$i")), matching: find.text("row $i")),
          findsOneWidget);
    }
    // The top row is now row 3.
    expect(tester.getRect(find.byKey(const ValueKey("r3"))).top,
        lessThan(tester.getRect(find.byKey(const ValueKey("r0"))).top));
  });
}
