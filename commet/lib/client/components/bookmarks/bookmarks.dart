import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: a saved message. Only the room and message ids are kept (no
/// copy of the text), plus your own tags and an optional note.
class Bookmark {
  final String roomId;
  final String eventId;
  final int savedTs;
  final List<String> tags;
  final String? note;

  const Bookmark({
    required this.roomId,
    required this.eventId,
    required this.savedTs,
    this.tags = const [],
    this.note,
  });

  Bookmark copyWith(
          {List<String>? tags, String? note, bool clearNote = false}) =>
      Bookmark(
        roomId: roomId,
        eventId: eventId,
        savedTs: savedTs,
        tags: tags ?? this.tags,
        note: clearNote ? null : (note ?? this.note),
      );

  static Bookmark? fromJson(Object? json) {
    if (json is! Map) return null;
    final roomId = json["room_id"];
    final eventId = json["event_id"];
    if (roomId is! String || eventId is! String) return null;
    if (roomId.isEmpty || eventId.isEmpty) return null;
    final ts = json["saved_ts"];
    final tags = json["tags"];
    final note = json["note"];
    return Bookmark(
      roomId: roomId,
      eventId: eventId,
      savedTs: ts is int ? ts : 0,
      tags: tags is List ? Bookmarks.cleanTags(tags.whereType<String>()) : [],
      note: note is String && note.trim().isNotEmpty ? note : null,
    );
  }

  Map<String, Object?> toJson() => {
        "room_id": roomId,
        "event_id": eventId,
        "saved_ts": savedTs,
        "tags": tags,
        if (note != null) "note": note,
      };
}

typedef BookmarkBatchResult = ({
  Set<String> saved,
  Set<String> existing,
  Set<String> full
});

/// Vommet: saved messages across all your rooms, with tags. They live in
/// your private account data (`im.nether.vommet.bookmarks`), so they follow
/// you to your other devices and nobody else sees them. The homeserver can
/// read the tags and notes. Other apps don't show them.
class Bookmarks {
  static const String type = "im.nether.vommet.bookmarks";
  static const int version = 1;

  /// Oldest bookmarks are dropped past this many.
  static const int maxItems = 1000;
  static const int maxTagLength = 32;

  static final Map<matrix.Client, Future<void>> _pending = {};

  /// Bumps whenever your bookmarks change, here or on another device.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static final Map<matrix.Client, StreamSubscription> _watching = {};

  static matrix.Client? _matrixClient(Client client) =>
      client is MatrixClient ? client.matrixClient : null;

  static bool supported(Client client) => _matrixClient(client) != null;

  /// Every bookmark, newest first.
  static List<Bookmark> of(Client client) {
    final mx = _matrixClient(client);
    if (mx == null) return const [];
    _watch(mx);
    return parse(mx.accountData[type]?.content);
  }

  /// Newest first, one per message; unreadable entries are skipped.
  static List<Bookmark> parse(Map<String, Object?>? content) {
    final items = content?["items"];
    if (items is! List) return const [];
    final seen = <String>{};
    final result = <Bookmark>[];
    for (final item in items) {
      final b = Bookmark.fromJson(item);
      if (b == null || !seen.add("${b.roomId}\n${b.eventId}")) continue;
      result.add(b);
    }
    result.sort((a, b) => b.savedTs.compareTo(a.savedTs));
    return result;
  }

  static Map<String, Object?> serialize(List<Bookmark> items) => {
        "version": version,
        "items": items.take(maxItems).map((b) => b.toJson()).toList(),
      };

  /// Trimmed, lower-cased, no duplicates, in the order given.
  static List<String> cleanTags(Iterable<String> tags) {
    final result = <String>[];
    for (var tag in tags) {
      tag = tag.trim().toLowerCase();
      if (tag.startsWith("#")) tag = tag.substring(1).trim();
      if (tag.isEmpty) continue;
      if (tag.length > maxTagLength) tag = tag.substring(0, maxTagLength);
      if (!result.contains(tag)) result.add(tag);
    }
    return result;
  }

  static Bookmark? find(Client client, String roomId, String eventId) {
    for (final b in of(client)) {
      if (b.roomId == roomId && b.eventId == eventId) return b;
    }
    return null;
  }

  static bool isSaved(Client client, String roomId, String eventId) =>
      find(client, roomId, eventId) != null;

  /// Every tag in use, most used first.
  static List<String> allTags(Client client) => tagsOf(of(client));

  static List<String> tagsOf(List<Bookmark> items) {
    final counts = <String, int>{};
    for (final b in items) {
      for (final t in b.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final tags = counts.keys.toList();
    tags.sort((a, b) {
      final c = counts[b]!.compareTo(counts[a]!);
      return c != 0 ? c : a.compareTo(b);
    });
    return tags;
  }

  // Serialize the read-modify-write, not just the network requests. Other
  // devices still use Matrix's existing last-write-wins account data.
  static Future<T> _queued<T>(
      matrix.Client mx, Future<T> Function(String userId) operation) {
    final userId = mx.userID;
    final result = (_pending[mx] ?? Future<void>.value()).then((_) {
      if (userId == null || mx.userID != userId) {
        throw StateError("Bookmark account changed");
      }
      return operation(userId);
    });
    // A failed write must not poison the next operation or leak an unhandled
    // error from the bookkeeping future. Return the original error to callers.
    final tail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _pending[mx] = tail;
    tail.then((_) {
      if (identical(_pending[mx], tail)) _pending.remove(mx);
    });
    return result;
  }

  static Future<void> save(Client client, String roomId, String eventId,
      {List<String> tags = const [], String? note}) {
    final mx = _matrixClient(client);
    if (mx == null) return Future.value();
    final cleaned = cleanTags(tags);
    return _queued(mx, (userId) {
      final items = of(client);
      final existing = items
          .where((b) => b.roomId == roomId && b.eventId == eventId)
          .firstOrNull;
      final saved = Bookmark(
        roomId: roomId,
        eventId: eventId,
        savedTs: existing?.savedTs ?? DateTime.now().millisecondsSinceEpoch,
        tags: cleaned,
        note: note != null && note.trim().isNotEmpty ? note.trim() : null,
      );
      return _set(mx, userId, [
        saved,
        ...items.where((b) => !(b.roomId == roomId && b.eventId == eventId))
      ]);
    });
  }

  static Future<void> remove(Client client, String roomId, String eventId) {
    final mx = _matrixClient(client);
    if (mx == null) return Future.value();
    return _queued(
        mx,
        (userId) => _set(
            mx,
            userId,
            of(client)
                .where((b) => !(b.roomId == roomId && b.eventId == eventId))
                .toList()));
  }

  /// Add new saves in timeline order, without changing any existing metadata
  /// or evicting old bookmarks. One batch makes at most one account-data write.
  static Future<BookmarkBatchResult> saveBatch(
      Client client, String roomId, Iterable<String> eventIds,
      {required bool Function(String) canSave}) {
    final mx = _matrixClient(client);
    if (mx == null)
      return Future.error(UnsupportedError("Bookmarks unavailable"));
    final ids = eventIds.toSet();
    return _queued(mx, (userId) async {
      final items = [...of(client)];
      final known = {
        for (final b in items)
          if (b.roomId == roomId) b.eventId
      };
      final saved = <String>{}, existing = <String>{}, full = <String>{};
      var ts = DateTime.now().millisecondsSinceEpoch;
      if (items.isNotEmpty && ts <= items.first.savedTs)
        ts = items.first.savedTs + 1;
      for (final id in ids) {
        if (!canSave(id)) continue;
        if (known.contains(id)) {
          existing.add(id);
        } else if (items.length >= maxItems) {
          full.add(id);
        } else {
          items.add(Bookmark(roomId: roomId, eventId: id, savedTs: ts++));
          saved.add(id);
        }
      }
      if (saved.isNotEmpty) await _set(mx, userId, items);
      return (saved: saved, existing: existing, full: full);
    });
  }

  static Future<void> _set(
      matrix.Client mx, String userId, List<Bookmark> items) async {
    items.sort((a, b) => b.savedTs.compareTo(a.savedTs));
    final content = serialize(items);
    await mx.setAccountData(userId, type, content);
    if (mx.userID != userId) throw StateError("Bookmark account changed");
    // Show it now rather than when the sync echoes it back.
    mx.accountData[type] = matrix.BasicEvent(type: type, content: content);
    changed.value++;
  }

  static void _watch(matrix.Client client) {
    if (_watching.containsKey(client)) return;
    _watching[client] = client.onSync.stream.listen((sync) {
      if (sync.accountData?.any((e) => e.type == type) == true) {
        changed.value++;
      }
    });
  }
}
