import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/ui/molecules/rail_drop_target.dart';
import 'package:commet/ui/molecules/space_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet: dropping on a sidebar icon moves next to it; only holding over its
// middle makes a folder.
void main() {
  late List<String> calls;

  Future<void> pumpRail(WidgetTester tester) async {
    calls = [];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Draggable<SidebarEntryDrag>(
            data: SidebarEntryDrag(SidebarEntry("dragged", ""), 0),
            feedback: const SizedBox(width: 70, height: 70),
            child: const SizedBox(
                key: Key("source"),
                width: 70,
                height: 70,
                child: ColoredBox(color: Colors.red)),
          ),
          const SizedBox(height: 100),
          RailDropTarget(
            size: 70,
            accepts: (_) => true,
            onReorder: (_, below) => calls.add(below ? "below" : "above"),
            onFolder: (_) => calls.add("folder"),
            child: const SizedBox(key: Key("target"), width: 70, height: 70),
          ),
        ]),
      ),
    ));
  }

  Future<void> dropOnTarget(
      WidgetTester tester, Offset offset, Duration hold) async {
    var gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const Key("source"))));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture
        .moveTo(tester.getCenter(find.byKey(const Key("target"))) + offset);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 1));
    await tester.pump(hold);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets("a quick drop on the middle moves, no folder", (tester) async {
    await pumpRail(tester);
    await dropOnTarget(
        tester, const Offset(0, -5), const Duration(milliseconds: 100));
    expect(calls, ["above"]);
  });

  testWidgets("holding over the middle makes a folder", (tester) async {
    await pumpRail(tester);
    await dropOnTarget(tester, Offset.zero, const Duration(milliseconds: 700));
    expect(calls, ["folder"]);
    expect(find.text("Release to make a folder"), findsNothing);
  });

  testWidgets("holding off-centre still makes a folder", (tester) async {
    await pumpRail(tester);
    await dropOnTarget(
        tester, const Offset(0, 20), const Duration(milliseconds: 700));
    expect(calls, ["folder"]);
  });

  testWidgets("holding near an edge only moves", (tester) async {
    await pumpRail(tester);
    await dropOnTarget(tester, const Offset(0, 30), const Duration(seconds: 1));
    expect(calls, ["below"]);
  });
}
