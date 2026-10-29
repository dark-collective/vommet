// Vommet (Deep Search, stage 2): one result list from three sources: the
// local index (encrypted rooms and DMs), the loaded timelines (messages on
// the device that the index doesn't hold yet) and the server's /search
// (unencrypted group rooms). Deduped by (room, event): the index wins, then
// the timeline, then the server. Lists merge by rank position, so a source
// with fewer hits doesn't sink below one with many; "All accounts" merges
// each account's list the same way and every result carries its account
// (the account dot). The server rows form their own section. Also the
// per-room counts and the "Most matches" strip.
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_query.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_server.dart';

enum DeepSearchSource { indexed, timeline, server }

/// One result row's data.
class DeepSearchResult {
  const DeepSearchResult({
    required this.accountId,
    required this.roomId,
    required this.eventId,
    required this.senderId,
    required this.ts,
    required this.source,
    this.content = const {},
    this.kind = SharedContentKind.text,
    this.links = const [],
    this.score = 0,
    this.threadRoot,
    this.isReply = false,
    this.edited = false,
  });

  factory DeepSearchResult.fromIndex(String accountId, IndexHit hit) {
    final content = hit.json["content"];
    return DeepSearchResult(
      accountId: accountId,
      roomId: hit.roomId,
      eventId: hit.eventId,
      senderId: hit.senderId,
      ts: hit.ts,
      source: DeepSearchSource.indexed,
      content: content is Map<String, dynamic> ? content : const {},
      kind: hit.kind,
      links: hit.links,
      score: hit.score,
      threadRoot: hit.threadRoot,
      isReply: hit.isReply,
    );
  }

  factory DeepSearchResult.fromServer(
          String accountId, DeepSearchServerHit hit) =>
      DeepSearchResult(
        accountId: accountId,
        roomId: hit.roomId,
        eventId: hit.eventId,
        senderId: hit.senderId,
        ts: hit.ts,
        source: DeepSearchSource.server,
        content: hit.content,
        score: hit.rank ?? 0,
        edited: hit.edited,
      );

  /// The account it was found by (the dot in All accounts).
  final String accountId;
  final String roomId;
  final String eventId;
  final String senderId;

  /// ms since epoch.
  final int ts;
  final DeepSearchSource source;

  /// The event content (the latest edit's, when edited).
  final Map<String, Object?> content;
  final SharedContentKind kind;
  final List<String> links;
  final double score;
  final String? threadRoot;
  final bool isReply;
  final bool edited;

  String get body {
    final b = content["body"];
    return b is String ? b : "";
  }

  String? get fileName {
    final f = content["filename"];
    return f is String ? f : null;
  }

  /// The dedupe key.
  (String, String) get key => (roomId, eventId);
}

/// Whether an index (or timeline) hit holds [query]'s quoted phrases (the
/// index only requires the words).
bool deepSearchAcceptsPhrases<S>(
        DeepSearchQuery<S> query, DeepSearchResult result) =>
    query.matchesPhrases("${result.body}\n${result.fileName ?? ""}");

/// Merges ranked [lists] by rank position: the i-th of a list of n sits
/// at (i + 1) / (n + 1), so lists interleave evenly; on a tie the earlier
/// list wins. Duplicates (same room and event) keep the earliest list's
/// copy, at its position. [newestFirst] sorts the result by time instead.
List<DeepSearchResult> deepSearchMerge(List<List<DeepSearchResult>> lists,
    {bool newestFirst = false}) {
  final placed = <(double, int, int, DeepSearchResult)>[];
  for (var l = 0; l < lists.length; l++) {
    final list = lists[l];
    for (var i = 0; i < list.length; i++) {
      placed.add(((i + 1) / (list.length + 1), l, i, list[i]));
    }
  }
  placed.sort((a, b) {
    final byPos = a.$1.compareTo(b.$1);
    if (byPos != 0) return byPos;
    final byList = a.$2.compareTo(b.$2);
    if (byList != 0) return byList;
    return a.$3.compareTo(b.$3);
  });
  // A duplicate keeps the earliest list's copy (the index over the
  // timeline over the server), at that copy's own position.
  final owner = <(String, String), int>{};
  for (var l = lists.length - 1; l >= 0; l--) {
    for (final r in lists[l]) {
      owner[r.key] = l;
    }
  }
  final seen = <(String, String)>{};
  final out = <DeepSearchResult>[];
  for (final p in placed) {
    if (owner[p.$4.key] != p.$2) continue;
    if (seen.add(p.$4.key)) out.add(p.$4);
  }
  if (newestFirst) out.sort((a, b) => b.ts.compareTo(a.ts));
  return out;
}

/// One account's sources.
class DeepSearchAccountHits {
  const DeepSearchAccountHits({
    required this.accountId,
    this.index,
    this.timeline = const [],
    this.server = const [],
  });

  final String accountId;
  final IndexSearchResult? index;

  /// Loaded-timeline matches, best first.
  final List<DeepSearchResult> timeline;
  final List<DeepSearchServerHit> server;
}

/// A room in the "Most matches" strip.
class DeepSearchRoomCount {
  const DeepSearchRoomCount(this.accountId, this.roomId, this.count);
  final String accountId;
  final String roomId;
  final int count;
}

/// The merged results of a query: two sections (review fix 2), the local
/// one ("On this device": index + loaded timelines, best match or newest)
/// and the server one ("Unencrypted rooms · searched on your homeserver",
/// newest first, none of the local rows repeated). Local rows paint first;
/// the server section fills in below them, so nothing reshuffles (review
/// fix 3).
class DeepSearchResults {
  const DeepSearchResults({
    this.local = const [],
    this.server = const [],
    this.roomCounts = const {},
    this.capped = false,
  });

  static const empty = DeepSearchResults();

  final List<DeepSearchResult> local;
  final List<DeepSearchResult> server;

  /// Matches per (account, room): the index's counts of all its candidates
  /// plus the timeline and server rows it doesn't hold.
  final Map<(String, String), int> roomCounts;

  /// The index stopped counting at its cap ("1,000+").
  final bool capped;

  bool get isEmpty => local.isEmpty && server.isEmpty;

  int get total => roomCounts.values.fold(0, (a, b) => a + b);

  /// The "Most matches" strip: the top rooms by count (ties: room id),
  /// shown only when the hits span more than one room.
  List<DeepSearchRoomCount> mostMatches({int limit = 5}) {
    if (roomCounts.length < 2) return const [];
    final rooms = [
      for (final e in roomCounts.entries)
        DeepSearchRoomCount(e.key.$1, e.key.$2, e.value)
    ]..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return a.roomId.compareTo(b.roomId);
      });
    return rooms.take(limit).toList();
  }

  /// "+5 more" after the strip.
  int moreRooms({int limit = 5}) {
    if (roomCounts.length < 2 || roomCounts.length <= limit) return 0;
    return roomCounts.length - limit;
  }

  /// Merges each account's sources, in the account filter's order (one
  /// account, or every account for All accounts: the first account's copy
  /// of a shared room's event wins).
  static DeepSearchResults merge<S>(
      DeepSearchQuery<S> query, List<DeepSearchAccountHits> accounts,
      {bool newestFirst = false}) {
    final localLists = <List<DeepSearchResult>>[];
    final serverLists = <List<DeepSearchResult>>[];
    final counts = <(String, String), int>{};
    var capped = false;
    for (final a in accounts) {
      final index = [
        for (final h in a.index?.hits ?? const <IndexHit>[])
          DeepSearchResult.fromIndex(a.accountId, h)
      ].where((r) => deepSearchAcceptsPhrases(query, r)).toList();
      final timeline =
          a.timeline.where((r) => deepSearchAcceptsPhrases(query, r)).toList();
      final local =
          deepSearchMerge([index, timeline], newestFirst: newestFirst);
      localLists.add(local);
      serverLists.add([
        for (final h in a.server) DeepSearchResult.fromServer(a.accountId, h)
      ]);

      if (a.index?.capped == true) capped = true;
      (a.index?.roomCounts ?? const <String, int>{}).forEach((room, n) {
        counts[(a.accountId, room)] = n;
      });
      for (final r in local) {
        if (r.source == DeepSearchSource.indexed) continue;
        final k = (a.accountId, r.roomId);
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    final local = localLists.length == 1
        ? localLists.first
        : deepSearchMerge(localLists, newestFirst: newestFirst);
    final shown = {for (final r in local) r.key};
    final server = <DeepSearchResult>[];
    for (final r in deepSearchMerge(serverLists, newestFirst: true)) {
      if (!shown.add(r.key)) continue;
      server.add(r);
      final k = (r.accountId, r.roomId);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return DeepSearchResults(
        local: local, server: server, roomCounts: counts, capped: capped);
  }
}
