// Vommet: Archive and chat folders of the Telegram-style chat list (Vommet
// issue 291, phase 2): pop-out rules, folder include/exclude precedence,
// unread counts and the stored formats. Made-up names.
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 18, 12);

int _ms(int minutesAgo) =>
    _now.subtract(Duration(minutes: minutesAgo)).millisecondsSinceEpoch;

ChatEntry chat(String id,
        {int? minutesAgo,
        bool direct = false,
        int unread = 0,
        int mentions = 0,
        bool muted = false}) =>
    ChatEntry(
      key: "acct:$id",
      roomId: id,
      name: id,
      kind: direct ? ChatKind.direct : ChatKind.room,
      lastActivity: minutesAgo == null
          ? null
          : _now.subtract(Duration(minutes: minutesAgo)),
      unread: unread,
      mentions: mentions,
      muted: muted,
    );

SpaceEntry space(String id,
        {List<ChatEntry> rooms = const [], bool muted = false}) =>
    SpaceEntry(
        key: "acct:$id", spaceId: id, name: id, rooms: rooms, muted: muted);

List<String> ids(Iterable<TopRow> rows) => rows.map((r) => r.roomId).toList();

/// juniper (DM, unread), pebble (DM, read), inkwell (room, unread, muted),
/// quests (room, read), lantern (space with unread), harbor (muted space).
List<TopRow> sampleRows({Map<String, String?> pins = const {}}) => buildTopRows(
      directMessages: [
        chat("juniper", direct: true, minutesAgo: 2, unread: 2),
        chat("pebble", direct: true, minutesAgo: 60),
      ],
      rooms: [
        chat("inkwell", minutesAgo: 10, unread: 3, muted: true),
        chat("quests", minutesAgo: 120),
      ],
      spaces: [
        space("lantern", rooms: [chat("general", minutesAgo: 5, unread: 4)]),
        space("harbor",
            muted: true,
            rooms: [chat("announcements", minutesAgo: 30, unread: 9)]),
      ],
      pins: pins,
    );

TopRow row(List<TopRow> rows, String id) =>
    rows.firstWhere((r) => r.roomId == id);

void main() {
  group("archive", () {
    test("archived rows leave the main list and keep the list order", () {
      final rows = sampleRows();
      final split = splitArchived(rows, {"pebble": _ms(30), "quests": _ms(30)});
      expect(ids(split.main), ["juniper", "lantern", "inkwell", "harbor"]);
      expect(ids(split.archived), ["pebble", "quests"]);
      expect(split.popped, isEmpty);
    });

    test("an unmuted chat with a newer unread message pops back out", () {
      final rows = sampleRows();
      // juniper's message (2 min ago) came after it was archived (30 min).
      final split = splitArchived(rows, {"juniper": _ms(30)});
      expect(ids(split.main), contains("juniper"));
      expect(split.archived, isEmpty);
      expect(split.popped, {"juniper"});
    });

    test("an unread message from before archiving doesn't pop it out", () {
      final split = splitArchived(sampleRows(), {"juniper": _ms(1)});
      expect(ids(split.archived), ["juniper"]);
      expect(split.popped, isEmpty);
    });

    test("muted chats and muted spaces stay archived", () {
      final split =
          splitArchived(sampleRows(), {"inkwell": _ms(60), "harbor": _ms(60)});
      expect(ids(split.archived), ["inkwell", "harbor"]);
      expect(split.popped, isEmpty);
    });

    test("a space pops out when one of its unmuted rooms gets a message", () {
      final split = splitArchived(sampleRows(), {"lantern": _ms(60)});
      expect(split.popped, {"lantern"});
      expect(ids(split.main), contains("lantern"));
    });

    test("read chats stay archived even with newer activity", () {
      final split = splitArchived(sampleRows(), {"pebble": _ms(600)});
      expect(ids(split.archived), ["pebble"]);
    });

    test("Keep unmuted chats archived stops every pop-out", () {
      final split = splitArchived(
          sampleRows(), {"juniper": _ms(30), "lantern": _ms(60)},
          keepUnmuted: true);
      expect(ids(split.archived), ["juniper", "lantern"]);
      expect(split.popped, isEmpty);
    });

    test("no archive time (garbage) means it never pops out by itself", () {
      final split = splitArchived(sampleRows(), {"juniper": null});
      expect(ids(split.archived), ["juniper"]);
    });

    test("a mention in an unmuted chat pops it out", () {
      final rows =
          buildTopRows(rooms: [chat("quests", minutesAgo: 1, mentions: 1)]);
      expect(splitArchived(rows, {"quests": _ms(10)}).popped, {"quests"});
    });

    test("ids that aren't in the list are ignored", () {
      final split = splitArchived(sampleRows(), {"gone": _ms(5)});
      expect(split.archived, isEmpty);
      expect(split.main.length, 6);
    });
  });

  group("archive summary", () {
    test("counts unread chats, leaving out muted ones", () {
      final rows = sampleRows();
      final split = splitArchived(rows, {
        "juniper": _ms(1), // unread, archived after the message
        "inkwell": _ms(60), // unread but muted
        "harbor": _ms(60), // muted space
        "pebble": _ms(60), // read
      });
      final summary = ArchiveSummary.of(split.archived);
      expect(summary.count, 4);
      expect(summary.unread, 1);
      expect(summary.names.first, ("juniper", true));
      expect(summary.names.map((n) => n.$1),
          ["juniper", "inkwell", "harbor", "pebble"]);
      expect(summary.names.where((n) => n.$2).length, 1);
    });

    test("names are newest first, ignoring pins", () {
      final rows = sampleRows(pins: {"quests": "a"});
      final split =
          splitArchived(rows, {"quests": _ms(500), "pebble": _ms(500)});
      expect(ArchiveSummary.of(split.archived).names.map((n) => n.$1),
          ["pebble", "quests"]);
    });
  });

  group("folders", () {
    const all = {
      FolderChatType.direct,
      FolderChatType.room,
      FolderChatType.space
    };

    test("types pick DMs, rooms not in a space, and spaces", () {
      final rows = sampleRows();
      List<String> of(Set<FolderChatType> types) => ids(
          folderRows(ChatFolder(id: "f", name: "F", types: types), rows, {}));
      expect(of({FolderChatType.direct}), ["juniper", "pebble"]);
      expect(of({FolderChatType.room}), ["inkwell", "quests"]);
      expect(of({FolderChatType.space}), ["lantern", "harbor"]);
      // A room inside a space never shows as its own row.
      expect(of(all), isNot(contains("general")));
    });

    test("exclude muted and exclude read", () {
      final rows = sampleRows();
      final f = ChatFolder(
          id: "f",
          name: "F",
          types: all,
          excludeMuted: true,
          excludeRead: true);
      expect(ids(folderRows(f, rows, {})), ["juniper", "lantern"]);
    });

    test("archived chats are left out unless the folder takes them", () {
      final rows = sampleRows();
      const f = ChatFolder(id: "f", name: "F", types: {FolderChatType.direct});
      expect(ids(folderRows(f, rows, {"pebble"})), ["juniper"]);
      expect(
          ids(folderRows(f.copyWith(excludeArchived: false), rows, {"pebble"})),
          ["juniper", "pebble"]);
    });

    test("a chat picked by hand is in whatever its type and state", () {
      final rows = sampleRows();
      final f = ChatFolder(
          id: "f",
          name: "F",
          types: {FolderChatType.direct},
          include: {"quests", "inkwell"},
          excludeMuted: true,
          excludeRead: true);
      expect(ids(folderRows(f, rows, {"quests"})),
          ["juniper", "inkwell", "quests"]);
    });

    test("an excluded chat beats its type and being picked by hand", () {
      final rows = sampleRows();
      final f = ChatFolder(
          id: "f",
          name: "F",
          types: {FolderChatType.direct},
          include: {"pebble"},
          exclude: {"pebble", "juniper"});
      expect(ids(folderRows(f, rows, {})), isEmpty);
    });

    test("a folder keeps the list's order, pins first", () {
      final rows = sampleRows(pins: {"quests": "a"});
      const f = ChatFolder(id: "f", name: "F", types: all);
      expect(ids(folderRows(f, rows, {})).first, "quests");
    });

    test("withChat / withoutChat", () {
      final rows = sampleRows();
      const f = ChatFolder(id: "f", name: "F", types: {FolderChatType.direct});
      final added = f.withChat("quests");
      expect(folderContains(added, row(rows, "quests")), isTrue);

      // Removing a chat its type brings in excludes it.
      final removed = added.withoutChat("juniper",
          typeWouldInclude: folderTypeMatches(added, row(rows, "juniper")));
      expect(folderContains(removed, row(rows, "juniper")), isFalse);

      // Removing a hand-picked chat just unpicks it.
      final unpicked = added.withoutChat("quests",
          typeWouldInclude: folderTypeMatches(added, row(rows, "quests")));
      expect(unpicked.exclude, isNot(contains("quests")));
      expect(folderContains(unpicked, row(rows, "quests")), isFalse);

      // Adding back an excluded chat lifts the exclusion.
      expect(folderContains(removed.withChat("juniper"), row(rows, "juniper")),
          isTrue);
    });

    test("tab badges count unread chats, not messages, and skip muted", () {
      final rows = sampleRows();
      const f = ChatFolder(id: "f", name: "F", types: all);
      // juniper (2), lantern (4); inkwell and harbor are muted.
      expect(unreadChatCount(folderRows(f, rows, {})), 2);
      expect(unreadChatCount(folderRows(f, rows, {"juniper"})), 1);
    });

    test("the recommended Unread folder holds unread chats", () {
      final unread = recommendedFolders().first;
      expect(ids(folderRows(unread, sampleRows(), {})),
          ["juniper", "lantern", "inkwell", "harbor"]);
      final personal = recommendedFolders().last;
      expect(
          ids(folderRows(personal, sampleRows(), {})), ["juniper", "pebble"]);
    });

    test("a folder needs a type or a chat", () {
      expect(const ChatFolder(id: "f", name: "F").isUsable, isFalse);
      expect(const ChatFolder(id: "f", name: "F", include: {"x"}).isUsable,
          isTrue);
    });
  });

  group("stored formats", () {
    test("folders round-trip through JSON", () {
      final doc = ChatFoldersDoc(
        updated: 42,
        keepUnmutedArchived: true,
        folders: [
          const ChatFolder(
              id: "a",
              name: "Friends",
              emoji: "🎲",
              types: {FolderChatType.direct},
              include: {"!b:x", "!a:x"},
              exclude: {"!c:x"},
              excludeMuted: true,
              excludeRead: true,
              excludeArchived: false),
        ],
      );
      final back = ChatFoldersDoc.fromJson(doc.toJson());
      expect(back.updated, 42);
      expect(back.keepUnmutedArchived, isTrue);
      final f = back.folders.single;
      expect(f.name, "Friends");
      expect(f.emoji, "🎲");
      expect(f.types, {FolderChatType.direct});
      expect(f.include, {"!a:x", "!b:x"});
      expect(f.exclude, {"!c:x"});
      expect([f.excludeMuted, f.excludeRead, f.excludeArchived],
          [true, true, false]);
    });

    test("garbage reads as no folders, broken folders are skipped", () {
      expect(ChatFoldersDoc.fromJson(null).folders, isEmpty);
      expect(ChatFoldersDoc.fromJson("nope").folders, isEmpty);
      expect(ChatFoldersDoc.fromJson({"folders": 3}).folders, isEmpty);
      final doc = ChatFoldersDoc.fromJson({
        "updated": "soon",
        "keep_unmuted_archived": "yes",
        "folders": [
          null,
          {"name": "no id"},
          {"id": "a", "name": 5},
          {
            "id": "b",
            "name": "  ",
            "types": ["direct", "bogus", 7],
            "include": ["!x:y", 3, ""],
            "exclude": "all",
            "exclude_read": "true",
          },
          {"id": "b", "name": "duplicate"},
        ],
      });
      expect(doc.updated, 0);
      expect(doc.keepUnmutedArchived, isFalse);
      final f = doc.folders.single;
      expect(f.id, "b");
      expect(f.name, "Folder");
      expect(f.types, {FolderChatType.direct});
      expect(f.include, {"!x:y"});
      expect(f.exclude, isEmpty);
      expect(f.excludeRead, isFalse);
      // Exclude archived is on by default.
      expect(f.excludeArchived, isTrue);
    });

    test("the newest copy across accounts wins", () {
      const a =
          ChatFoldersDoc(updated: 5, folders: [ChatFolder(id: "a", name: "A")]);
      const b =
          ChatFoldersDoc(updated: 9, folders: [ChatFolder(id: "b", name: "B")]);
      expect(ChatFoldersDoc.newest([a, b]).folders.single.id, "b");
      expect(ChatFoldersDoc.newest([b, a]).folders.single.id, "b");
      expect(ChatFoldersDoc.newest([]).folders, isEmpty);
    });

    test("reorder, replace and remove folders", () {
      const doc = ChatFoldersDoc(folders: [
        ChatFolder(id: "a", name: "A"),
        ChatFolder(id: "b", name: "B"),
        ChatFolder(id: "c", name: "C"),
      ]);
      expect(doc.reordered(0, 3).folders.map((f) => f.id), ["b", "c", "a"]);
      expect(doc.reordered(2, 0).folders.map((f) => f.id), ["c", "a", "b"]);
      expect(doc.reordered(9, 0).folders.map((f) => f.id), ["a", "b", "c"]);
      expect(
          doc
              .withFolder(const ChatFolder(id: "b", name: "Bee"))
              .folders
              .map((f) => f.name),
          ["A", "Bee", "C"]);
      expect(
          doc.withFolder(const ChatFolder(id: "d", name: "D")).folders.length,
          4);
      expect(doc.withoutFolder("a").folders.map((f) => f.id), ["b", "c"]);
    });

    test("archived chats read tolerantly and round-trip", () {
      expect(readArchivedChats(null), isEmpty);
      expect(readArchivedChats({"rooms": []}), isEmpty);
      expect(
          readArchivedChats({
            "rooms": {
              "!a:x": {"ts": 10},
              "!b:x": {"ts": "late"},
              "!c:x": 4,
              "": {"ts": 1},
            }
          }),
          {"!a:x": 10, "!b:x": null, "!c:x": null});
      final map = {"!a:x": 10, "!b:x": null};
      expect(readArchivedChats(archivedChatsContent(map)), map);
    });

    test("folder summary", () {
      expect(
          folderSummary(recommendedFolders().first), "All chats, unread only");
      expect(
          folderSummary(const ChatFolder(
              id: "x",
              name: "x",
              types: {FolderChatType.direct},
              include: {"a", "b"})),
          "Direct messages, 2 chats");
      expect(folderSummary(const ChatFolder(id: "x", name: "x")), "No chats");
    });
  });
}
