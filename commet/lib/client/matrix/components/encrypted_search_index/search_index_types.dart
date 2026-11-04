// Vommet (issues 602, 611): the encrypted search index's plain data types,
// shared by the index isolate and the app (no database imports, so the web
// build can use them too).
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';

/// A search of the index: in one room (the index's form of
/// MatrixSearchParameters) or, for Deep Search, across rooms
/// ([SearchIndexStore.searchAll]).
class IndexQuery {
  const IndexQuery({
    this.words = const [],
    this.senderId,
    this.type,
    this.requireLink = false,
    this.requireImage = false,
    this.requireVideo = false,
    this.requireAttachment = false,
    this.senders = const [],
    this.excludeSenders = const [],
    this.roomIds,
    this.kinds = const {},
    this.mentionsMe = false,
    this.myNames = const [],
    this.beforeTs,
    this.afterTs,
  });

  /// Lowercased words; a message matches when at least half of them occur.
  final List<String> words;
  final String? senderId;

  /// Deep Search: messages from any of these senders.
  final List<String> senders;

  /// Deep Search: never messages from these (ignored users).
  final List<String> excludeSenders;

  /// Deep Search: only these rooms (null = every indexed room).
  final List<String>? roomIds;

  /// Deep Search: messages of any of these kinds.
  final Set<SharedContentKind> kinds;

  /// Deep Search: messages that mention me: by `m.mentions` (or the whole
  /// room), my user id in the text, or one of [myNames] (lowercased display
  /// names, checked now so a rename never leaves stale flags).
  final bool mentionsMe;
  final List<String> myNames;

  /// Deep Search: only messages sent before / after (ms since epoch).
  final int? beforeTs;
  final int? afterTs;

  /// Event type or msgtype.
  final String? type;
  final bool requireLink;
  final bool requireImage;
  final bool requireVideo;
  final bool requireAttachment;
}

/// One result: the decrypted event (with its latest edit applied to the
/// content, if any) and its links.
class IndexHit {
  const IndexHit({
    required this.eventId,
    required this.ts,
    required this.kind,
    required this.json,
    this.links = const [],
    this.roomId = "",
    this.senderId = "",
    this.score = 0,
    this.threadRoot,
    this.isReply = false,
  });

  final String eventId;
  final int ts;

  /// Deep Search: where and who from, and the rank score (searchAll).
  final String roomId;
  final String senderId;
  final double score;
  final String? threadRoot;
  final bool isReply;
  final SharedContentKind kind;
  final Map<String, dynamic> json;
  final List<String> links;
}

/// How many of each kind of message the index holds for a room.
class SharedContentCounts {
  const SharedContentCounts({
    this.images = 0,
    this.videos = 0,
    this.gifs = 0,
    this.files = 0,
    this.voice = 0,
    this.audio = 0,
    this.stickers = 0,
    this.links = 0,
  });

  final int images;
  final int videos;
  final int gifs;
  final int files;
  final int voice;
  final int audio;
  final int stickers;

  /// URLs in text messages (a message with two links counts two).
  final int links;

  /// "Photos and videos" (GIFs have their own row).
  int get photosAndVideos => images + videos;

  /// "Files": documents and audio that isn't a voice message.
  int get filesAndAudio => files + audio;
}

/// What the index knows about a room.
class RoomCoverage {
  const RoomCoverage({
    required this.known,
    required this.complete,
    this.oldestTs,
    this.headTs,
    this.pendingSegments = 0,
    this.undecrypted = 0,
    this.historyLimited = false,
  });

  static const unknown = RoomCoverage(known: false, complete: false);

  /// Whether the room was ever added to the index.
  final bool known;

  /// Whether the backfill reached the start of the room.
  final bool complete;

  /// The oldest message the backfill reached so far (ms since epoch).
  final int? oldestTs;

  /// The newest message the index covers without a gap.
  final int? headTs;
  final int pendingSegments;

  /// Messages that couldn't be decrypted yet (they're retried when keys
  /// arrive).
  final int undecrypted;

  /// The backfill reached the start of what the server shows (history
  /// visibility, or when I joined), not the room's creation.
  final bool historyLimited;

  /// Whether every stretch of the room's history has been scanned.
  bool get upToDate => complete && pendingSegments == 0;
}

/// A stretch of a room still to scan.
class IndexSegment {
  const IndexSegment(
      {required this.id, required this.roomId, this.fromToken, this.stopTs});
  final int id;
  final String roomId;
  final String? fromToken;
  final int? stopTs;
}

/// What scanning one page did.
class IndexPageResult {
  const IndexPageResult({
    required this.added,
    required this.segmentDone,
    required this.coverage,
  });
  final int added;
  final bool segmentDone;
  final RoomCoverage coverage;
}

/// Deep Search: what the caller boosts in "Best match" (the index doesn't
/// know DMs, favorites or where I posted).
class IndexRanking {
  const IndexRanking({
    this.dmRoomIds = const {},
    this.favoriteRoomIds = const {},
    this.postedInRoomIds = const {},
    this.newestFirst = false,
    this.now,
  });

  final Set<String> dmRoomIds;
  final Set<String> favoriteRoomIds;
  final Set<String> postedInRoomIds;

  /// "Newest" instead of "Best match".
  final bool newestFirst;

  /// The time recency is measured from (ms since epoch; tests).
  final int? now;

  static const exactPhraseBoost = 1.5;
  static const dmBoost = 1.3;
  static const favoriteBoost = 1.2;
  static const postedInBoost = 1.1;

  /// Recency halves the score every 30 days, down to [recencyFloor] of it,
  /// so a perfect old match still beats a weak new one.
  static const halfLifeDays = 30.0;
  static const recencyFloor = 0.2;
}

/// Deep Search: the "rooms I've posted in" set, cached per account. It's
/// one query on the reader, so it's kept until the own user's message is
/// indexed ([invalidate]) or for at most [maxAge].
class IndexPostedInCache {
  IndexPostedInCache(
      {this.maxAge = const Duration(minutes: 5), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Duration maxAge;
  final DateTime Function() _clock;
  Set<String>? _rooms;
  DateTime? _at;

  /// The cached rooms, or null when there are none or they're too old.
  Set<String>? get fresh {
    final at = _at;
    final rooms = _rooms;
    if (at == null || rooms == null) return null;
    if (_clock().difference(at) > maxAge) return null;
    return rooms;
  }

  void store(Set<String> rooms) {
    _rooms = rooms;
    _at = _clock();
  }

  void invalidate() {
    _rooms = null;
    _at = null;
  }
}

/// Deep Search: one cross-room search. [hits] are ranked (at most the
/// limit asked for); [roomCounts] counts every candidate per room (for
/// "Most matches"); [capped] = the candidate set hit its cap, so counts are
/// "at least".
class IndexSearchResult {
  const IndexSearchResult({
    this.hits = const [],
    this.roomCounts = const {},
    this.candidates = 0,
    this.capped = false,
  });

  static const empty = IndexSearchResult();

  final List<IndexHit> hits;
  final Map<String, int> roomCounts;
  final int candidates;
  final bool capped;
}

/// Deep Search: the index's coverage of a set of rooms (the coverage line).
class IndexCoverageTotals {
  const IndexCoverageTotals({
    this.rooms = 0,
    this.complete = 0,
    this.started = 0,
    this.undecrypted = 0,
    this.historyLimited = 0,
    this.migrating = false,
  });

  /// Rooms asked about.
  final int rooms;

  /// Fully indexed (backfill done, no gaps).
  final int complete;

  /// Indexed in part.
  final int started;

  /// Messages that couldn't be decrypted yet, across the rooms.
  final int undecrypted;

  /// Complete rooms indexed only back to what history visibility shows.
  final int historyLimited;

  /// The v1 → v2 upgrade is still filling the full-text index (searches
  /// still find everything, more slowly).
  final bool migrating;

  int get notStarted => rooms - complete - started;
}
