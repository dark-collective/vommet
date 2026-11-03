// Vommet issue 521: in the Telegram-style chat list a "Mentions & keywords"
// room with messages that don't mention you has no count, so it gets the
// classic list's unread dot instead, and so do the spaces and subspaces
// around it. Made-up names.
import 'package:commet/ui/atoms/dot_indicator.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ChatEntry chat(String id,
        {int unread = 0,
        int mentions = 0,
        bool marked = false,
        bool muted = false}) =>
    ChatEntry(
      key: "acct:$id",
      roomId: id,
      name: id,
      unread: unread,
      mentions: mentions,
      unreadMark: marked,
      muted: muted,
    );

SpaceEntry space(String id,
        {List<ChatEntry> rooms = const [],
        List<SpaceEntry> subspaces = const []}) =>
    SpaceEntry(
        key: "acct:$id",
        spaceId: id,
        name: id,
        rooms: rooms,
        subspaces: subspaces);

Future<void> pumpBadges(WidgetTester tester, ChatBadges badges) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: badges))));

void main() {
  test("a space and its parent carry a subspace room's unread mark", () {
    final inner = space("inner", rooms: [chat("lore", marked: true)]);
    final outer = space("outer", rooms: [chat("plaza")], subspaces: [inner]);
    expect(SpaceDigest.of(inner).unreadMark, isTrue);
    expect(SpaceDigest.of(outer).unreadMark, isTrue);
    expect(SpaceDigest.of(outer).unread, 0);
    expect(SpaceDigest.of(space("calm", rooms: [chat("plaza")])).unreadMark,
        isFalse);
  });

  test("a marked chat or space counts as unread for folders", () {
    final marked = ChatTopRow(chat("lore", marked: true, muted: true));
    final read = ChatTopRow(chat("plaza"));
    final markedSpace =
        SpaceTopRow(space("guild", rooms: [chat("lore", marked: true)]));
    expect(marked.hasUnread, isTrue);
    expect(markedSpace.hasUnread, isTrue);
    expect(read.hasUnread, isFalse);

    const f = ChatFolder(
        id: "f",
        name: "F",
        types: {FolderChatType.room, FolderChatType.space},
        excludeRead: true);
    expect(
        folderRows(f, [marked, read, markedSpace], {})
            .map((r) => r.roomId)
            .toList(),
        ["lore", "guild"]);
  });

  testWidgets("the dot shows only when there's no count", (tester) async {
    await pumpBadges(tester, const ChatBadges(marked: true, muted: true));
    expect(find.byType(DotIndicator), findsOneWidget);

    await pumpBadges(tester, const ChatBadges(unread: 2, marked: true));
    expect(find.byType(DotIndicator), findsNothing);
    expect(find.text("2"), findsOneWidget);

    await pumpBadges(tester, const ChatBadges(mentions: 1, marked: true));
    expect(find.byType(DotIndicator), findsNothing);
    expect(find.text("@"), findsOneWidget);

    await pumpBadges(tester, const ChatBadges());
    expect(find.byType(DotIndicator), findsNothing);
  });
}
