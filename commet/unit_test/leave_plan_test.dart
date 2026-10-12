// Vommet: "Leave space" — what it can also leave (only rooms you're in),
// the order (rooms before their spaces, the space itself last), what starts
// ticked (everything but rooms you're also in through another space), and
// half-ticked subspaces staying joined.
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

  test('rooms you are also in through another space are marked', () {
    final index = gaming();
    // Pixel Guild holds lfg and a space that holds pb-brags; Hub is the
    // parent of Gaming, which doesn't make Gaming's rooms shared.
    final kids = {
      "!pixel": ["!lfg", "!art"],
      "!art": ["!pb"],
      "!hub": ["!gaming", "!lounge"],
    };
    List<String> childrenOf(String id) => kids[id] ?? const [];
    index.markShared("!pixel", "Pixel Guild", childrenOf);
    index.markShared("!hub", "Hub", childrenOf);
    index.markShared("!gaming", "Gaming", childrenOf);
    expect(index.alsoIn, {"!lfg": "Pixel Guild", "!pb": "Pixel Guild"});
  });

  test(
      'starts with everything ticked but shared rooms; a half-ticked '
      'subspace stays', () async {
    final index = gaming();
    index.alsoIn["!pb"] = "Pixel Guild";
    final tree = index.tree();
    await JoinedSpaceIndex.loadAll(tree);
    await index.selectDefault(tree);

    expect(tree.selected, {"!lfg", "!squad", "!routes"});
    expect(tree.stateOf(tree.node("!speed")!), isNull);
    expect(index.selectedCounts(tree), (3, 0));
    expect(index.leaveOrder(all: false, tree: tree),
        ["!lfg", "!squad", "!routes", "!gaming"]);

    // Ticking the last room inside makes the subspace go too.
    tree.toggle(tree.node("!pb")!);
    JoinedSpaceIndex.syncSpaces(tree);
    expect(tree.stateOf(tree.node("!speed")!), true);
    expect(index.selectedCounts(tree), (4, 1));
    expect(index.leaveOrder(all: false, tree: tree).sublist(4),
        ["!speed", "!gaming"]);
  });

  testWidgets('the confirmation opens on the tree, everything ticked',
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

    expect(find.text("routes"), findsOneWidget);
    expect(find.text("Leave space, 1 subspace and 4 rooms"), findsOneWidget);

    // Unticking one room inside Speedrunning keeps Speedrunning.
    await tester.tap(find.text("routes"));
    await tester.pumpAndSettle();
    expect(find.text("Leave space and 3 rooms"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("leave-space-confirm")));
    await tester.pumpAndSettle();
    expect(result, ["!lfg", "!squad", "!pb", "!gaming"]);

    // Select none leaves only the space.
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Select none"));
    await tester.pumpAndSettle();
    expect(find.text("Leave Space"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("leave-space-confirm")));
    await tester.pumpAndSettle();
    expect(result, ["!gaming"]);
  });

  testWidgets('shared rooms start unticked and say where else they are',
      (tester) async {
    final index = gaming();
    index.alsoIn["!lfg"] = "Pixel Guild";
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
          body: LeaveSpaceDialog(_FakeSpace(), index, avatarFor: (_) => null)),
    ));
    await tester.pumpAndSettle();
    expect(find.text("also in Pixel Guild"), findsOneWidget);
    expect(find.text("Leave space, 1 subspace and 3 rooms"), findsOneWidget);
  });
}
