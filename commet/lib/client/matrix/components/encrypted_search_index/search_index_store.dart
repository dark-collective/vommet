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
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:sqlite3/sqlite3.dart';

export 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart';

class SearchIndexStore {
  SearchIndexStore._(this.db, {this.ownUserId, bool reader = false}) {
    if (reader) {
      db.execute("PRAGMA busy_timeout = 5000;");
      _detectFullText();
    } else {
      _migrate();
    }
  }

  final Database db;

  /// The account's user id: a message naming it counts as mentioning me
  /// (Deep Search's "Mentions me").
  final String? ownUserId;

  /// Whether this SQLite has the full-text tables (FTS5); without them
  /// every search falls back to instr().
  bool get hasFullText => _fts;
  bool _fts = false;

  /// The trigram table for Chinese, Japanese and Korean text, which the
  /// word tokenizer can't split.
  bool _tri = false;

  /// Opens (or creates) the index at [path], keyed with [key] when it is
  /// encrypted (Vommet local data encryption; see [EncryptedOpen]).
  static SearchIndexStore open(String path,
          {String? ownUserId, Uint8List? key}) =>
      SearchIndexStore._(EncryptedOpen.open(path, key: key),
          ownUserId: ownUserId);

  /// A second, read-only connection for searches (Deep Search), so typing
  /// never waits behind the backfill's writes. WAL lets it read while the
  /// writer writes. The writer must have opened (migrated) the file first.
  static SearchIndexStore openReader(String path,
          {String? ownUserId, Uint8List? key}) =>
      SearchIndexStore._(EncryptedOpen.open(path, key: key, readOnly: true),
          ownUserId: ownUserId, reader: true);

  static SearchIndexStore openInMemory({String? ownUserId}) =>
      SearchIndexStore._(sqlite3.openInMemory(), ownUserId: ownUserId);

  static const _schemaVersion = 2;

  void _migrate() {
    db.execute("PRAGMA journal_mode = WAL;");
    // Another engine of the app (an Android bubble) may write at once.
    db.execute("PRAGMA busy_timeout = 5000;");
    var version = db.select("PRAGMA user_version;").first.values.first as int;
    if (version > _schemaVersion) {
      // A newer Vommet's file (after a downgrade): it's a cache, rebuild.
      version = 0;
    }
    if (version == 0) _createV1();
    // Vommet Deep Search: v1 → v2 keeps every row (dropping the cache made
    // every device download its whole history again). The new columns are
    // filled, and the full-text index built, from the stored events in
    // the background ([migrateStep]); until then those rows are searched
    // with instr().
    if (version <= 1) _transaction(_upgradeToV2);
    _ensureFullText();
  }

  void _createV1() {
    db.execute("""
      DROP TABLE IF EXISTS events; DROP TABLE IF EXISTS edits;
      DROP TABLE IF EXISTS redacted; DROP TABLE IF EXISTS undecrypted;
      DROP TABLE IF EXISTS rooms; DROP TABLE IF EXISTS segments;
      DROP TABLE IF EXISTS meta; DROP TABLE IF EXISTS events_fts;
      DROP TABLE IF EXISTS events_tri;
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
      PRAGMA user_version = 1;
    """);
  }

  /// v2 (Deep Search): mentions, threads and replies per message; `doc_id`
  /// keys the full-text tables (a stable id derived from the message time,
  /// so the newest matches come first without sorting); `v2` = 0 marks a
  /// row [migrateStep] still has to fill. `saw_create` tells a room indexed
  /// back to its creation from one the server only shows part of (NULL =
  /// indexed before v2, unknown).
  void _upgradeToV2() {
    db.execute("""
      ALTER TABLE events ADD COLUMN doc_id INTEGER;
      ALTER TABLE events ADD COLUMN mention_ids TEXT;
      ALTER TABLE events ADD COLUMN mentions_me INTEGER NOT NULL DEFAULT 0;
      ALTER TABLE events ADD COLUMN thread_root TEXT;
      ALTER TABLE events ADD COLUMN is_reply INTEGER NOT NULL DEFAULT 0;
      ALTER TABLE events ADD COLUMN v2 INTEGER NOT NULL DEFAULT 0;
      ALTER TABLE rooms ADD COLUMN saw_create INTEGER;
      CREATE UNIQUE INDEX events_doc ON events(doc_id);
      CREATE INDEX events_ts ON events(ts DESC);
      CREATE INDEX events_pending ON events(v2) WHERE v2 = 0;
      CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
      PRAGMA user_version = 2;
    """);
  }

  bool _tableExists(String name) => db
      .select("SELECT 1 FROM sqlite_master WHERE name = ?", [name]).isNotEmpty;

  void _detectFullText() {
    _fts = _tableExists("events_fts");
    _tri = _tableExists("events_tri");
  }

  /// Creates the full-text tables where this SQLite supports them (FTS5;
  /// trigram needs 3.34). Tables created over existing rows get filled by
  /// [migrateStep].
  void _ensureFullText() {
    var created = false;
    if (!_tableExists("events_fts")) {
      for (final diacritics in const [2, 1]) {
        try {
          db.execute("CREATE VIRTUAL TABLE events_fts USING fts5(text, "
              "tokenize = 'unicode61 remove_diacritics $diacritics', "
              "prefix = '2 3')");
          created = true;
          break;
        } on SqliteException {
          // older SQLite, or no FTS5
        }
      }
    }
    if (!_tableExists("events_tri") && _tableExists("events_fts")) {
      try {
        db.execute(
            "CREATE VIRTUAL TABLE events_tri USING fts5(text, tokenize = 'trigram')");
        created = true;
      } on SqliteException {
        // SQLite older than 3.34: CJK words use instr()
      }
    }
    _detectFullText();
    if (created) db.execute("UPDATE events SET v2 = 0 WHERE v2 = 1");
  }

  void dispose() => db.close();

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
        "SELECT head_ts, oldest_ts, complete, saw_create, "
        "(SELECT count(*) FROM segments s WHERE s.room_id = r.room_id) AS n, "
        "(SELECT count(*) FROM undecrypted u WHERE u.room_id = r.room_id) "
        "AS u FROM rooms r WHERE room_id = ?",
        [roomId]);
    if (row.isEmpty) return RoomCoverage.unknown;
    final r = row.first;
    return RoomCoverage(
      known: true,
      complete: r["complete"] == 1,
      oldestTs: r["oldest_ts"] as int?,
      headTs: r["head_ts"] as int?,
      pendingSegments: r["n"] as int,
      undecrypted: r["u"] as int,
      historyLimited: r["complete"] == 1 && r["saw_create"] == 0,
    );
  }

  /// Adds [roomId] with a backfill from its newest message, once.
  void ensureRoom(String roomId) {
    _transaction(() {
      if (db.select(
          "SELECT 1 FROM rooms WHERE room_id = ?", [roomId]).isNotEmpty) {
        return;
      }
      db.execute(
          "INSERT INTO rooms(room_id, saw_create) VALUES (?, 0)", [roomId]);
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
      if (events.any((e) => e["type"] == "m.room.create")) {
        db.execute(
            "UPDATE rooms SET saw_create = 1 WHERE room_id = ?", [roomId]);
      }
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
        for (final r in db.select(
            "SELECT doc_id FROM events WHERE event_id = ? "
            "AND doc_id IS NOT NULL",
            [targetId])) {
          _unindexText(r["doc_id"] as int);
        }
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
        if (db.updatedRows > 0) {
          for (final r in db.select(
              "SELECT doc_id FROM events WHERE event_id = ? AND v2 = 1 "
              "AND doc_id IS NOT NULL",
              [edit.targetId])) {
            _indexText(r["doc_id"] as int, edit.searchText);
          }
        }
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
        if (db.select("SELECT 1 FROM events WHERE event_id = ?",
            [event.eventId]).isNotEmpty) {
          return false;
        }
        final editText =
            edit.isEmpty ? null : edit.first["search_text"] as String?;
        final docId = _newDocId(event.ts);
        db.execute(
            "INSERT OR IGNORE INTO events(event_id, room_id, sender, ts, type, "
            "msgtype, mimetype, kind, search_text, edit_text, edit_ts, "
            "edit_content, links, link_count, json, doc_id, mention_ids, "
            "mentions_me, thread_root, is_reply, v2) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "
            "?, ?, ?, ?, ?, 1)",
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
              editText,
              edit.isEmpty ? null : edit.first["ts"],
              edit.isEmpty ? null : edit.first["content"],
              event.links.isEmpty ? null : event.links.join("\n"),
              event.links.length,
              jsonEncode(event.json),
              docId,
              _mentionIds(event),
              _mentionsMe(event, editText ?? event.searchText) ? 1 : 0,
              event.threadRoot,
              event.isReply ? 1 : 0,
            ]);
        if (db.updatedRows == 0) return false;
        _indexText(docId, editText ?? event.searchText);
        return true;
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
  ///
  /// Vommet: with [beforeEventId] too, the page after the message
  /// ([beforeTs], [beforeEventId]): messages sent in the same millisecond
  /// are ordered by id, so paging never skips or repeats one.
  List<IndexHit> list(String roomId,
      {Set<SharedContentKind> kinds = const {},
      bool linksOnly = false,
      int? beforeTs,
      String? beforeEventId,
      int limit = 100}) {
    final where = <String>["room_id = ?"];
    final args = <Object?>[roomId];
    if (kinds.isNotEmpty) {
      where.add("kind IN (${kinds.map((k) => k.index).join(",")})");
    }
    if (linksOnly) where.add("link_count > 0");
    if (beforeTs != null && beforeEventId != null) {
      where.add("(ts < ? OR (ts = ? AND event_id < ?))");
      args.addAll([beforeTs, beforeTs, beforeEventId]);
    } else if (beforeTs != null) {
      where.add("ts < ?");
      args.add(beforeTs);
    }
    args.add(limit);
    return _hits(db.select(
        "SELECT event_id, ts, kind, json, edit_content, links FROM events "
        "WHERE ${where.join(" AND ")} ORDER BY ts DESC, event_id DESC LIMIT ?",
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

  // ---- full text (v2) ---------------------------------------------------

  static final _cjk = RegExp(r'[぀-ヿ㐀-䶿一-鿿가-힯豈-﫿]');

  static bool hasCjk(String text) => _cjk.hasMatch(text);

  /// A full-text id from the message time: ts × 1000 plus the first free
  /// slot, so "rowid DESC" in the full-text tables is newest first.
  int _newDocId(int ts) {
    final base = ts.clamp(0, 9000000000000) * 1000;
    final taken = {
      for (final r in db.select(
          "SELECT doc_id FROM events WHERE doc_id >= ? AND doc_id < ?",
          [base, base + 1000]))
        r["doc_id"] as int
    };
    for (var k = 0; k < 1000; k++) {
      if (!taken.contains(base + k)) return base + k;
    }
    return base + 999;
  }

  static String? _mentionIds(IndexedEvent e) {
    final ids = [...e.mentionIds, if (e.mentionsRoom) "@room"];
    return ids.isEmpty ? null : "\n${ids.join("\n")}\n";
  }

  bool _mentionsMe(IndexedEvent e, String text) {
    final me = ownUserId;
    if (e.mentionsRoom) return true;
    if (me == null) return false;
    return e.mentionIds.contains(me) || text.contains(me.toLowerCase());
  }

  void _indexText(int docId, String text) {
    if (!_fts) return;
    _unindexText(docId);
    db.execute(
        "INSERT INTO events_fts(rowid, text) VALUES (?, ?)", [docId, text]);
    if (_tri && hasCjk(text)) {
      db.execute(
          "INSERT INTO events_tri(rowid, text) VALUES (?, ?)", [docId, text]);
    }
  }

  void _unindexText(int docId) {
    if (!_fts) return;
    db.execute("DELETE FROM events_fts WHERE rowid = ?", [docId]);
    if (_tri) db.execute("DELETE FROM events_tri WHERE rowid = ?", [docId]);
  }

  /// Rows the v1 → v2 upgrade still has to fill.
  int pendingMigration() =>
      db.select("SELECT count(*) AS n FROM events WHERE v2 = 0").first["n"]
          as int;

  /// Fills up to [limit] rows stored before v2 (or before this SQLite had
  /// full text): the new columns from the stored event, the reply-stripped
  /// search text and the full-text tables. Returns how many are left, so
  /// the caller can go on in small steps (resumable: each step commits).
  int migrateStep({int limit = 500}) {
    final rows = db.select(
        "SELECT event_id, ts, json, edit_text, doc_id FROM events "
        "WHERE v2 = 0 LIMIT ?",
        [limit]);
    if (rows.isEmpty) return 0;
    _transaction(() {
      for (final r in rows) {
        final eventId = r["event_id"] as String;
        final docId = r["doc_id"] as int? ?? _newDocId(r["ts"] as int);
        final json = jsonDecode(r["json"] as String);
        final extract =
            json is Map<String, dynamic> ? IndexExtract.of(json) : null;
        if (extract is IndexEventExtract) {
          final e = extract.event;
          final editText = r["edit_text"] as String?;
          db.execute(
              "UPDATE events SET search_text = ?, doc_id = ?, "
              "mention_ids = ?, mentions_me = ?, thread_root = ?, "
              "is_reply = ?, v2 = 1 WHERE event_id = ?",
              [
                e.searchText,
                docId,
                _mentionIds(e),
                _mentionsMe(e, editText ?? e.searchText) ? 1 : 0,
                e.threadRoot,
                e.isReply ? 1 : 0,
                eventId,
              ]);
          _indexText(docId, editText ?? e.searchText);
        } else {
          final text = db.select(
              "SELECT coalesce(edit_text, search_text) AS t FROM events "
              "WHERE event_id = ?",
              [eventId]).first["t"] as String;
          db.execute("UPDATE events SET doc_id = ?, v2 = 1 WHERE event_id = ?",
              [docId, eventId]);
          _indexText(docId, text);
        }
      }
    });
    return pendingMigration();
  }

  // ---- Deep Search: across rooms -----------------------------------------

  /// How many matches [searchAll] reads at most before ranking.
  static const candidateCap = 5000;

  static final _tokenSplit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Deep Search: messages matching [query] across the index (or its
  /// [IndexQuery.roomIds]). Reads the newest [cap] matches, then ranks them
  /// ([IndexRanking]: relevance × recency × boosts, or newest first) and
  /// returns the best [limit] with per-room counts of all candidates.
  ///
  /// Words: every word must occur (as a word prefix through the full-text
  /// index; Chinese, Japanese and Korean words as a substring through the
  /// trigram table). Rows the upgrade hasn't reached yet, and a SQLite
  /// without FTS5, are matched with instr().
  IndexSearchResult searchAll(IndexQuery query,
      {IndexRanking ranking = const IndexRanking(),
      int limit = 200,
      int cap = candidateCap}) {
    final roomIds = query.roomIds;
    if (roomIds != null && roomIds.isEmpty) return IndexSearchResult.empty;
    final (filters, filterArgs) = _filters(query);
    final words = [
      for (final w in query.words)
        if (w.trim().isNotEmpty) w.trim().toLowerCase()
    ];

    const columns = "e.event_id, e.room_id, e.ts, "
        "coalesce(e.edit_text, e.search_text) AS text";
    final candidates = <_Candidate>[];
    var capped = false;

    void collect(ResultSet rows, {required bool ranked}) {
      if (rows.length >= cap) capped = true;
      for (final r in rows) {
        candidates.add(_Candidate(
          eventId: r["event_id"] as String,
          roomId: r["room_id"] as String,
          ts: r["ts"] as int,
          text: r["text"] as String,
          rank: ranked ? -(r["rank"] as num).toDouble() : null,
        ));
      }
    }

    if (words.isEmpty) {
      collect(
          db.select(
              "SELECT $columns FROM events e "
              "${filters.isEmpty ? "" : "WHERE ${filters.join(" AND ")}"} "
              "ORDER BY e.ts DESC LIMIT ?",
              [...filterArgs, cap]),
          ranked: false);
    } else {
      final cjkWords = words.where(hasCjk).toList();
      final plainTokens = <String>[
        for (final w in words.where((w) => !hasCjk(w)))
          ...w.split(_tokenSplit).where((t) => t.isNotEmpty)
      ];
      final ftsTokens = plainTokens.where((t) => t.length >= 2).toList();
      final triWords = _tri
          ? cjkWords.where((w) => w.runes.length >= 3).toList()
          : const <String>[];
      // What neither full-text table can match: instr() on the text.
      final instrWords = [
        ...plainTokens.where((t) => t.length < 2),
        ...cjkWords.where((w) => !triWords.contains(w)),
      ];
      final instr = [for (final _ in instrWords) "instr($_text, ?) > 0"];

      if (_fts && (ftsTokens.isNotEmpty || triWords.isNotEmpty)) {
        final useFts = ftsTokens.isNotEmpty;
        final table = useFts ? "events_fts" : "events_tri";
        final where = <String>["$table MATCH ?", ...filters, ...instr];
        final args = <Object?>[
          useFts
              ? _matchExpression(ftsTokens)
              : _matchExpression(triWords, prefix: false),
          ...filterArgs,
          ...instrWords,
        ];
        if (useFts && triWords.isNotEmpty) {
          where.add("e.doc_id IN (SELECT rowid FROM events_tri "
              "WHERE events_tri MATCH ?)");
          args.add(_matchExpression(triWords, prefix: false));
        }
        args.add(cap);
        collect(
            db.select(
                "SELECT $columns, bm25($table) AS rank FROM $table "
                "JOIN events e ON e.doc_id = $table.rowid "
                "WHERE ${where.join(" AND ")} "
                "ORDER BY $table.rowid DESC LIMIT ?",
                args),
            ranked: true);
      }
      // Rows not in the full-text tables (yet): all words by instr().
      final scanAll = !_fts || (ftsTokens.isEmpty && triWords.isEmpty);
      final where = <String>[
        if (!scanAll) "e.v2 = 0",
        ...filters,
        for (final _ in words) "instr($_text, ?) > 0",
      ];
      collect(
          db.select(
              "SELECT $columns FROM events e WHERE ${where.join(" AND ")} "
              "ORDER BY e.ts DESC LIMIT ?",
              [...filterArgs, ...words, cap]),
          ranked: false);
    }

    final seen = <String>{};
    candidates.retainWhere((c) => seen.add(c.eventId));
    candidates.sort((a, b) => b.ts.compareTo(a.ts));
    if (candidates.length > cap) {
      candidates.removeRange(cap, candidates.length);
      capped = true;
    }

    final roomCounts = <String, int>{};
    for (final c in candidates) {
      roomCounts[c.roomId] = (roomCounts[c.roomId] ?? 0) + 1;
    }

    final newest = ranking.newestFirst || words.isEmpty;
    if (!newest) {
      final ranks = [
        for (final c in candidates)
          if (c.rank != null) c.rank!
      ];
      // instr() rows have no bm25: score them as an average match.
      final fallback =
          ranks.isEmpty ? 1.0 : ranks.reduce((a, b) => a + b) / ranks.length;
      final now = ranking.now ?? DateTime.now().millisecondsSinceEpoch;
      final phrase = words.length > 1 ? words.join(" ") : null;
      for (final c in candidates) {
        c.score = rankScore(
          relevance: c.rank ?? fallback,
          ageMs: now - c.ts,
          exactPhrase: phrase != null && c.text.contains(phrase),
          dm: ranking.dmRoomIds.contains(c.roomId),
          favorite: ranking.favoriteRoomIds.contains(c.roomId),
          postedIn: ranking.postedInRoomIds.contains(c.roomId),
        );
      }
      candidates.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : b.ts.compareTo(a.ts);
      });
    }

    final top = candidates.take(limit).toList();
    return IndexSearchResult(
      hits: _hitsFor(top),
      roomCounts: roomCounts,
      candidates: candidates.length,
      capped: capped,
    );
  }

  static const _text = "coalesce(e.edit_text, e.search_text)";

  /// "Best match": relevance (bm25, higher is better) × recency (halves
  /// every 30 days, never below [IndexRanking.recencyFloor]) × boosts.
  static double rankScore({
    required double relevance,
    required int ageMs,
    bool exactPhrase = false,
    bool dm = false,
    bool favorite = false,
    bool postedIn = false,
  }) {
    final ageDays = (ageMs < 0 ? 0 : ageMs) / Duration.millisecondsPerDay;
    final decay = math.pow(0.5, ageDays / IndexRanking.halfLifeDays);
    final recency = IndexRanking.recencyFloor +
        (1 - IndexRanking.recencyFloor) * decay.toDouble();
    var score = (relevance <= 0 ? 0.01 : relevance) * recency;
    if (exactPhrase) score *= IndexRanking.exactPhraseBoost;
    if (dm) score *= IndexRanking.dmBoost;
    if (favorite) score *= IndexRanking.favoriteBoost;
    if (postedIn) score *= IndexRanking.postedInBoost;
    return score;
  }

  /// An FTS5 query: every term, each a quoted prefix ("tea"*), or a quoted
  /// substring for the trigram table.
  static String _matchExpression(List<String> terms, {bool prefix = true}) =>
      terms
          .map((t) => '"${t.replaceAll('"', '""')}"${prefix ? "*" : ""}')
          .join(" AND ");

  (List<String>, List<Object?>) _filters(IndexQuery q) {
    final where = <String>[];
    final args = <Object?>[];
    void anyOf(String column, Iterable<Object?> values) {
      final list = values.toList();
      if (list.isEmpty) return;
      where.add("$column IN (${List.filled(list.length, "?").join(",")})");
      args.addAll(list);
    }

    final roomIds = q.roomIds;
    if (roomIds != null) anyOf("e.room_id", roomIds);
    anyOf("e.sender", [...q.senders, if (q.senderId != null) q.senderId]);
    if (q.excludeSenders.isNotEmpty) {
      where.add("e.sender NOT IN "
          "(${List.filled(q.excludeSenders.length, "?").join(",")})");
      args.addAll(q.excludeSenders);
    }
    final kinds = {...q.kinds};
    if (q.requireImage) kinds.addAll(_imageKinds);
    if (q.requireVideo) kinds.add(SharedContentKind.video);
    anyOf("e.kind", kinds.map((k) => k.index));
    if (q.requireAttachment) {
      where.add("e.kind NOT IN (${SharedContentKind.text.index}, "
          "${SharedContentKind.sticker.index})");
    }
    if (q.requireLink) where.add("e.link_count > 0");
    if (q.type != null) {
      where.add("(e.type = ? OR e.msgtype = ?)");
      args.addAll([q.type, q.type]);
    }
    if (q.beforeTs != null) {
      where.add("e.ts < ?");
      args.add(q.beforeTs);
    }
    if (q.afterTs != null) {
      where.add("e.ts > ?");
      args.add(q.afterTs);
    }
    if (q.mentionsMe) {
      final names = [
        for (final n in q.myNames)
          if (n.trim().length >= 2) n.trim().toLowerCase()
      ];
      final any = [
        "e.mentions_me = 1",
        if (ownUserId != null) "instr(e.mention_ids, ?) > 0",
        for (final _ in names) "instr($_text, ?) > 0",
      ];
      where.add("(${any.join(" OR ")})");
      if (ownUserId != null) args.add("\n$ownUserId\n");
      args.addAll(names);
    }
    return (where, args);
  }

  List<IndexHit> _hitsFor(List<_Candidate> ranked) {
    if (ranked.isEmpty) return const [];
    final rows = <String, Row>{};
    for (var i = 0; i < ranked.length; i += 500) {
      final ids = ranked.skip(i).take(500).map((c) => c.eventId).toList();
      for (final r in db.select(
          "SELECT event_id, room_id, sender, ts, kind, json, edit_content, "
          "links, thread_root, is_reply FROM events WHERE event_id IN "
          "(${List.filled(ids.length, "?").join(",")})",
          ids)) {
        rows[r["event_id"] as String] = r;
      }
    }
    return [
      for (final c in ranked)
        if (rows[c.eventId] case final r?)
          IndexHit(
            eventId: c.eventId,
            ts: r["ts"] as int,
            kind: SharedContentKind.values[r["kind"] as int],
            json: _withEdit(
                jsonDecode(r["json"] as String), r["edit_content"] as String?),
            links: (r["links"] as String?)?.split("\n") ?? const [],
            roomId: r["room_id"] as String,
            senderId: r["sender"] as String,
            score: c.score,
            threadRoot: r["thread_root"] as String?,
            isReply: r["is_reply"] == 1,
          ),
    ];
  }

  /// Deep Search's coverage line for [roomIds] (the rooms the index should
  /// hold).
  IndexCoverageTotals coverageTotals(List<String> roomIds) {
    final wanted = roomIds.toSet();
    final pending = {
      for (final r in db.select("SELECT DISTINCT room_id FROM segments"))
        r["room_id"] as String
    };
    var complete = 0, started = 0, limited = 0, undecrypted = 0;
    for (final r in db.select("SELECT room_id, complete, saw_create, "
        "oldest_ts, head_ts FROM rooms")) {
      final id = r["room_id"] as String;
      if (!wanted.contains(id)) continue;
      if (r["complete"] == 1 && !pending.contains(id)) {
        complete++;
        if (r["saw_create"] == 0) limited++;
      } else if (r["oldest_ts"] != null || r["head_ts"] != null) {
        started++;
      }
    }
    for (final r in db.select(
        "SELECT room_id, count(*) AS n FROM undecrypted GROUP BY room_id")) {
      if (wanted.contains(r["room_id"])) undecrypted += r["n"] as int;
    }
    final migrating =
        db.select("SELECT 1 FROM events WHERE v2 = 0 LIMIT 1").isNotEmpty;
    return IndexCoverageTotals(
      rooms: wanted.length,
      complete: complete,
      started: started,
      undecrypted: undecrypted,
      historyLimited: limited,
      migrating: migrating,
    );
  }

  /// Deep Search's "rooms I've posted in" boost: the rooms where
  /// [senderId] (the account's own user) has a message in the index.
  List<String> roomsPostedIn(String senderId) => [
        for (final r in db.select(
            "SELECT DISTINCT room_id FROM events WHERE sender = ?", [senderId]))
          r["room_id"] as String
      ];

  // ---- forgetting --------------------------------------------------------

  void deleteRoom(String roomId) {
    _transaction(() {
      if (_fts) {
        for (final table in [
          "events_fts",
          if (_tri) "events_tri",
        ]) {
          db.execute(
              "DELETE FROM $table WHERE rowid IN (SELECT doc_id FROM events "
              "WHERE room_id = ? AND doc_id IS NOT NULL)",
              [roomId]);
        }
      }
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
      for (final table in [
        "events",
        "edits",
        "redacted",
        "undecrypted",
        "rooms",
        "segments",
        if (_fts) "events_fts",
        if (_tri) "events_tri",
      ]) {
        db.execute("DELETE FROM $table");
      }
    });
    db.execute("VACUUM");
  }
}

class _Candidate {
  _Candidate({
    required this.eventId,
    required this.roomId,
    required this.ts,
    required this.text,
    this.rank,
  });
  final String eventId;
  final String roomId;
  final int ts;
  final String text;

  /// bm25, negated (higher = better); null for instr() matches.
  final double? rank;
  double score = 0;
}
