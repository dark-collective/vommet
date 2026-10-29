import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_editor.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_main.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 674: a Home tab's main area holds views, shown as a bar to
// tap (or swipe); the shown view is remembered per tab while the app runs.

void main() {
  testWidgets("tapping a view name shows that view", (tester) async {
    final people = HomeTabs.defaults.tab(HomeTabs.people)!;
    newHomeViews.value = {};
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: newHomeViews,
          builder: (_, views, __) => NewHomeViewBar(
              tab: people,
              shown: views[people.id] ?? people.views.first.id,
              phone: false),
        ),
      ),
    ));
    expect(find.text("Contacts"), findsOneWidget);
    expect(find.text("Invites"), findsOneWidget);
    expect(find.text("Blocked"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("NewHomeView-blocked")));
    await tester.pump();
    expect(newHomeViews.value[HomeTabs.people], "blocked");
    expect(
        tester.getSemantics(find.byKey(const ValueKey("NewHomeView-blocked"))),
        containsSemantics(isSelected: true));
    newHomeViews.value = {};
  });

  test("only the Invites view gets the invites count", () {
    final people = HomeTabs.defaults.tab(HomeTabs.people)!;
    expect([for (final v in people.views) NewHomeViewBar.showsInvites(v)],
        [false, true, false]);
  });

  test("Add a view: a full-size card's view, or an empty one for cards", () {
    var people = HomeTabs.defaults.tab(HomeTabs.people)!;
    expect(
        tabHasViewOf(
            people, const HomeCard(HomeLayout.peoplePage, part: "invites")),
        isTrue);
    expect(tabHasViewOf(people, const HomeCard(HomeLayout.dmsPage)), isFalse);
    final (withDms, dmsId) = addViewTo(people, "dms");
    expect(dmsId, "dms");
    expect(withDms.view("dms")!.name, "Direct messages");
    expect([for (final c in withDms.view("dms")!.main.cards) c.type],
        ["dms_page"]);
    expect(tabHasViewOf(withDms, const HomeCard(HomeLayout.dmsPage)), isTrue);
    // The reporter's People: Direct messages first.
    people = withDms.moveView("dms", 0);
    expect([for (final v in people.views) v.id],
        ["dms", "contacts", "invites", "blocked"]);
    final (withCards, cardsId) = addViewTo(people, "cards");
    expect(withCards.view(cardsId)!.name, "Cards");
    expect(withCards.view(cardsId)!.main.cards, isEmpty);
    final (again, secondId) = addViewTo(withCards, "cards");
    expect(secondId, "cards-2");
    expect(again.views.length, 6);
  });
}
