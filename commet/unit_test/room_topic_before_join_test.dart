// Vommet issue 672: a room's topic is shown before joining it, in Browse
// rooms (the space join picker's tree) and in the classic chat list's Join
// confirmation.

import 'package:commet/client/room_preview.dart';
import 'package:commet/ui/molecules/room_join_preview.dart';
import 'package:commet/ui/organisms/space_join_picker/space_tree_view.dart';
import 'package:commet/utils/space_hierarchy/space_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<SpaceTree> loadedTree() async {
  final rooms = {
    "!root": const HierarchyRoomInfo(
        roomId: "!root",
        name: "Lantern Collective",
        roomType: "m.space",
        children: [
          HierarchyChildLink("!art", via: ["example.org"]),
          HierarchyChildLink("!quiet", via: ["example.org"]),
        ]),
    "!art": const HierarchyRoomInfo(
        roomId: "!art",
        name: "art-share",
        members: 64,
        topic: "Post your drawings\nand works in progress."),
    "!quiet": const HierarchyRoomInfo(
        roomId: "!quiet", name: "quiet-room", members: 3, topic: "   "),
  };
  final tree = SpaceTree(
      spaceId: "!root",
      isJoined: (_) => false,
      fetch: (id, {String? from, required int limit}) async => HierarchyPage(
          [rooms[id]!, for (final c in rooms[id]!.children) rooms[c.roomId]!]));
  await tree.loadRoot();
  return tree;
}

Widget treeView(SpaceTree tree, {required bool showTopics}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 500,
          height: 400,
          child: SpaceTreeView(
            tree: tree,
            showTopics: showTopics,
            avatarFor: (_) => null,
            colorFor: (_) => Colors.grey,
            onChanged: () {},
          ),
        ),
      ),
    );

void main() {
  test('a node folds its topic onto one line; blank means none', () async {
    final tree = await loadedTree();
    final art = tree.root.children.firstWhere((n) => n.roomId == "!art");
    final quiet = tree.root.children.firstWhere((n) => n.roomId == "!quiet");
    expect(art.topic, "Post your drawings and works in progress.");
    expect(quiet.topic, isNull);
  });

  testWidgets('Browse rooms shows a topic line under rooms that have one',
      (tester) async {
    final tree = await loadedTree();
    await tester.pumpWidget(treeView(tree, showTopics: true));
    expect(find.byKey(const ValueKey("space-tree-topic-!art")), findsOneWidget);
    expect(
        find.text("Post your drawings and works in progress."), findsOneWidget);
    expect(find.byKey(const ValueKey("space-tree-topic-!quiet")), findsNothing);

    // A row with a topic is taller than one without.
    final artRow = tester.getSize(find
        .ancestor(
            of: find.byKey(const ValueKey("space-tree-row-!art")),
            matching: find.byType(SizedBox))
        .first);
    final quietRow = tester.getSize(find
        .ancestor(
            of: find.byKey(const ValueKey("space-tree-row-!quiet")),
            matching: find.byType(SizedBox))
        .first);
    expect(artRow.height, SpaceTreeView.topicRowHeight);
    expect(quietRow.height, SpaceTreeView.rowHeight);
  });

  testWidgets('other uses of the tree (leave, invite) keep one-line rows',
      (tester) async {
    final tree = await loadedTree();
    await tester.pumpWidget(treeView(tree, showTopics: false));
    expect(find.byKey(const ValueKey("space-tree-topic-!art")), findsNothing);
  });

  testWidgets('the Join confirmation previews the room with its topic',
      (tester) async {
    final preview = GenericRoomPreview("!art",
        displayName: "art-share",
        type: null,
        numMembers: 1234,
        topic: "Post your drawings and works in progress.");
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RoomJoinPreview(preview, spaceName: "Lantern Collective"))));
    expect(find.text("art-share"), findsOneWidget);
    expect(find.text("1,234 members · Lantern Collective"), findsOneWidget);
    expect(
        find.text("Post your drawings and works in progress."), findsOneWidget);
  });

  testWidgets('a room without a topic shows just its name and members',
      (tester) async {
    final preview = GenericRoomPreview("!quiet",
        displayName: "quiet-room", type: null, numMembers: 1);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RoomJoinPreview(preview))));
    expect(find.text("1 member"), findsOneWidget);
    expect(find.byKey(const ValueKey("room-join-preview-topic")), findsNothing);
  });
}
