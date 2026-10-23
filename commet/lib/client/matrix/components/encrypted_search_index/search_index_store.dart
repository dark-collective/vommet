// Vommet (issues 602, 611): the encrypted search index's database. One
// SQLite file per account, next to the account's message store (data.db),
// which already holds the same decrypted messages; so the index is kept
// exactly like the messages are. Synchronous: it only runs inside the
// index's isolate (SearchIndexWorker) and in unit tests.
//
// Coverage is tracked per room as "segments" still to scan backwards: a
// segment starts at a pagination token (null = the newest message) and ends
// at the room's start (the backfill, stopTs null) or once it reaches a
// message the index already covers (stopTs = the newest covered message).
// So every stretch of history is fetched once, whether by the background
// indexer or by a search paging back while the indexer is off.
import 'dart:convert';

import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart';
import 'package:sqlite3/sqlite3.dart';

export 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart';

class SearchIndexStore {
  SearchIndexStore._(this.db) {
    _migrate();
  }

  final Database db;

  static SearchIndexStore open(String path) =>
      SearchIndexStore._(sqlite3.open(path));

  static SearchIndexStore openInMemory() =>
      SearchIndexStore._(sqlite3.openInMemory());

  static const _schemaVersion = 1;

  void _migrate() {
    db.execute("PRAGMA journal_mode = WAL;");
    // Another engine of the app (an Android bubble) may write at once.
    db.execute("PRAGMA busy_timeout = 5000;");
    final version = db.select("PRAGMA user_version;").first.values.first as int;
    if (version == _schemaVersion) return;
    // Version 0 = a new file. A future schema change can simply drop and
    // rebuild: the index is a cache.
    db.execute("""
      DROP TABLE IF EXISTS events; DROP TABLE IF EXISTS edits;
      DROP TABLE IF EXISTS redacted; DROP TABLE IF EXISTS undecrypted;
      DROP TABLE IF EXISTS rooms; DROP TABLE IF EXISTS segments;
      CREATE TABLE events(
        event_id TEXT PRIMARY KEY, room_id TEXT NOT NULL,
        sender TEXT NOT NULL, ts INTEGER NOT NULL, type TEXT NOT NULL,
        msgtype TEXT, mimetype TEXT, kind INTEGER NOT NULL,
        search_text TEXT NOT NULL, edit_text TEXT, edit_ts INTEGER,
        edit_content TEXT, links TEXT, link_count INTEGER NOT NULL,
        json TEXT NOT NULL);
      CREATE INDEX events_room_ts ON events(room_id, ts DESC);
      CREATE INDEX events_room_kind ON events(room_id, kind, ts DESC);
      CREATE TABLE edits(
        target_id TEXT NOT NULL, room_id TEXT NOT NULL,
        sender TEXT NOT NULL, ts INTEGER NOT NULL,
        search_text TEXT NOT NULL, content TEXT NOT NULL,
        PRIMARY KEY(target_id, sender));
      CREATE TABLE redacted(event_id TEXT PRIMARY KEY, room_id TEXT NOT NULL);
      CREATE TABLE undecrypted(
        event_id TEXT PRIMARY KEY, room_id TEXT NOT NULL,
        ts INTEGER NOT NULL, json TEXT NOT NULL);
      CREATE INDEX undecrypted_room ON undecrypted(room_id);
      CREATE TABLE rooms(
        room_id TEXT PRIMARY KEY, head_ts INTEGER, oldest_ts INTEGER,
        complete INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE segments(
        id INTEGER PRIMARY KEY AUTOINCREMENT, room_id TEXT NOT NULL,
        from_token TEXT, stop_ts INTEGER,
        started INTEGER NOT NULL DEFAULT 0);
      CREATE INDEX segments_room ON segments(room_id);
      PRAGMA user_version = $_schemaVersion;
    """);
  }

  void dispose() => db.dispose();

  T _transaction<T>(T Function() body) {
    db.execute("BEGIN");
    try {
      final result = body();
      db.execute("COMMIT");
      return result;
    } catch (_) {
      db.execute("ROLLBACK");
      rethrow;
    }
  }

  // ---- coverage ----------------------------------------------------------

  RoomCoverage coverage(String roomId) {
    final row = db.select(
        "SELECT head_ts, oldest_ts, complete, "
        "(SELECT count(*) FROM segments s WHERE s.room_id = r.room_id) AS n "
        "FROM rooms r WHERE room_id = ?",
        [roomId]);
    if (row.isEmpty) return RoomCoverage.unknown;
    final r = row.first;
    return RoomCoverage(
      known: true,
      complete: r["complete"] == 1,
      oldestTs: r["oldest_ts"] as int?,
      headTs: r["head_ts"] as int?,
      pendingSegments: r["n"] as int,
    );
  }

  /// Adds [roomId] with a backfill from its newest message, once.
  void ensureRoom(String roomId) {
    _transaction(() {
      if (db.select(
          "SELECT 1 FROM rooms WHERE room_id = ?", [roomId]).isNotEmpty) {
        return;
      }
      db.execute("INSERT INTO rooms(room_id) VALUES (?)", [roomId]);
      db.execute(
          "INSERT INTO segments(room_id, from_token, stop_ts) "
          "VALUES (?, NULL, NULL)",
          [roomId]);
    });
  }

  /// Scans from the newest message down to what's already covered, for
  /// messages that arrived while the app was closed or the index was off.
  /// Does nothing when such a scan is already waiting.
  void addTopSegment(String roomId) {
    ensureRoom(roomId);
    _transaction(() {
      final waiting = db.select(
          "SELECT 1 FROM segments WHERE room_id = ? AND from_token IS NULL "
          "AND started = 0",
          [roomId]);
      if (waiting.isNotEmpty) return;
      final head = coverage(roomId).headTs;
      if (head == null) return; // the backfill hasn't started: it covers it
      db.execute(
          "INSERT INTO segments(room_id, from_token, stop_ts) VALUES (?, NULL, ?)",
          [roomId, head]);
    });
  }

  /// A limited sync skipped messages: scan back from [fromToken] (the sync's
  /// prev_batch) to the newest covered message.
  void addGapSegment(String roomId, String fromToken) {
    final head = coverage(roomId).headTs;
    if (head == null) return;
    db.execute(
        "INSERT INTO segments(room_id, from_token, stop_ts) VALUES (?, ?, ?)",
        [roomId, fromToken, head]);
  }

  /// The next stretch to scan in [roomId]: recent gaps first, then the
  /// backfill.
  IndexSegment? nextSegment(String roomId) {
    final rows = db.select(
        "SELECT id, from_token, stop_ts FROM segments WHERE room_id = ? "
        "ORDER BY (stop_ts IS NULL), id DESC LIMIT 1",
        [roomId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return IndexSegment(
        id: r["id"] as int,
        roomId: roomId,
        fromToken: r["from_token"] as String?,
        stopTs: r["stop_ts"] as int?);
  }

  /// The first of [roomIds] (in that order) with something left to scan,
  /// preferring rooms with recent gaps.
  String? nextRoom(List<String> roomIds) {
    if (roomIds.isEmpty) return null;
    final pending = <String, bool>{};
    for (final r
        in db.select("SELECT room_id, min(stop_ts IS NULL) AS backfill_only "
            "FROM segments GROUP BY room_id")) {
      pending[r["room_id"] as String] = r["backfill_only"] == 1;
    }
    for (final id in roomIds) {
      if (pending[id] == false) return id;
    }
    for (final id in roomIds) {
      if (pending.containsKey(id)) return id;
    }
    return null;
  }

  /// Stores one page of [segmentId] (newest first, as /messages returns it
  /// backwards) and moves the segment on to [end], or ends it.
  IndexPageResult applyPage(String roomId, int segmentId,
      List<Map<String, dynamic>> events, String? end,
      {List<Map<String, dynamic>> undecrypted = const []}) {
    return _transaction(() {
      final seg = db.select(
          "SELECT from_token, stop_ts FROM segments WHERE id = ?", [segmentId]);
      if (seg.isEmpty) {
        return IndexPageResult(
            added: 0, segmentDone: true, coverage: coverage(roomId));
      }
      final fromNewest = seg.first["from_token"] == null;
      final stopTs = seg.first["stop_ts"] as int?;

      var added = 0;
      int? minTs;
      int? maxTs;
      for (final e in [...events, ...undecrypted]) {
        final ts = e["origin_server_ts"];
        if (ts is! int) continue;
        if (minTs == null || ts < minTs) minTs = ts;
        if (maxTs == null || ts > maxTs) maxTs = ts;
      }
      for (final e in events) {
        if (_insert(roomId, e)) added++;
      }
      for (final e in undecrypted) {
        _insertUndecrypted(roomId, e);
      }

      if (fromNewest && maxTs != null) _advanceHead(roomId, maxTs);
      if (stopTs == null && minTs != null) {
        db.execute(
            "UPDATE rooms SET oldest_ts = min(coalesce(oldest_ts, ?), ?) "
            "WHERE room_id = ?",
            [minTs, minTs, roomId]);
      }

      final reachedStart =
          end == null || (events.isEmpty && undecrypted.isEmpty);
      final reachedStop = stopTs != null && minTs != null && minTs <= stopTs;
      final done = reachedStart || reachedStop;
      if (done) {
        db.execute("DELETE FROM segments WHERE id = ?", [segmentId]);
        if (stopTs == null) {
          db.execute(
              "UPDATE rooms SET complete = 1 WHERE room_id = ?", [roomId]);
        }
      } else {
        db.execute(
            "UPDATE segments SET from_token = ?, started = 1 WHERE id = ?",
            [end, segmentId]);
      }
      return IndexPageResult(
          added: added, segmentDone: done, coverage: coverage(roomId));
    });
  }

  /// Messages that arrived by sync, decrypted. [headTs] (the newest message
  /// of a sync that wasn't limited) moves the covered head on.
  int addLive(String roomId, List<Map<String, dynamic>> events, {int? headTs}) {
    return _transaction(() {
      var added = 0;
      for (final e in events) {
        if (_insert(roomId, e)) added++;
      }
      if (headTs != null) _advanceHead(roomId, headTs);
      return added;
    });
  }

  void _advanceHead(String roomId, int ts) {
    db.execute(
        "UPDATE rooms SET head_ts = max(coalesce(head_ts, ?), ?) "
        "WHERE room_id = ?",
        [ts, ts, roomId]);
  }

  bool _insert(String roomId, Map<String, dynamic> json) {
    final extract = IndexExtract.of(json);
    switch (extract) {
      case null:
        return false;
      case IndexRedaction(:final targetId):
        db.execute(
            "INSERT OR IGNORE INTO redacted VALUES (?, ?)", [targetId, roomId]);
        db.execute("DELETE FROM events WHERE event_id = ?", [targetId]);
        db.execute("DELETE FROM edits WHERE target_id = ?", [targetId]);
        db.execute("DELETE FROM undecrypted WHERE event_id = ?", [targetId]);
        return false;
      case IndexEditExtract(:final edit):
        final content = (json["content"] as Map)["m.new_content"];
        final contentJson = jsonEncode(content);
        db.execute(
            "INSERT INTO edits VALUES (?, ?, ?, ?, ?, ?) "
            "ON CONFLICT(target_id, sender) DO UPDATE SET ts = excluded.ts, "
            "search_text = excluded.search_text, "
            "content = excluded.content WHERE excluded.ts > edits.ts",
            [
              edit.targetId,
              roomId,
              json["sender"],
              edit.ts,
              edit.searchText,
              contentJson
            ]);
        // Only the original sender's edits count, as in the timeline.
        db.execute(
            "UPDATE events SET edit_text = ?, edit_ts = ?, edit_content = ? "
            "WHERE event_id = ? AND sender = ? "
            "AND (edit_ts IS NULL OR edit_ts < ?)",
            [
              edit.searchText,
              edit.ts,
              contentJson,
              edit.targetId,
              json["sender"],
              edit.ts
            ]);
        return false;
      case IndexEventExtract(:final event):
        if (db.select("SELECT 1 FROM redacted WHERE event_id = ?",
            [event.eventId]).isNotEmpty) {
          return false;
        }
        db.execute(
            "DELETE FROM undecrypted WHERE event_id = ?", [event.eventId]);
        final edit = db.select(
            "SELECT ts, search_text, content FROM edits "
            "WHERE target_id = ? AND sender = ?",
            [event.eventId, event.senderId]);
        db.execute(
            "INSERT OR IGNORE INTO events(event_id, room_id, sender, ts, type, "
            "msgtype, mimetype, kind, search_text, edit_text, edit_ts, "
            "edit_content, links, link_count, json) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
              event.eventId,
              roomId,
              event.senderId,
              event.ts,
              event.type,
              event.msgtype,
              event.mimetype,
              event.kind.index,
              event.searchText,
              edit.isEmpty ? null : edit.first["search_text"],
              edit.isEmpty ? null : edit.first["ts"],
              edit.isEmpty ? null : edit.first["content"],
              event.links.isEmpty ? null : event.links.join("\n"),
              event.links.length,
              jsonEncode(event.json),
            ]);
        return db.updatedRows > 0;
    }
  }

  void _insertUndecrypted(String roomId, Map<String, dynamic> json) {
    final id = json["event_id"];
    final ts = json["origin_server_ts"];
    if (id is! String || ts is! int) return;
    db.execute("INSERT OR IGNORE INTO undecrypted VALUES (?, ?, ?, ?)",
        [id, roomId, ts, jsonEncode(json)]);
  }

  // ---- messages that didn't decrypt yet ----------------------------------

  /// Up to [limit] still-encrypted events of [roomId], to try again once
  /// keys arrive.
  List<Map<String, dynamic>> undecrypted(String roomId, {int limit = 200}) => [
        for (final r in db.select(
            "SELECT json FROM undecrypted WHERE room_id = ? "
            "ORDER BY ts DESC LIMIT ?",
            [roomId, limit]))
          jsonDecode(r["json"] as String) as Map<String, dynamic>,
      ];

  /// Rooms with messages that didn't decrypt yet.
  List<String> roomsWithUndecrypted() => [
        for (final r in db.select("SELECT DISTINCT room_id FROM undecrypted"))
          r["room_id"] as String
      ];

  /// Stores events that decrypt now (they leave the undecrypted list).
  int addDecrypted(String roomId, List<Map<String, dynamic>> events) =>
      addLive(roomId, events);

  // ---- queries -----------------------------------------------------------

  static const List<SharedContentKind> _imageKinds = [
    SharedContentKind.image,
    SharedContentKind.gif,
  ];

  /// Messages of [roomId] matching [query], newest first, older than
  /// [beforeTs] if given.
  List<IndexHit> search(String roomId, IndexQuery query,
      {int? beforeTs, int limit = 500}) {
    final where = <String>["room_id = ?"];
    final args = <Object?>[roomId];
    if (beforeTs != null) {
      where.add("ts < ?");
      args.add(beforeTs);
    }
    if (query.senderId != null) {
      where.add("sender = ?");
      args.add(query.senderId);
    }
    if (query.type != null) {
      where.add("(type = ? OR msgtype = ?)");
      args.addAll([query.type, query.type]);
    }
    if (query.requireLink) where.add("link_count > 0");
    if (query.requireImage) {
      where.add("kind IN (${_imageKinds.map((k) => k.index).join(",")})");
    }
    if (query.requireVideo) {
      where.add("kind = ${SharedContentKind.video.index}");
    }
    if (query.requireAttachment) {
      where.add("kind NOT IN (${SharedContentKind.text.index}, "
          "${SharedContentKind.sticker.index})");
    }
    final words = query.words.where((w) => w.isNotEmpty).toList();
    if (words.isNotEmpty) {
      final matches = words
          .map((_) => "(instr(coalesce(edit_text, search_text), ?) > 0)")
          .join(" + ");
      where.add("(($matches) * 2 >= ${words.length})");
      args.addAll(words);
    }
    args.add(limit);
    return _hits(db.select(
        "SELECT event_id, ts, kind, json, edit_content, links FROM events "
        "WHERE ${where.join(" AND ")} ORDER BY ts DESC LIMIT ?",
        args));
  }

  /// Messages of [roomId] of the given [kinds], newest first (for the
  /// Media and Files tabs). [linksOnly] lists messages with links instead
  /// (the Links tab).
  List<IndexHit> list(String roomId,
      {Set<SharedContentKind> kinds = const {},
      bool linksOnly = false,
      int? beforeTs,
      int limit = 100}) {
    final where = <String>["room_id = ?"];
    final args = <Object?>[roomId];
    if (kinds.isNotEmpty) {
      where.add("kind IN (${kinds.map((k) => k.index).join(",")})");
    }
    if (linksOnly) where.add("link_count > 0");
    if (beforeTs != null) {
      where.add("ts < ?");
      args.add(beforeTs);
    }
    args.add(limit);
    return _hits(db.select(
        "SELECT event_id, ts, kind, json, edit_content, links FROM events "
        "WHERE ${where.join(" AND ")} ORDER BY ts DESC LIMIT ?",
        args));
  }

  List<IndexHit> _hits(ResultSet rows) => [
        for (final r in rows)
          IndexHit(
            eventId: r["event_id"] as String,
            ts: r["ts"] as int,
            kind: SharedContentKind.values[r["kind"] as int],
            json: _withEdit(
                jsonDecode(r["json"] as String), r["edit_content"] as String?),
            links: (r["links"] as String?)?.split("\n") ?? const [],
          ),
      ];

  /// The event as the timeline shows it: an edit's new content replaces
  /// the original's (keeping the original's reply relation).
  static Map<String, dynamic> _withEdit(
      Map<String, dynamic> json, String? editContent) {
    if (editContent == null) return json;
    final newContent = jsonDecode(editContent);
    if (newContent is! Map) return json;
    final content = Map<String, dynamic>.from(newContent);
    final relates = (json["content"] as Map?)?["m.relates_to"];
    if (relates != null) content["m.relates_to"] = relates;
    return {...json, "content": content};
  }

  SharedContentCounts counts(String roomId) {
    final byKind = <SharedContentKind, int>{};
    for (final r in db.select(
        "SELECT kind, count(*) AS n FROM events WHERE room_id = ? "
        "GROUP BY kind",
        [roomId])) {
      byKind[SharedContentKind.values[r["kind"] as int]] = r["n"] as int;
    }
    final links = db.select(
        "SELECT coalesce(sum(link_count), 0) AS n FROM events "
        "WHERE room_id = ?",
        [roomId]).first["n"] as int;
    return SharedContentCounts(
      images: byKind[SharedContentKind.image] ?? 0,
      videos: byKind[SharedContentKind.video] ?? 0,
      gifs: byKind[SharedContentKind.gif] ?? 0,
      files: byKind[SharedContentKind.file] ?? 0,
      voice: byKind[SharedContentKind.voice] ?? 0,
      audio: byKind[SharedContentKind.audio] ?? 0,
      stickers: byKind[SharedContentKind.sticker] ?? 0,
      links: links,
    );
  }

  /// How many of [roomIds] are fully indexed.
  int completeCount(List<String> roomIds) {
    if (roomIds.isEmpty) return 0;
    final complete = {
      for (final r in db.select("SELECT room_id FROM rooms WHERE complete = 1 "
          "AND NOT EXISTS (SELECT 1 FROM segments s "
          "WHERE s.room_id = rooms.room_id)"))
        r["room_id"] as String
    };
    return roomIds.where(complete.contains).length;
  }

  // ---- forgetting --------------------------------------------------------

  void deleteRoom(String roomId) {
    _transaction(() {
      for (final table in const [
        "events",
        "edits",
        "redacted",
        "undecrypted",
        "rooms",
        "segments"
      ]) {
        db.execute("DELETE FROM $table WHERE room_id = ?", [roomId]);
      }
    });
  }

  void clear() {
    _transaction(() {
      for (final table in const [
        "events",
        "edits",
        "redacted",
        "undecrypted",
        "rooms",
        "segments"
      ]) {
        db.execute("DELETE FROM $table");
      }
    });
    db.execute("VACUUM");
  }
}
