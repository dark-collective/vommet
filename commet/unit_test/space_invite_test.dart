// Vommet: inviting to a space also offers its rooms. Only rooms you can
// invite to are ticked (and tickable), the space goes first and each
// subspace before its rooms, the button counts what goes out, and a deep or
// long tree scrolls both ways inside its box.
import 'package:commet/ui/organisms/space_join_picker/space_tree_view.dart';
import 'package:commet/utils/space_hierarchy/invite_plan.dart';
import 'package:commet/utils/space_hierarchy/leave_plan.dart';
import 'package:commet/utils/space_hierarchy/space_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

/// Driftwood: general, mods (can't invite), Art (art-share, already in
/// critique).
JoinedSpaceIndex driftwood() {
  final index = JoinedSpaceIndex("!drift");
  index.addSpace("!drift", "Driftwood", ["!general", "!mods", "!art"]);
  index.addRoom("!general", "general");
  index.addRoom("!mods", "mods");
  index.addSpace("!art", "Art", ["!share", "!critique"]);
  index.addRoom("!share", "art-share");
  index.addRoom("!critique", "critique");
  return index;
}

const statuses = {
  "!general": InviteHistory.included,
  "!mods": InviteHistory.cannotInvite,
  "!art": InviteHistory.space,
  "!share": InviteHistory.newMessagesOnly,
  "!critique": InviteHistory.alreadyMember,
};

SpaceTree treeOf(JoinedSpaceIndex index, Map<String, InviteHistory> s) =>
    SpaceTree(
      spaceId: index.spaceId,
      rootInfo: index.infos[index.spaceId],
      fetch: index.fetcher,
      isJoined: (id) => !(s[id]?.invitable ?? false),
      selectionCap: SpaceTree.totalCap,
      // Local data: every level, however deep the subspaces go.
      depthLimit: 64,
    );

void main() {
  test('everything you can invite to is ticked, nothing else', () async {
    final tree = treeOf(driftwood(), statuses);
    await JoinedSpaceIndex.loadAll(tree);
    await tree.selectAll();
    expect(tree.selected, {"!general", "!art", "!share"});
  });

  test('the space first, each subspace before its rooms', () async {
    final tree = treeOf(driftwood(), statuses);
    await JoinedSpaceIndex.loadAll(tree);
    await tree.selectAll();
    final order = InvitePlan.order(tree);
    expect(order.first, "!drift");
    expect(order, containsAll(["!general", "!art", "!share"]));
    expect(order, isNot(contains("!mods")));
    expect(order, isNot(contains("!critique")));
    expect(order.indexOf("!art"), lessThan(order.indexOf("!share")));
    expect(order.toSet().length, order.length);
  });

  test('unticking everything invites to the space only', () async {
    final tree = treeOf(driftwood(), statuses);
    await JoinedSpaceIndex.loadAll(tree);
    await tree.selectAll();
    tree.selectNone();
    expect(InvitePlan.order(tree), ["!drift"]);
  });

  test('button label counts rooms and subspaces', () {
    expect(InvitePlan.buttonLabel(rooms: 0, subspaces: 0), "Invite");
    expect(InvitePlan.buttonLabel(rooms: 1, subspaces: 0),
        "Invite to space + 1 room");
    expect(InvitePlan.buttonLabel(rooms: 4, subspaces: 2),
        "Invite to space + 4 rooms and 2 subspaces");
    expect(InvitePlan.buttonLabel(rooms: 0, subspaces: 1),
        "Invite to space + 1 subspace");
  });

  testWidgets('a long, deep tree scrolls both ways inside its box',
      (tester) async {
    // 12 levels of subspaces, each with 6 rooms: far taller and wider than
    // the 360 x 240 box.
    final index = JoinedSpaceIndex("!s0");
    final all = <String, InviteHistory>{};
    for (var d = 0; d < 12; d++) {
      final rooms = [for (var r = 0; r < 6; r++) "!r$d-$r"];
      index.addSpace("!s$d", "Subspace level $d with a long name",
          [...rooms, if (d < 11) "!s${d + 1}"]);
      for (final r in rooms) {
        index.addRoom(r, "room $r");
        all[r] = InviteHistory.included;
      }
      if (d > 0) all["!s$d"] = InviteHistory.space;
    }
    final tree = treeOf(index, all);
    await tester.runAsync(() async {
      await JoinedSpaceIndex.loadAll(tree);
      await tree.selectAll();
    });
    // Every level is loaded and ticked, however deep.
    expect(tree.selected, contains("!r11-5"));
    expect(tree.selected, contains("!s11"));

    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 240,
            child: SpaceTreeView(
              tree: tree,
              joinMode: false,
              statusFor: (_) => const Text("History included"),
              statusWidth: 170,
              avatarFor: (_) => null,
              colorFor: (_) => Colors.blue,
              onChanged: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final scrollables =
        tester.stateList<ScrollableState>(find.byType(Scrollable)).toList();
    final horizontal = scrollables
        .firstWhere((s) => s.position.axis == Axis.horizontal)
        .position;
    final vertical = scrollables
        .firstWhere((s) => s.position.axis == Axis.vertical)
        .position;
    expect(horizontal.maxScrollExtent, greaterThan(0));
    expect(vertical.maxScrollExtent, greaterThan(0));

    // The deepest room can be reached.
    vertical.jumpTo(vertical.maxScrollExtent);
    horizontal.jumpTo(horizontal.maxScrollExtent);
    await tester.pump();
    expect(find.text("room !r11-5"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
