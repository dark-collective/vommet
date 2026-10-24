import 'package:commet/ui/organisms/new_home/new_home.dart';
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
}
