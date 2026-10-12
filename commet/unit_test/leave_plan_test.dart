// Vommet: "Leave space" — what it can also leave (only rooms you're in),
// the order (rooms before their spaces, the space itself last), and the
// confirmation's "also leave its rooms" box being off by default.
import 'package:commet/client/client.dart';
import 'package:commet/ui/organisms/space_join_picker/leave_space_dialog.dart';
import 'package:commet/utils/space_hierarchy/leave_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

/// Gaming (you're in): lfg, Squad Voice, Speedrunning (routes, pb-brags);
/// Speedrunning also lists Gaming itself (a loop).
JoinedSpaceIndex gaming() {
  final index = JoinedSpaceIndex("!gaming");
  index.addSpace("!gaming", "Gaming", ["!lfg", "!squad", "!speed"]);
  index.addRoom("!lfg", "lfg");
  index.addRoom("!squad", "Squad Voice", roomType: "org.matrix.msc3417.call");
  index.addSpace("!speed", "Speedrunning", ["!routes", "!pb", "!gaming"]);
  index.addRoom("!routes", "routes");
  index.addRoom("!pb", "pb-brags");
  return index;
}

class _FakeSpace implements Space {
  @override
  String get identifier => "!gaming";

  @override
  String get displayName => "Gaming";

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('counts only what you are in, a loop once', () {
    final index = gaming();
    expect(index.roomCount, 4);
    expect(index.subspaceCount, 1);
    expect(index.total, 5);
  });

  test('leaving everything: rooms before their space, the space last', () {
    final order = gaming().leaveOrder(all: true);
    expect(order.last, "!gaming");
    expect(order.toSet().length, order.length);
    expect(order, containsAll(["!lfg", "!squad", "!routes", "!pb", "!speed"]));
    expect(order.indexOf("!routes"), lessThan(order.indexOf("!speed")));
    expect(order.indexOf("!pb"), lessThan(order.indexOf("!speed")));
  });

  test('leaving only the space by default', () {
    expect(gaming().leaveOrder(all: false), ["!gaming"]);
  });

  test('chosen rooms only, nothing ticked at first, space last', () async {
    final index = gaming();
    final tree = index.tree();
    await JoinedSpaceIndex.loadAll(tree);
    expect(tree.selected, isEmpty);
    expect(tree.loadedCount, 5);
    expect(tree.node("!speed")!.expanded, true);

    tree.toggle(tree.node("!speed")!);
    tree.toggle(tree.node("!squad")!);
    expect(tree.stateOf(tree.node("!speed")!), true);

    final order = index.leaveOrder(all: false, tree: tree);
    expect(order, ["!squad", "!routes", "!pb", "!speed", "!gaming"]);
  });

  testWidgets('the confirmation leaves only the space unless ticked',
      (tester) async {
    List<String>? result;
    final index = gaming();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<List<String>>(
                context: context,
                builder: (_) => Dialog(
                    child: LeaveSpaceDialog(_FakeSpace(), index,
                        avatarFor: (_) => null)),
              );
            },
            child: const Text("open"),
          ),
        ),
      ),
    ));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();

    final box = tester
        .widget<Checkbox>(find.byKey(const ValueKey("leave-space-also-rooms")));
    expect(box.value, false);
    expect(find.text("Also leave its 4 rooms and 1 subspace you're in"),
        findsOneWidget);

    await tester.tap(find.text("Leave Space"));
    await tester.pumpAndSettle();
    expect(result, ["!gaming"]);

    // Choosing: nothing ticked, then one room makes the box a dash.
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Choose…"));
    await tester.pumpAndSettle();
    expect(find.text("routes"), findsOneWidget);
    await tester.tap(find.text("routes"));
    await tester.pumpAndSettle();
    expect(find.text("Also leave 1 of its 5 rooms and spaces"), findsOneWidget);
    expect(
        tester
            .widget<Checkbox>(
                find.byKey(const ValueKey("leave-space-also-rooms")))
            .value,
        isNull);
    expect(find.text("you're in"), findsNothing);

    await tester.tap(find.text("Leave Space"));
    await tester.pumpAndSettle();
    expect(result, ["!routes", "!gaming"]);
  });
}
