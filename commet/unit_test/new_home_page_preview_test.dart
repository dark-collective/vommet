import 'package:commet/ui/organisms/new_home/new_home_page_preview.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 782: a whole page beside other Overview cards shows its first
// rows and "See all N ›", which opens the whole page; the page closes when
// a room opens from it.
void main() {
  testWidgets("See all opens the whole page; opening a room closes it",
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => NewHomeSeeAll(
            total: 12,
            onTap: () => NewHomePagePreview.open(context,
                title: "Direct messages",
                builder: (_) => const Text("every DM")),
          ),
        ),
      ),
    ));

    expect(find.text("See all 12 ›"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("NewHomeSeeAll")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("NewHomeWholePage")), findsOneWidget);
    expect(find.text("every DM"), findsOneWidget);
    expect(find.text("Direct messages"), findsOneWidget);

    EventBus.openRoom.add(RoomOpenArgs("!room:example.org", "client"));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("NewHomeWholePage")), findsNothing);
    expect(find.text("See all 12 ›"), findsOneWidget);
  });
}
