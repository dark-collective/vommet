// Vommet (Deep Search, stage 2): the server half. Unencrypted group rooms'
// history comes from ONE account-wide /search (Decision 2): fired after a
// 600 ms pause in typing, or at once on Enter; a stale response (the query
// moved on) is dropped by a generation counter; pages are cached per
// normalized query and "Load more from the server" follows next_batch.
// The response is post-processed here, in pure Dart on event JSON: edits
// map to their latest text and the edit events are dropped, redacted
// events and rooms the index covers fully are dropped, ignored users are
// filtered and the query's chips the server can't filter (has:, dates,
// mentions:me, "phrases") are applied. The SDK call itself lives in
// deep_search_server_matrix.dart.
import 'dart:async';

import 'package:commet/client/client.dart' show ClientConnectionStatus;
import 'package:commet/debug/log.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_query.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One raw /search result: the event's JSON and the server's rank.
class DeepSearchServerEvent {
  const DeepSearchServerEvent(this.json, {this.rank});
  final Map<String, Object?> json;
  final double? rank;
}

/// One raw page of /search.
class DeepSearchServerPage {
  const DeepSearchServerPage(this.events, {this.nextBatch, this.count});
  final List<DeepSearchServerEvent> events;
  final String? nextBatch;

  /// The server's estimate of all matches, if it gave one.
  final int? count;
}

/// One server hit after post-processing.
class DeepSearchServerHit {
  const DeepSearchServerHit({
    required this.eventId,
    required this.roomId,
    required this.senderId,
    required this.ts,
    required this.content,
    this.rank,
    this.edited = false,
  });

  final String eventId;
  final String roomId;
  final String senderId;

  /// ms since epoch.
  final int ts;

  /// The content with the latest edit (m.new_content) applied.
  final Map<String, Object?> content;
  final double? rank;
  final bool edited;

  String get body => _str(content["body"]) ?? "";
  String? get msgtype => _str(content["msgtype"]);
}

String? _str(Object? v) => v is String ? v : null;

int _ts(Map<String, Object?> json) {
  final ts = json["origin_server_ts"];
  return ts is num ? ts.toInt() : 0;
}

Map<String, Object?>? _map(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) {
    final out = <String, Object?>{};
    v.forEach((k, value) {
      if (k is String) out[k] = value;
    });
    return out;
  }
  return null;
}

/// Context for [deepSearchPostProcess].
class DeepSearchServerContext {
  const DeepSearchServerContext({
    this.coveredRoomIds = const {},
    this.ignoredUsers = const {},
    this.redactedIds = const {},
    this.myUserId,
    this.myNames = const [],
  });

  /// Rooms the index covers fully (their local hits win).
  final Set<String> coveredRoomIds;
  final Set<String> ignoredUsers;

  /// Events known to be redacted (e.g. from the loaded timelines).
  final Set<String> redactedIds;
  final String? myUserId;
  final List<String> myNames;
}

const _messageTypes = {"m.room.message", "m.sticker"};

bool _isRedacted(Map<String, Object?> json, Map<String, Object?> content) {
  final unsigned = _map(json["unsigned"]);
  if (unsigned != null && unsigned["redacted_because"] != null) return true;
  return content.isEmpty;
}

/// The id [json] edits (m.replace), or null.
String? _editTarget(Map<String, Object?> content) {
  final rel = _map(content["m.relates_to"]);
  if (rel == null || rel["rel_type"] != "m.replace") return null;
  return _str(rel["event_id"]);
}

/// The server-bundled latest edit's new content, if any.
Map<String, Object?>? _bundledEdit(Map<String, Object?> json) {
  final relations = _map(_map(json["unsigned"])?["m.relations"]);
  final replace = _map(relations?["m.replace"]);
  if (replace == null) return null;
  final content = _map(replace["content"]);
  return _map(content?["m.new_content"]);
}

bool _mentions(DeepSearchServerHit hit, DeepSearchServerContext ctx) {
  final me = ctx.myUserId;
  final mentions = _map(hit.content["m.mentions"]);
  if (mentions != null) {
    if (mentions["room"] == true) return true;
    final ids = mentions["user_ids"];
    if (me != null && ids is List && ids.contains(me)) return true;
  }
  final body = searchFold(hit.body);
  if (me != null && body.contains(me.toLowerCase())) return true;
  for (final n in ctx.myNames) {
    final name = searchFold(n.trim());
    if (name.length >= 2 && body.contains(name)) return true;
  }
  return false;
}

/// Whether [hit] passes [query]'s chips and phrases.
bool deepSearchServerAccepts<S>(DeepSearchQuery<S> query,
    DeepSearchServerHit hit, DeepSearchServerContext ctx) {
  final from = query.fromUserIds;
  if (from.isNotEmpty && !from.contains(hit.senderId)) return false;
  final before = query.beforeTs;
  if (before != null && hit.ts >= before) return false;
  final after = query.afterTs;
  if (after != null && hit.ts <= after) return false;
  // has: chips of kinds are any-of (like the index), a link is required.
  if (!deepSearchHasMatches(query.has, hit.content, body: hit.body)) {
    return false;
  }
  if (query.mentionsMe && !_mentions(hit, ctx)) return false;
  final fileName = _str(hit.content["filename"]) ?? "";
  if (!query.matchesPhrases("${hit.body}\n$fileName")) return false;
  return true;
}

/// The page's hits, newest first: edits applied (the edit events dropped;
/// an edit whose original isn't in the page stands in for it), redactions
/// (and redacted events) dropped, covered rooms and ignored users dropped,
/// [query]'s chips applied. [seen] holds ids of earlier pages (no repeats).
List<DeepSearchServerHit> deepSearchPostProcess<S>(
    DeepSearchQuery<S> query, List<DeepSearchServerEvent> events,
    {DeepSearchServerContext context = const DeepSearchServerContext(),
    Set<String> seen = const {}}) {
  final redacted = {...context.redactedIds};
  // Newest edit per original: (ts, new content).
  final edits = <String, (int, Map<String, Object?>, DeepSearchServerEvent)>{};
  final originals = <DeepSearchServerEvent>[];

  for (final e in events) {
    final json = e.json;
    final type = _str(json["type"]);
    final content = _map(json["content"]) ?? const <String, Object?>{};
    if (type == "m.room.redaction") {
      final target = _str(json["redacts"]) ?? _str(content["redacts"]);
      if (target != null) redacted.add(target);
      continue;
    }
    if (type == null || !_messageTypes.contains(type)) continue;
    final target = _editTarget(content);
    if (target != null) {
      final newContent = _map(content["m.new_content"]);
      if (newContent == null) continue;
      final ts = _ts(json);
      final old = edits[target];
      if (old == null || old.$1 <= ts) edits[target] = (ts, newContent, e);
      continue;
    }
    originals.add(e);
  }

  final out = <DeepSearchServerHit>[];
  final ids = <String>{...seen};
  final words = query.words;

  void add(DeepSearchServerEvent e, String eventId, int ts,
      Map<String, Object?> content, bool edited) {
    final json = e.json;
    final roomId = _str(json["room_id"]) ?? "";
    final sender = _str(json["sender"]) ?? "";
    if (eventId.isEmpty || roomId.isEmpty) return;
    if (ids.contains(eventId) || redacted.contains(eventId)) return;
    if (context.coveredRoomIds.contains(roomId)) return;
    if (context.ignoredUsers.contains(sender)) return;
    final hit = DeepSearchServerHit(
        eventId: eventId,
        roomId: roomId,
        senderId: sender,
        ts: ts,
        content: content,
        rank: e.rank,
        edited: edited);
    // The server matched the old text: an edited hit must still hold the
    // words in its latest text.
    if (edited) {
      final text = searchFold("${hit.body}\n${_str(content["filename"])}");
      if (!words.every(text.contains)) return;
    }
    if (!deepSearchServerAccepts(query, hit, context)) return;
    ids.add(eventId);
    out.add(hit);
  }

  for (final e in originals) {
    final json = e.json;
    final id = _str(json["event_id"]) ?? "";
    final content = _map(json["content"]) ?? const <String, Object?>{};
    if (_isRedacted(json, content)) continue;
    final ts = _ts(json);
    final edit = edits.remove(id);
    final bundled = _bundledEdit(json);
    final latest = edit?.$2 ?? bundled;
    add(e, id, ts, latest ?? content, latest != null);
  }
  // Edits whose original the page lacks: the edit stands in for it, under
  // the original's id (the edit's own ts: the original's is unknown).
  edits.forEach((target, edit) {
    add(edit.$3, target, edit.$1, edit.$2, true);
  });

  out.sort((a, b) => b.ts.compareTo(a.ts));
  return out;
}

/// The server search's state for the current query.
class DeepSearchServerState {
  const DeepSearchServerState({
    this.key,
    this.hits = const [],
    this.nextBatch,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.skipped = false,
    this.count,
  });

  static const idle = DeepSearchServerState(skipped: true);

  /// The normalized query these hits are for.
  final String? key;
  final List<DeepSearchServerHit> hits;

  /// Set: "Load more from the server" can show.
  final String? nextBatch;
  final bool loading;
  final bool loadingMore;

  /// The last request failed (offline, server error): the coverage line
  /// says server results are missing.
  final Object? error;

  /// No server search for this query (no words, DMs only, nothing the
  /// index doesn't cover, or no query).
  final bool skipped;
  final int? count;

  bool get canLoadMore => nextBatch != null && !loadingMore && error == null;

  DeepSearchServerState copyWith({
    List<DeepSearchServerHit>? hits,
    String? nextBatch,
    bool clearNextBatch = false,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) =>
      DeepSearchServerState(
        key: key,
        hits: hits ?? this.hits,
        nextBatch: clearNextBatch ? null : (nextBatch ?? this.nextBatch),
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
        skipped: skipped,
        count: count,
      );
}

/// Whether a failed /search is the network's fault (no connection, DNS,
/// TLS, a timeout), not the server's answer. dart:io's exceptions are
/// matched by name, so this also builds for the web.
bool deepSearchIsNetworkError(Object? error) {
  if (error == null) return false;
  if (error is TimeoutException || error is http.ClientException) return true;
  final type = error.runtimeType.toString();
  return const {
    "SocketException",
    "HandshakeException",
    "TlsException",
    "HttpException",
    "WebSocketException",
  }.contains(type);
}

/// Whether one account's server results are missing because it's offline
/// (Mockup 5's Offline line): its /search failed for the network, or its
/// sync connection is down and the search didn't come back. A search that
/// went through while sync blipped still counts as online.
bool deepSearchServerOffline(
    DeepSearchServerState state, ClientConnectionStatus? connection) {
  if (state.skipped) return false;
  if (deepSearchIsNetworkError(state.error)) return true;
  return connection == ClientConnectionStatus.disconnected &&
      (state.loading || state.error != null);
}

/// Fetches one /search page for [filter] ([nextBatch] for more).
typedef DeepSearchServerFetch = Future<DeepSearchServerPage> Function(
    DeepSearchServerFilter filter, String? nextBatch);

/// Runs the server search of the current query: debounced, stale
/// responses dropped, pages cached per normalized query.
class DeepSearchServerController<S> {
  DeepSearchServerController({
    required this.fetch,
    this.debounce = const Duration(milliseconds: 600),
    this.cacheSize = 20,
  });

  final DeepSearchServerFetch fetch;
  final Duration debounce;
  final int cacheSize;

  final ValueNotifier<DeepSearchServerState> state =
      ValueNotifier(DeepSearchServerState.idle);

  final Map<String, DeepSearchServerState> _cache = {};
  int _generation = 0;
  Timer? _timer;
  _Pending<S>? _pending;

  /// The generation of the latest request (tests).
  int get generation => _generation;

  /// The query changed: search after [debounce] (cached results show at
  /// once). A null [filter] means no server search for it.
  void update(DeepSearchQuery<S> query, DeepSearchServerFilter? filter,
      DeepSearchServerContext context) {
    _schedule(query, filter, context, immediate: false);
  }

  /// Enter: search now.
  void submit(DeepSearchQuery<S> query, DeepSearchServerFilter? filter,
      DeepSearchServerContext context) {
    _schedule(query, filter, context, immediate: true);
  }

  void _schedule(DeepSearchQuery<S> query, DeepSearchServerFilter? filter,
      DeepSearchServerContext context,
      {required bool immediate}) {
    _timer?.cancel();
    _timer = null;
    _generation++;
    final key = query.normalized;
    if (filter == null || query.isEmpty) {
      _pending = null;
      state.value = DeepSearchServerState(key: key, skipped: true);
      return;
    }
    final pending = _Pending(query, filter, context, _generation);
    _pending = pending;
    final cached = _cache[key];
    if (cached != null && cached.error == null) {
      state.value = cached;
      return;
    }
    state.value = DeepSearchServerState(key: key, loading: true);
    if (immediate) {
      unawaited(_run(pending));
    } else {
      _timer = Timer(debounce, () => unawaited(_run(pending)));
    }
  }

  Future<void> _run(_Pending<S> p) async {
    final key = p.query.normalized;
    try {
      final page = await fetch(p.filter, null);
      if (p.generation != _generation) return; // stale
      final hits =
          deepSearchPostProcess(p.query, page.events, context: p.context);
      final next = DeepSearchServerState(
          key: key,
          hits: hits,
          nextBatch: page.nextBatch,
          count: page.count,
          skipped: false);
      _remember(key, next);
      state.value = next;
    } catch (e, s) {
      if (p.generation != _generation) return;
      Log.onError(e, s, content: "Deep Search: server search failed");
      state.value = DeepSearchServerState(key: key, error: e);
    }
  }

  /// "Load more from the server": the next page, appended.
  Future<void> loadMore() async {
    final p = _pending;
    final current = state.value;
    final batch = current.nextBatch;
    if (p == null || batch == null || current.loadingMore) return;
    if (current.key != p.query.normalized) return;
    final generation = _generation;
    state.value = current.copyWith(loadingMore: true);
    try {
      final page = await fetch(p.filter, batch);
      if (generation != _generation) return;
      final more = deepSearchPostProcess(p.query, page.events,
          context: p.context, seen: {for (final h in current.hits) h.eventId});
      final next = DeepSearchServerState(
        key: current.key,
        hits: [...current.hits, ...more],
        nextBatch: page.nextBatch,
        count: current.count,
        skipped: false,
      );
      if (current.key != null) _remember(current.key ?? "", next);
      state.value = next;
    } catch (e, s) {
      if (generation != _generation) return;
      Log.onError(e, s, content: "Deep Search: loading more failed");
      state.value = current.copyWith(loadingMore: false, error: e);
    }
  }

  void _remember(String key, DeepSearchServerState value) {
    _cache.remove(key);
    _cache[key] = value;
    while (_cache.length > cacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Drops cached pages (e.g. after a redaction or the account changed).
  void clearCache() => _cache.clear();

  void dispose() {
    _timer?.cancel();
    _generation++;
    state.dispose();
  }
}

class _Pending<S> {
  _Pending(this.query, this.filter, this.context, this.generation);
  final DeepSearchQuery<S> query;
  final DeepSearchServerFilter filter;
  final DeepSearchServerContext context;
  final int generation;
}
