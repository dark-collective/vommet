// Vommet: New Home's Overview builds a card's rows only as they scroll into
// view. Before, the whole page was one Column, so the Standalone rooms card
// kept a live RoomPanel per standalone room (+80 MB peak memory at 250 rooms).
// The look is unchanged: a card as a sliver lays out exactly like the box.
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_overview.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    // Scrolled to the end: the oldest room (no Add a card tile: the page
    // has cards), still only a screenful of rows. (The list's length is an estimate until its
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
    expect(find.byKey(const ValueKey("NewHomeAddCardTile")), findsNothing);
    expect(builtRows().length, lessThan(60));
  });

  Room? focusedRoom() => FocusManager.instance.primaryFocus?.context
      ?.findAncestorWidgetOfExactType<RoomPanel>()
      ?.room;

  testWidgets("Tab walks the rows in order, building them as it goes",
      (tester) async {
    final ordered = manager.singleRooms()
      ..sort((a, b) => b.lastEventTimestamp.compareTo(a.lastEventTimestamp));
    showCards([HomeLayout.otherRooms]);
    await pumpOverview(tester);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    final seen = <Room>[];
    var last = 0.0;
    for (var i = 0; i < 45; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      // Never a jump ahead (to the Add a card tile at the end).
      expect(position.pixels, greaterThanOrEqualTo(last));
      expect(position.pixels - last, lessThan(100));
      last = position.pixels;
      if (focusedRoom() case final room?) seen.add(room);
    }
    // Every row once, in the card's order, well past the first screenful.
    expect(seen.length, greaterThan(40));
    expect(seen, ordered.take(seen.length).toList());
    expect(builtRows().length, lessThan(60));

    // Shift+Tab walks back up, row by row.
    for (var i = 0; i < 9; i++) {
      final from = focusedRoom();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(focusedRoom(), seen[seen.indexOf(from!) - 1]);
    }

    // The focused row stays focused (and built) when scrolled far away.
    final focused = focusedRoom();
    expect(focused, isNotNull);
    position.jumpTo(position.pixels + 5000);
    await tester.pump();
    expect(focusedRoom(), focused);
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
    // The plain boxes, as before: drag and drop measures whole cards.
    expect(find.byType(NewHomeCardSliver), findsNothing);
    expect(builtRows().length, roomCount);
  });

  testWidgets("a card as a sliver lays out exactly like the box",
      (tester) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 8 rows, one row, no rows with a note, no rows without one.
    for (final (count, empty) in [
      (8, null),
      (1, null),
      (0, "Nothing here."),
      (0, null)
    ]) {
      List<Widget> rows() => [
            for (var i = 0; i < count; i++)
              _Row("row $i",
                  key: ValueKey("r$i"), width: i.isEven ? 220 : null),
          ];
      const after = ValueKey("after");

      Map<String, Rect> rects() => {
            for (var i = 0; i < count; i++)
              "r$i": tester.getRect(find.byKey(ValueKey("r$i"))),
            "title": tester.getRect(find.text("Standalone rooms")),
            if (empty != null) "empty": tester.getRect(find.text(empty)),
            "after": tester.getRect(find.byKey(after)),
          };

      // The old Overview: a ListView holding a Column of cards.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(padding: const EdgeInsets.all(8), children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: card(rows(), empty: empty)),
              const SizedBox(key: after, height: 10),
            ]),
          ]),
        ),
      ));
      final box = rects();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomScrollView(slivers: [
            SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                sliver: NewHomeCardSliver(card(rows(), empty: empty))),
            const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                sliver: SliverToBoxAdapter(
                    child: SizedBox(key: after, height: 10))),
          ]),
        ),
      ));
      expect(find.byType(NewHomeCardSliver), findsOneWidget);
      expect(rects(), box, reason: "$count rows, note: $empty");
    }
  });

  testWidgets("a reordered list shows its rows in the new order",
      (tester) async {
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
