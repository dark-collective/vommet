// Vommet (issues 602, 611): the encrypted search index's plain data types,
// shared by the index isolate and the app (no database imports, so the web
// build can use them too).
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';

/// A search over one room, the index's form of MatrixSearchParameters.
class IndexQuery {
  const IndexQuery({
    this.words = const [],
    this.senderId,
    this.type,
    this.requireLink = false,
    this.requireImage = false,
    this.requireVideo = false,
    this.requireAttachment = false,
  });

  /// Lowercased words; a message matches when at least half of them occur.
  final List<String> words;
  final String? senderId;

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
  });

  final String eventId;
  final int ts;
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
