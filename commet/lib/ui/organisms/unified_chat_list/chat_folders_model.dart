// Vommet: Archive and chat folders for the Telegram-style chat list (Vommet
// issue 291, phase 2).
//
// The pure part: what's stored in account data, which rows are archived
// (and which pop back out), which rows a folder holds, and the unread counts
// on the tabs and the Archived chats row. Like unified_chat_model.dart it
// knows nothing about the client, so unit tests can feed it made-up rows.
//
// Account data (both tolerate missing or garbage content):
// - im.nether.chat.archived_chats, per account, written to the account that
//   owns the chat: {"rooms": {"<room or space id>": {"ts": <ms archived>}}}.
//   The rows of every account in the list are merged, like the pins.
// - im.nether.chat.chat_folders, the same on every account (each save writes
//   all of them; the copy with the newest "updated" wins):
//   {"updated": <ms>, "keep_unmuted_archived": false, "folders": [{"id",
//   "name", "emoji", "types": ["direct", "room", "space"], "include": [ids],
//   "exclude": [ids], "exclude_muted", "exclude_read", "exclude_archived"}]}
import 'dart:math';

import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';

const archivedChatsAccountDataKey = "im.nether.chat.archived_chats";
const chatFoldersAccountDataKey = "im.nether.chat.chat_folders";

/// The chat types a folder can include by type.
enum FolderChatType {
  /// Direct messages.
  direct("direct"),

  /// Rooms that aren't in a space.
  room("room"),

  /// Spaces (one row each).
  space("space");

  const FolderChatType(this.key);
  final String key;

  static FolderChatType? fromKey(Object? key) =>
      values.where((t) => t.key == key).firstOrNull;
}

Set<String> _idSet(Object? value) => {
      if (value is List)
        for (final id in value)
          if (id is String && id.isNotEmpty) id,
    };

bool _flag(Object? value, bool fallback) => value is bool ? value : fallback;

/// A user-made folder: a name, chat types it takes in, chats picked by hand,
/// and filters. Which rows it holds is decided by [folderContains].
class ChatFolder {
  const ChatFolder({
    required this.id,
    required this.name,
    this.emoji,
    this.types = const {},
    this.include = const {},
    this.exclude = const {},
    this.excludeMuted = false,
    this.excludeRead = false,
    this.excludeArchived = true,
  });

  final String id;
  final String name;

  /// Shown instead of the folder icon on the tab, if set.
  final String? emoji;
  final Set<FolderChatType> types;

  /// Room or space ids that are always in the folder (unless excluded).
  final Set<String> include;

  /// Room or space ids that are never in the folder.
  final Set<String> exclude;
  final bool excludeMuted;
  final bool excludeRead;
  final bool excludeArchived;

  /// A folder must take in something: a type or a chat.
  bool get isUsable => types.isNotEmpty || include.isNotEmpty;

  ChatFolder copyWith({
    String? name,
    String? Function()? emoji,
    Set<FolderChatType>? types,
    Set<String>? include,
    Set<String>? exclude,
    bool? excludeMuted,
    bool? excludeRead,
    bool? excludeArchived,
  }) =>
      ChatFolder(
        id: id,
        name: name ?? this.name,
        emoji: emoji == null ? this.emoji : emoji(),
        types: types ?? this.types,
        include: include ?? this.include,
        exclude: exclude ?? this.exclude,
        excludeMuted: excludeMuted ?? this.excludeMuted,
        excludeRead: excludeRead ?? this.excludeRead,
        excludeArchived: excludeArchived ?? this.excludeArchived,
      );

  /// Puts [roomId] in the folder: picked by hand, and no longer excluded.
  ChatFolder withChat(String roomId) => copyWith(
      include: {...include, roomId}, exclude: {...exclude}..remove(roomId));

  /// Takes [roomId] out: no longer picked, and excluded when its type (or
  /// nothing else) would still bring it in.
  ChatFolder withoutChat(String roomId, {required bool typeWouldInclude}) =>
      copyWith(
          include: {...include}..remove(roomId),
          exclude: typeWouldInclude ? {...exclude, roomId} : exclude);

  Map<String, Object?> toJson() => {
        "id": id,
        "name": name,
        if (emoji != null) "emoji": emoji,
        "types": [
          for (final t in FolderChatType.values)
            if (types.contains(t)) t.key
        ],
        "include": include.toList()..sort(),
        "exclude": exclude.toList()..sort(),
        "exclude_muted": excludeMuted,
        "exclude_read": excludeRead,
        "exclude_archived": excludeArchived,
      };

  /// Null for anything that isn't a folder with an id and a name.
  static ChatFolder? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json["id"];
    final name = json["name"];
    if (id is! String || id.isEmpty || name is! String) return null;
    final emoji = json["emoji"];
    return ChatFolder(
      id: id,
      name: name.trim().isEmpty ? "Folder" : name,
      emoji: emoji is String && emoji.trim().isNotEmpty ? emoji : null,
      types: {
        if (json["types"] case List types)
          for (final t in types)
            if (FolderChatType.fromKey(t) case final type?) type,
      },
      include: _idSet(json["include"]),
      exclude: _idSet(json["exclude"]),
      excludeMuted: _flag(json["exclude_muted"], false),
      excludeRead: _flag(json["exclude_read"], false),
      excludeArchived: _flag(json["exclude_archived"], true),
    );
  }

  static String newId([Random? random]) {
    final r = random ?? Random();
    return "f${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}"
        "${r.nextInt(1 << 30).toRadixString(36)}";
  }
}

/// The folders, in tab order, and the archive's one option.
class ChatFoldersDoc {
  const ChatFoldersDoc(
      {this.folders = const [],
      this.keepUnmutedArchived = false,
      this.updated = 0});

  static const empty = ChatFoldersDoc();

  final List<ChatFolder> folders;

  /// Telegram's "Keep unmuted chats archived": off means an archived chat
  /// that isn't muted comes back to the list when a message arrives.
  final bool keepUnmutedArchived;

  /// When this was saved (ms since epoch); the newest copy wins.
  final int updated;

  ChatFolder? folder(String? id) =>
      id == null ? null : folders.where((f) => f.id == id).firstOrNull;

  ChatFoldersDoc copyWith(
          {List<ChatFolder>? folders,
          bool? keepUnmutedArchived,
          int? updated}) =>
      ChatFoldersDoc(
          folders: folders ?? this.folders,
          keepUnmutedArchived: keepUnmutedArchived ?? this.keepUnmutedArchived,
          updated: updated ?? this.updated);

  /// Replaces the folder with [folder]'s id, or adds it at the end.
  ChatFoldersDoc withFolder(ChatFolder folder) {
    final at = folders.indexWhere((f) => f.id == folder.id);
    return copyWith(
        folders: at < 0
            ? [...folders, folder]
            : [...folders.take(at), folder, ...folders.skip(at + 1)]);
  }

  ChatFoldersDoc withoutFolder(String id) =>
      copyWith(folders: folders.where((f) => f.id != id).toList());

  /// Moves the folder at [from] to [to] (ReorderableListView's indices: [to]
  /// counts the moved folder still in place).
  ChatFoldersDoc reordered(int from, int to) {
    if (from < 0 || from >= folders.length) return this;
    final list = List.of(folders);
    final moved = list.removeAt(from);
    final at = (to > from ? to - 1 : to).clamp(0, list.length);
    list.insert(at, moved);
    return copyWith(folders: list);
  }

  Map<String, Object?> toJson() => {
        "updated": updated,
        "keep_unmuted_archived": keepUnmutedArchived,
        "folders": [for (final f in folders) f.toJson()],
      };

  /// Never throws: garbage reads as no folders; broken folders are skipped,
  /// and a folder id seen twice keeps its first copy.
  static ChatFoldersDoc fromJson(Object? json) {
    if (json is! Map) return empty;
    final seen = <String>{};
    final folders = <ChatFolder>[];
    if (json["folders"] case List list) {
      for (final item in list) {
        final folder = ChatFolder.fromJson(item);
        if (folder != null && seen.add(folder.id)) folders.add(folder);
      }
    }
    final updated = json["updated"];
    return ChatFoldersDoc(
      folders: folders,
      keepUnmutedArchived: _flag(json["keep_unmuted_archived"], false),
      updated: updated is int ? updated : 0,
    );
  }

  /// The copy saved last, of several accounts' copies.
  static ChatFoldersDoc newest(Iterable<ChatFoldersDoc> docs) {
    ChatFoldersDoc best = empty;
    var first = true;
    for (final doc in docs) {
      if (first || doc.updated > best.updated) best = doc;
      first = false;
    }
    return best;
  }
}

/// Telegram's recommended folders, added with one tap.
List<ChatFolder> recommendedFolders() => const [
      ChatFolder(
        id: "rec-unread",
        name: "Unread",
        types: {
          FolderChatType.direct,
          FolderChatType.room,
          FolderChatType.space
        },
        excludeRead: true,
      ),
      ChatFolder(
        id: "rec-personal",
        name: "Personal",
        types: {FolderChatType.direct},
      ),
    ];

/// What the recommended folder [id] is for, for its row in settings.
String recommendedFolderDescription(String id) => switch (id) {
      "rec-unread" => "New messages from all chats",
      "rec-personal" => "Only messages from direct messages",
      _ => "",
    };

/// Reads the archived chats: room or space id -> when it was archived (ms),
/// null when the time is missing (such a chat never pops back out by
/// itself).
Map<String, int?> readArchivedChats(Object? content) {
  if (content is! Map) return const {};
  final rooms = content["rooms"];
  if (rooms is! Map) return const {};
  return {
    for (final entry in rooms.entries)
      if (entry.key is String && (entry.key as String).isNotEmpty)
        entry.key as String: switch (entry.value) {
          {"ts": int ts} => ts,
          _ => null,
        },
  };
}

/// The account data content for [archived].
Map<String, Object?> archivedChatsContent(Map<String, int?> archived) => {
      "rooms": {
        for (final entry in archived.entries)
          entry.key: {if (entry.value != null) "ts": entry.value},
      },
    };

/// What the folder and archive rules need to know about a list row.
extension TopRowState on TopRow {
  FolderChatType get folderType => switch (this) {
        ChatTopRow(:final chat) =>
          chat.isDirect ? FolderChatType.direct : FolderChatType.room,
        SpaceTopRow() => FolderChatType.space,
      };

  /// Unread messages (for a space, in its rooms that aren't muted).
  int get unreadCount => switch (this) {
        ChatTopRow(:final chat) => chat.unread,
        SpaceTopRow(:final digest) => digest.unread,
      };

  int get mentionCount => switch (this) {
        ChatTopRow(:final chat) => chat.mentions,
        SpaceTopRow(:final digest) => digest.mentions,
      };

  bool get isMuted => switch (this) {
        ChatTopRow(:final chat) => chat.muted,
        SpaceTopRow(:final space) => space.muted,
      };

  bool get hasUnread => unreadCount > 0 || mentionCount > 0;

  /// Counts towards a tab's or the Archived row's badge: unread, not muted.
  bool get countsAsUnread => hasUnread && !isMuted;
}

/// The list split into the main list and the archive.
class ArchiveSplit {
  const ArchiveSplit(
      {this.main = const [], this.archived = const [], this.popped = const {}});

  /// Rows not archived, in the list's order (pins first, then newest).
  final List<TopRow> main;

  /// Archived rows, same order.
  final List<TopRow> archived;

  /// Ids of archived rows that came back out because a message arrived;
  /// they're in [main] and should be unarchived in account data.
  final Set<String> popped;

  Set<String> get archivedIds => {for (final row in archived) row.roomId};
}

/// Whether an archived [row] comes back to the list: it isn't muted, a
/// message arrived after it was archived ([archivedAt], ms) and is still
/// unread. With [keepUnmuted] (Telegram's "Keep unmuted chats archived")
/// nothing comes back by itself.
bool popsOutOfArchive(TopRow row, int? archivedAt, {bool keepUnmuted = false}) {
  if (keepUnmuted || archivedAt == null || row.isMuted || !row.hasUnread) {
    return false;
  }
  final last = row.lastActivity;
  return last != null && last.millisecondsSinceEpoch > archivedAt;
}

ArchiveSplit splitArchived(List<TopRow> rows, Map<String, int?> archived,
    {bool keepUnmuted = false}) {
  if (archived.isEmpty) return ArchiveSplit(main: rows);
  final main = <TopRow>[];
  final archivedRows = <TopRow>[];
  final popped = <String>{};
  for (final row in rows) {
    if (!archived.containsKey(row.roomId)) {
      main.add(row);
    } else if (popsOutOfArchive(row, archived[row.roomId],
        keepUnmuted: keepUnmuted)) {
      main.add(row);
      popped.add(row.roomId);
    } else {
      archivedRows.add(row);
    }
  }
  return ArchiveSplit(main: main, archived: archivedRows, popped: popped);
}

/// Whether [folder] holds [row] ([archived]: the row is in the archive).
/// Precedence: an excluded chat is never in; a chat picked by hand always
/// is; otherwise its type must be included and the exclude-muted, -read and
/// -archived options apply.
bool folderContains(ChatFolder folder, TopRow row, {bool archived = false}) {
  if (folder.exclude.contains(row.roomId)) return false;
  if (folder.include.contains(row.roomId)) return true;
  return folderTypeMatches(folder, row, archived: archived);
}

/// Whether [row] is in [folder] by its type and the options alone, ignoring
/// the chats picked or excluded by hand.
bool folderTypeMatches(ChatFolder folder, TopRow row, {bool archived = false}) {
  if (!folder.types.contains(row.folderType)) return false;
  if (folder.excludeArchived && archived) return false;
  if (folder.excludeMuted && row.isMuted) return false;
  if (folder.excludeRead && !row.hasUnread) return false;
  return true;
}

/// [folder]'s rows out of every row ([rows], archived ones too, in list
/// order); [archivedIds] says which are in the archive.
List<TopRow> folderRows(
        ChatFolder folder, List<TopRow> rows, Set<String> archivedIds) =>
    [
      for (final row in rows)
        if (folderContains(folder, row,
            archived: archivedIds.contains(row.roomId)))
          row
    ];

/// The badge on a tab or on the Archived chats row: how many chats are
/// unread, leaving out muted ones (Telegram counts chats, not messages).
int unreadChatCount(Iterable<TopRow> rows) =>
    rows.where((row) => row.countsAsUnread).length;

/// What the Archived chats row shows.
class ArchiveSummary {
  const ArchiveSummary(
      {this.count = 0, this.unread = 0, this.names = const []});

  /// How many chats are archived.
  final int count;

  /// Unread archived chats that aren't muted.
  final int unread;

  /// Names, newest first, and whether each counts as unread (drawn bold).
  final List<(String, bool)> names;

  static ArchiveSummary of(List<TopRow> archived, {int maxNames = 8}) {
    final sorted = List.of(archived)
      ..sort((a, b) => compareRowsByActivity(a, b));
    return ArchiveSummary(
      count: archived.length,
      unread: unreadChatCount(archived),
      names: [
        for (final row in sorted.take(maxNames)) (row.name, row.countsAsUnread)
      ],
    );
  }
}

/// Newest first, ignoring pins.
int compareRowsByActivity(TopRow a, TopRow b) {
  final ta = a.lastActivity, tb = b.lastActivity;
  if (ta != null && tb != null) {
    final c = tb.compareTo(ta);
    if (c != 0) return c;
  } else if (ta != null) {
    return -1;
  } else if (tb != null) {
    return 1;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// A short line about what a folder holds, for its row in settings:
/// "Direct messages, 2 chats".
String folderSummary(ChatFolder folder) {
  final parts = <String>[
    if (folder.types.length == FolderChatType.values.length)
      "All chats"
    else
      for (final t in FolderChatType.values)
        if (folder.types.contains(t))
          switch (t) {
            FolderChatType.direct => "Direct messages",
            FolderChatType.room => "Rooms",
            FolderChatType.space => "Spaces",
          },
    if (folder.include.isNotEmpty)
      "${folder.include.length} ${folder.include.length == 1 ? "chat" : "chats"}",
  ];
  if (parts.isEmpty) return "No chats";
  final text = parts.join(", ");
  return folder.excludeRead ? "$text, unread only" : text;
}
