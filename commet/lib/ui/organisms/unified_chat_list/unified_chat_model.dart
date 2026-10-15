// Vommet: the Telegram-style unified chat list (Vommet issue 291).
//
// The pure part: row models, sorting, space aggregation and the drill-in
// navigation state. It knows nothing about Room/Space/Client, so unit tests
// (and renders) can feed it made-up data; unified_chat_source.dart turns the
// real client objects into these models.
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:intl/intl.dart';

enum ChatKind { direct, room, voice }

/// One chat: a DM, a room, or a voice room.
class ChatEntry {
  const ChatEntry({
    required this.key,
    required this.roomId,
    required this.name,
    this.kind = ChatKind.room,
    this.lastActivity,
    this.sender,
    this.preview,
    this.unread = 0,
    this.mentions = 0,
    this.muted = false,
    this.voiceCount = 0,
    this.voiceNames,
    this.avatar,
    this.color = const Color(0xff808080),
    this.source,
  });

  /// Unique across accounts (the room's localId).
  final String key;
  final String roomId;
  final String name;
  final ChatKind kind;

  /// When the newest event arrived; null while nothing is known.
  final DateTime? lastActivity;

  /// Who sent the newest message ("You", a display name, or null for the
  /// other person in a DM). Resolved only when a row is built, because a
  /// member lookup can hit the database.
  final String? Function()? sender;
  final String? preview;

  /// Unread messages, counted even when the chat is muted (a muted chat shows
  /// them in grey, like Telegram).
  final int unread;

  /// Mentions and other highlights (0 when the chat is fully muted).
  final int mentions;
  final bool muted;

  /// People in this voice room's call.
  final int voiceCount;
  final List<String> Function()? voiceNames;

  final ImageProvider? avatar;
  final Color color;

  /// The client object behind this entry (a Room), for opening it.
  final Object? source;

  bool get isDirect => kind == ChatKind.direct;
  bool get isVoice => kind == ChatKind.voice;
}

/// A room of a space that we haven't joined.
class ChatPreviewEntry {
  const ChatPreviewEntry({
    required this.roomId,
    required this.name,
    this.isVoice = false,
    this.memberCount,
    this.source,
  });

  final String roomId;
  final String name;
  final bool isVoice;
  final int? memberCount;
  final Object? source;
}

/// A space and what's in it, rooms in the space's own order.
class SpaceEntry {
  const SpaceEntry({
    required this.key,
    required this.spaceId,
    required this.name,
    this.rooms = const [],
    this.subspaces = const [],
    this.previews = const [],
    this.memberCount,
    this.muted = false,
    this.avatar,
    this.color = const Color(0xff808080),
    this.source,
  });

  final String key;
  final String spaceId;
  final String name;
  final List<ChatEntry> rooms;
  final List<SpaceEntry> subspaces;
  final List<ChatPreviewEntry> previews;
  final int? memberCount;
  final bool muted;
  final ImageProvider? avatar;
  final Color color;
  final Object? source;

  /// Every joined room in this space and its subspaces, each once. Survives
  /// a space hierarchy that loops back on itself.
  List<ChatEntry> get allRooms {
    final result = <ChatEntry>[];
    final seenRooms = <String>{};
    final seenSpaces = <String>{};

    void walk(SpaceEntry space) {
      if (!seenSpaces.add(space.key)) return;
      for (final room in space.rooms) {
        if (seenRooms.add(room.key)) result.add(room);
      }
      for (final sub in space.subspaces) {
        walk(sub);
      }
    }

    walk(this);
    return result;
  }

  /// This space and every subspace below it, each once.
  List<SpaceEntry> get allSpaces {
    final result = <SpaceEntry>[];
    final seen = <String>{};

    void walk(SpaceEntry space) {
      if (!seen.add(space.key)) return;
      result.add(space);
      for (final sub in space.subspaces) {
        walk(sub);
      }
    }

    walk(this);
    return result;
  }

  /// Finds this space or a subspace by key.
  SpaceEntry? find(String key) {
    for (final space in allSpaces) {
      if (space.key == key) return space;
    }
    return null;
  }
}

/// Newest first; chats with no known activity last, then by name.
int compareByActivity(ChatEntry a, ChatEntry b) =>
    _compareTimes(a.lastActivity, b.lastActivity, a.name, b.name);

int _compareTimes(DateTime? a, DateTime? b, String nameA, String nameB) {
  if (a != null && b != null) {
    final c = b.compareTo(a);
    if (c != 0) return c;
  } else if (a != null) {
    return -1;
  } else if (b != null) {
    return 1;
  }
  return nameA.toLowerCase().compareTo(nameB.toLowerCase());
}

/// What a space's row in the list shows: everything inside it, summed up.
class SpaceDigest {
  const SpaceDigest({
    this.latest,
    this.chips = const [],
    this.unread = 0,
    this.mentions = 0,
    this.lastActivity,
    this.voice,
    this.roomCount = 0,
  });

  /// The room with the newest message, across subspaces too.
  final ChatEntry? latest;

  /// Rooms for the chip line, most recently active first (the first one is
  /// the highlighted, newest one).
  final List<ChatEntry> chips;

  /// Unread messages in rooms that aren't muted.
  final int unread;
  final int mentions;
  final DateTime? lastActivity;

  /// The voice room with the most people in it, if anyone is in one.
  final ChatEntry? voice;
  final int roomCount;

  static SpaceDigest of(SpaceEntry space, {int maxChips = 6}) {
    final rooms = space.allRooms;
    final sorted = List.of(rooms)..sort(compareByActivity);

    var unread = 0;
    var mentions = 0;
    ChatEntry? voice;
    for (final room in rooms) {
      if (!room.muted) unread += room.unread;
      mentions += room.mentions;
      if (room.voiceCount > 0 &&
          (voice == null || room.voiceCount > voice.voiceCount)) {
        voice = room;
      }
    }

    final latest = sorted.firstOrNull;
    return SpaceDigest(
      latest: latest?.lastActivity == null ? null : latest,
      chips: sorted.take(maxChips).toList(growable: false),
      unread: unread,
      mentions: mentions,
      lastActivity: latest?.lastActivity,
      voice: voice,
      roomCount: rooms.length,
    );
  }
}

/// One row of the top-level list.
sealed class TopRow {
  const TopRow({this.pinned = false});

  final bool pinned;
  String get key;
  String get roomId;
  String get name;
  DateTime? get lastActivity;
}

class ChatTopRow extends TopRow {
  const ChatTopRow(this.chat, {super.pinned});
  final ChatEntry chat;

  @override
  String get key => chat.key;
  @override
  String get roomId => chat.roomId;
  @override
  String get name => chat.name;
  @override
  DateTime? get lastActivity => chat.lastActivity;
}

class SpaceTopRow extends TopRow {
  SpaceTopRow(this.space, {super.pinned, SpaceDigest? digest})
      : digest = digest ?? SpaceDigest.of(space);
  final SpaceEntry space;
  final SpaceDigest digest;

  @override
  String get key => space.key;
  @override
  String get roomId => space.spaceId;
  @override
  String get name => space.name;
  @override
  DateTime? get lastActivity => digest.lastActivity;
}

/// Builds the one list: DMs, rooms outside any space, and top-level spaces,
/// one row each. A room inside one of [spaces] never gets its own row (even
/// a DM), and a chat listed twice (a DM that's also a plain room) appears
/// once. Pinned chats ([pins]: room id -> saved order, null for a pin with
/// no order yet) come first in their saved order; the rest are newest first.
List<TopRow> buildTopRows({
  Iterable<ChatEntry> directMessages = const [],
  Iterable<ChatEntry> rooms = const [],
  Iterable<SpaceEntry> spaces = const [],
  Map<String, String?> pins = const {},
}) {
  final inSpaces = <String>{};
  final spaceKeys = <String>{};
  final nested = <String>{};
  for (final space in spaces) {
    for (final room in space.allRooms) {
      inSpaces.add(room.key);
    }
    for (final sub in space.allSpaces.skip(1)) {
      nested.add(sub.key);
    }
  }

  final rows = <TopRow>[];
  final seen = <String>{};

  for (final chat in [...directMessages, ...rooms]) {
    if (inSpaces.contains(chat.key) || !seen.add(chat.key)) continue;
    rows.add(ChatTopRow(chat, pinned: pins.containsKey(chat.roomId)));
  }

  for (final space in spaces) {
    // A space that's also inside another listed space shows only there.
    if (nested.contains(space.key) || !spaceKeys.add(space.key)) continue;
    if (!seen.add(space.key)) continue;
    rows.add(SpaceTopRow(space, pinned: pins.containsKey(space.spaceId)));
  }

  String pinOrder(TopRow row) => pins[row.roomId] ?? "~${row.roomId}";

  rows.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    if (a.pinned) {
      final c = pinOrder(a).compareTo(pinOrder(b));
      if (c != 0) return c;
    }
    return _compareTimes(a.lastActivity, b.lastActivity, a.name, b.name);
  });

  return rows;
}

/// The rows whose name, or (for a space) any room or subspace's name,
/// contains [query], ignoring case.
List<TopRow> filterTopRows(List<TopRow> rows, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return rows;

  bool matches(String name) => name.toLowerCase().contains(q);

  return rows.where((row) {
    if (matches(row.name)) return true;
    if (row case SpaceTopRow(:final space)) {
      return space.allRooms.any((r) => matches(r.name)) ||
          space.allSpaces.any((s) => matches(s.name));
    }
    return false;
  }).toList(growable: false);
}

/// The rows of an open space's pane: its rooms in the space's order, then
/// rooms we haven't joined, then its subspaces.
sealed class SpacePaneRow {
  const SpacePaneRow();
}

class SpaceRoomRow extends SpacePaneRow {
  const SpaceRoomRow(this.room);
  final ChatEntry room;
}

class SpacePreviewRow extends SpacePaneRow {
  const SpacePreviewRow(this.preview);
  final ChatPreviewEntry preview;
}

class SubspaceRow extends SpacePaneRow {
  SubspaceRow(this.space) : digest = SpaceDigest.of(space, maxChips: 4);
  final SpaceEntry space;
  final SpaceDigest digest;
}

List<SpacePaneRow> buildSpacePaneRows(SpaceEntry space) => [
      for (final room in space.rooms) SpaceRoomRow(room),
      for (final preview in space.previews) SpacePreviewRow(preview),
      for (final sub in space.subspaces)
        if (sub.key != space.key) SubspaceRow(sub),
    ];

/// Which space (and subspace) the list has open. Remembers, per top-level
/// space, the subspace last open there, so coming back to a space returns to
/// it (in memory only).
class SpaceNavigation extends ChangeNotifier {
  List<String> _path = const [];
  final Map<String, List<String>> _remembered = {};

  /// Keys from the top-level space down to the open (sub)space.
  List<String> get path => _path;
  bool get isOpen => _path.isNotEmpty;
  String? get root => isOpen ? _path.first : null;
  String? get current => isOpen ? _path.last : null;
  String? get parent => _path.length >= 2 ? _path[_path.length - 2] : null;

  /// Opens a top-level space, at the subspace last open in it.
  void openRoot(String key) {
    if (root == key) return;
    _path = List.unmodifiable(_remembered[key] ?? [key]);
    notifyListeners();
  }

  /// Goes one level deeper, into a subspace of the open space.
  void drillInto(String key) {
    if (!isOpen || current == key) return;
    final at = _path.indexOf(key);
    _path =
        List.unmodifiable(at >= 0 ? _path.sublist(0, at + 1) : [..._path, key]);
    _remembered[_path.first] = _path;
    notifyListeners();
  }

  /// Up one level; from a top-level space, back to the list.
  void back() {
    if (!isOpen) return;
    final up = _path.sublist(0, _path.length - 1);
    if (up.isNotEmpty) _remembered[up.first] = List.unmodifiable(up);
    _path = List.unmodifiable(up);
    notifyListeners();
  }

  /// Back to the list, remembering where each space was.
  void close() {
    if (!isOpen) return;
    _path = const [];
    notifyListeners();
  }

  /// Drops spaces that no longer exist (left, or no longer a subspace of
  /// the one above) from the open path and from what's remembered.
  void prune(bool Function(List<String> path) valid) {
    List<String> cut(List<String> path) {
      var end = 0;
      while (end < path.length && valid(path.sublist(0, end + 1))) {
        end++;
      }
      return List.unmodifiable(path.sublist(0, end));
    }

    _remembered.updateAll((_, p) => cut(p));
    _remembered.removeWhere((_, p) => p.isEmpty);

    final next = cut(_path);
    if (next.length != _path.length) {
      _path = next;
      notifyListeners();
    }
  }
}

/// The time on a row: the clock time today, "Yesterday", the weekday within
/// a week, then the date.
String formatChatTime(DateTime time, DateTime now,
    {bool use24HourFormat = false, String yesterday = "Yesterday"}) {
  final local = time.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  // Rounded: a day across a daylight saving change is 23 or 25 hours.
  final daysAgo = (today.difference(day).inHours / 24).round();

  if (daysAgo <= 0) {
    return (use24HourFormat ? DateFormat.Hm() : DateFormat.jm()).format(local);
  }
  if (daysAgo == 1) return yesterday;
  if (daysAgo < 7) return DateFormat.E().format(local);
  if (local.year == now.year) return DateFormat.MMMd().format(local);
  return DateFormat.yMMMd().format(local);
}
