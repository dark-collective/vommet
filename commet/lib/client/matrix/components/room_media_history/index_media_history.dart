// Vommet: the Media and Files tabs of an ENCRYPTED room, paged from the
// encrypted search index (Vommet issues 602 and 611) instead of the room
// timeline: the index already holds the room's decrypted messages with a
// file, by kind and time, so a screenful is one local query. Where the
// index hasn't reached yet, it scans the next 100 messages itself
// (indexOlder, shared with the background indexer, so each stretch of
// history is fetched once) and the listing continues.
import 'package:commet/client/components/room_media_history/room_media_history_component.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';

/// What [IndexMediaHistory] needs from the index
/// ([MatrixEncryptedSearchIndexComponent]; a fake in tests).
abstract class MediaHistoryIndex {
  Future<RoomCoverage> prepare(String roomId);

  Future<List<IndexHit>> list(String roomId,
      {Set<SharedContentKind> kinds,
      bool linksOnly,
      int? beforeTs,
      String? beforeEventId,
      int limit});

  Future<IndexStepResult> indexOlder(String roomId);
}

/// The index stopped getting further (a room it can't page, a backend that
/// failed to open): the feed pages the timeline instead.
class IndexMediaHistoryStalled implements Exception {
  const IndexMediaHistoryStalled(this.roomId);
  final String roomId;

  @override
  String toString() => "The search index stopped scanning $roomId";
}

/// Pages of [roomId]'s messages with a file (newest first) from [index].
/// Page tokens are `idx:<ts>:<event id>` of the last message given out
/// (`idx:` = from the newest).
class IndexMediaHistory {
  IndexMediaHistory(this.index, this.roomId, {required this.convert});

  final MediaHistoryIndex index;
  final String roomId;

  /// The decrypted event as the timeline shows it (null to leave it out).
  final TimelineEvent? Function(Map<String, dynamic> json) convert;

  /// Everything the Media and Files tabs list.
  static const Set<SharedContentKind> fileKinds = {
    SharedContentKind.image,
    SharedContentKind.video,
    SharedContentKind.gif,
    SharedContentKind.file,
    SharedContentKind.voice,
    SharedContentKind.audio,
  };

  /// Index pages (100 messages each) scanned at most per [loadPage], so a
  /// page comes back soon even in a stretch without files.
  static const int maxScansPerPage = 3;

  static const String _prefix = "idx:";

  static String tokenOf(IndexHit hit) => "$_prefix${hit.ts}:${hit.eventId}";

  /// The (ts, event id) a token continues after; null from the newest.
  static (int, String)? parse(String? token) {
    if (token == null || !token.startsWith(_prefix)) return null;
    final rest = token.substring(_prefix.length);
    final colon = rest.indexOf(":");
    if (colon <= 0) return null;
    final ts = int.tryParse(rest.substring(0, colon));
    if (ts == null) return null;
    return (ts, rest.substring(colon + 1));
  }

  /// Stretches still to scan that are NOT the backfill: messages that
  /// arrived while the app was closed, or that a limited sync skipped.
  /// They are newer than what the backfill reached, so listing past them
  /// would leave their files out.
  static int gapsOf(RoomCoverage coverage) => !coverage.known
      ? 0
      : coverage.pendingSegments - (coverage.complete ? 0 : 1);

  static bool _moved(RoomCoverage before, IndexStepResult step) =>
      step.added > 0 ||
      step.coverage.complete != before.complete ||
      step.coverage.oldestTs != before.oldestTs ||
      step.coverage.headTs != before.headTs ||
      step.coverage.pendingSegments != before.pendingSegments;

  Future<RoomMediaPage> loadPage(String? from, {int limit = 50}) async {
    var coverage = await index.prepare(roomId);
    var cursor = parse(from);
    var scans = 0;

    Future<void> scan() async {
      final step = await index.indexOlder(roomId);
      scans++;
      if (!_moved(coverage, step)) throw IndexMediaHistoryStalled(roomId);
      coverage = step.coverage;
    }

    // Close the gaps first. One closed after paging had begun added files
    // newer than [cursor]: start over from the newest (the feed already
    // has the rest by id, and listing is local).
    var filledGap = false;
    while (gapsOf(coverage) > 0 && scans < maxScansPerPage) {
      await scan();
      filledGap = true;
    }
    if (filledGap && cursor != null) cursor = null;
    if (gapsOf(coverage) > 0) {
      return RoomMediaPage(const [], next: from ?? _prefix);
    }

    Future<List<IndexHit>> list() => index.list(roomId,
        kinds: fileKinds,
        beforeTs: cursor?.$1,
        beforeEventId: cursor?.$2,
        limit: limit);

    var hits = await list();
    while (
        hits.length < limit && !coverage.upToDate && scans < maxScansPerPage) {
      final gapsBefore = gapsOf(coverage);
      await scan();
      // A gap that opened meanwhile (a limited sync) was scanned first.
      if (gapsBefore > gapsOf(coverage) && cursor != null) cursor = null;
      hits = await list();
    }

    final events = <TimelineEvent>[
      for (final hit in hits)
        if (convert(hit.json) case final event?) event
    ];
    final String? next;
    if (hits.length < limit && coverage.upToDate) {
      next = null;
    } else if (hits.isEmpty) {
      // Nothing yet in what was scanned: carry on from the same place.
      next = cursor == null ? _prefix : "$_prefix${cursor.$1}:${cursor.$2}";
    } else {
      next = tokenOf(hits.last);
    }
    return RoomMediaPage(events, next: next);
  }
}
