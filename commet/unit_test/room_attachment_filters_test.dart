import 'dart:async';
import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/components/room_media_history/room_media_history_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 602: the Media/Files chips, the Links list and the DM
// Profile tab's "Shared in this chat" counts.

class _Message extends Fake implements TimelineEventMessage {
  _Message(this.eventId, this.attachments,
      {this.links, required this.originServerTs});

  @override
  final String eventId;

  @override
  final List<Attachment>? attachments;

  final List<Uri>? links;

  @override
  final DateTime originServerTs;

  int linkLookups = 0;

  @override
  List<Uri>? getLinks({Timeline? timeline}) {
    linkLookups++;
    return links;
  }
}

class _Timeline extends Fake implements Timeline {
  _Timeline(this.events);

  @override
  List<TimelineEvent> events;

  @override
  StreamController<int> onEventAdded = StreamController.broadcast(sync: true);

  @override
  StreamController<int> onChange = StreamController.broadcast();

  @override
  StreamController<int> onRemove = StreamController.broadcast(sync: true);

  @override
  bool isEventRedacted(TimelineEvent event) => false;

  @override
  bool get canLoadHistory => false;
}

class _Room extends Fake implements Room {
  _Room(this.timeline, {this.pager});

  @override
  final Timeline? timeline;

  final RoomMediaHistoryComponent? pager;

  @override
  T? getComponent<T extends RoomComponent>() {
    final p = pager;
    return p is T ? p as T : null;
  }
}

/// Server-filtered pages of messages with a file, newest first.
class _Pager extends Fake implements RoomMediaHistoryComponent {
  _Pager(this.pages);

  /// Each page's events; the last page has no next token.
  final List<List<TimelineEvent>> pages;
  final List<String?> asked = [];
  bool fail = false;
  final StreamController<String> redactions = StreamController.broadcast();

  @override
  bool get available => true;

  @override
  Future<RoomMediaPage> loadPage(String? from, {int limit = 50}) async {
    asked.add(from);
    if (fail) throw Exception("M_UNRECOGNIZED");
    final i = from == null ? 0 : int.parse(from);
    return RoomMediaPage(pages[i],
        next: i + 1 < pages.length ? "${i + 1}" : null);
  }

  @override
  Stream<String> get onRedacted => redactions.stream;
}

class _HistoryTimeline extends _Timeline {
  _HistoryTimeline(super.events, this.older);

  /// Pages loadMoreHistory appends, oldest last.
  final List<List<TimelineEvent>> older;
  int pagesLoaded = 0;

  @override
  bool get canLoadHistory => older.isNotEmpty;

  @override
  Future<void> loadMoreHistory() async {
    pagesLoaded++;
    events.addAll(older.removeAt(0));
  }
}

class _File extends Fake implements FileProvider {}

ImageAttachment _image(String name, String mime) =>
    ImageAttachment(MemoryImage(Uint8List.fromList([1])), _File(),
        name: name, mimeType: mime);

void main() {
  final photo = _image("a.png", "image/png");
  final gif = _image("b.gif", "image/gif");
  final video = VideoAttachment(_File(), name: "v.mp4", mimeType: "video/mp4");
  final bridgedGif = VideoAttachment(_File(),
      name: "g.mp4", mimeType: "video/mp4", isGif: true);
  final doc = FileAttachment(_File(), name: "notes.pdf");
  final song = AudioAttachment(_File(), name: "song.mp3");
  final voice = AudioAttachment(_File(), name: "voice.ogg", isVoice: true);

  test("Media chips: photos, videos and GIFs (image/gif or bridged)", () {
    const f = RoomAttachmentFilter.values;
    expect(RoomAttachmentFilter.of(RoomAttachmentKind.media),
        [f[0], f[1], f[2], f[3]]);
    expect(RoomAttachmentFilter.photos.matches(photo), isTrue);
    expect(RoomAttachmentFilter.photos.matches(gif), isFalse);
    expect(RoomAttachmentFilter.videos.matches(video), isTrue);
    expect(RoomAttachmentFilter.videos.matches(bridgedGif), isFalse);
    expect(RoomAttachmentFilter.gifs.matches(gif), isTrue);
    expect(RoomAttachmentFilter.gifs.matches(bridgedGif), isTrue);
    expect(RoomAttachmentFilter.gifs.matches(photo), isFalse);
  });

  test("Files chips: voice messages only with the voice flag", () {
    expect(RoomAttachmentFilter.of(RoomAttachmentKind.files), [
      RoomAttachmentFilter.all,
      RoomAttachmentFilter.files,
      RoomAttachmentFilter.voice
    ]);
    expect(RoomAttachmentFilter.voice.matches(voice), isTrue);
    expect(RoomAttachmentFilter.voice.matches(song), isFalse);
    expect(RoomAttachmentFilter.files.matches(song), isTrue);
    expect(RoomAttachmentFilter.files.matches(doc), isTrue);
    expect(RoomAttachmentFilter.files.matches(voice), isFalse);
  });

  test("feed: lists, links and counts from the loaded timeline", () async {
    final timeline = _Timeline([
      _Message(r"$5", [voice], originServerTs: DateTime(2026, 10, 20)),
      _Message(r"$4", null,
          links: [
            Uri.parse("https://a.example"),
            Uri.parse("https://b.example")
          ],
          originServerTs: DateTime(2026, 10, 19)),
      _Message(r"$3", [gif, photo], originServerTs: DateTime(2026, 10, 2)),
      _Message(r"$2", [doc, song], originServerTs: DateTime(2026, 9, 28)),
      _Message(r"$1", [video, bridgedGif],
          originServerTs: DateTime(2026, 9, 3)),
    ]);
    final feed = RoomAttachmentFeed(_Room(timeline));
    final counts = FeedSharedContentCounts(feed);
    await feed.start();

    expect(feed.media.length, 4);
    expect(feed.files.length, 3);
    expect(feed.links.map((l) => l.$2.host), ["a.example", "b.example"]);
    expect(feed.oldestLoaded, DateTime(2026, 9, 3));
    expect(
        feed
            .filtered(RoomAttachmentKind.media, RoomAttachmentFilter.gifs)
            .map((a) => a.$2),
        [gif, bridgedGif]);

    // Not looked through to the start yet: "N+".
    expect(counts.complete, isFalse);
    expect(counts.count(SharedCategory.photosAndVideos).toString(), "2+");
    expect(counts.count(SharedCategory.gifs).count, 2);
    expect(counts.count(SharedCategory.files).count, 2);
    expect(counts.count(SharedCategory.voice).count, 1);
    expect(counts.count(SharedCategory.links).count, 2);

    // canLoadHistory is false: the next page reaches the start.
    await feed.loadOlder(null);
    expect(feed.reachedStart, isTrue);
    expect(counts.complete, isTrue);
    expect(counts.count(SharedCategory.photosAndVideos).toString(), "2");

    counts.dispose();
    feed.dispose();
  });

  // Vommet: onEventAdded fires once per event, synchronously; the feed
  // rescanned the whole timeline each time, so a page of 30 ran 30 scans.
  test("feed: a burst of new events scans once, each message worked out once",
      () async {
    final first = _Message(r"$1", [photo], originServerTs: DateTime(2026, 9));
    final timeline = _Timeline([first]);
    final feed = RoomAttachmentFeed(_Room(timeline));
    await feed.start();
    var scans = 0;
    feed.addListener(() => scans++);

    for (var i = 2; i <= 31; i++) {
      timeline.events.insert(
          0, _Message("\$$i", [photo], originServerTs: DateTime(2026, 10, i)));
      timeline.onEventAdded.add(0);
    }
    expect(scans, 0);
    await Future<void>.delayed(Duration.zero);
    expect(scans, 1);
    expect(feed.media.length, 31);
    expect(first.linkLookups, 1);

    feed.dispose();
  });

  // Vommet: unencrypted rooms page Media/Files with a server-filtered
  // /messages instead of the timeline (30 events per slow request).
  group("filtered pages", () {
    _Message msg(String id, List<Attachment>? attachments, int day,
            {List<Uri>? links}) =>
        _Message(id, attachments,
            links: links, originServerTs: DateTime(2026, 10, day));

    test("merged with the timeline, deduped by id, newest first", () async {
      final timeline = _HistoryTimeline([
        msg(r"$9", [photo], 9, links: [Uri.parse("https://a.example")]),
        msg(r"$8", [doc], 8),
      ], [
        [
          msg(r"$1", [song], 1)
        ]
      ]);
      final pager = _Pager([
        // The newest filtered page overlaps what the timeline has.
        [
          msg(r"$9", [photo], 9),
          msg(r"$8", [doc], 8),
          msg(r"$6", [gif], 6)
        ],
        [
          msg(r"$4", [video], 4),
          msg(r"$3", [voice], 3)
        ],
      ]);
      final feed = RoomAttachmentFeed(_Room(timeline, pager: pager));
      final counts = FeedSharedContentCounts(feed);
      await feed.start();
      expect(feed.usesFilteredPages, isTrue);
      expect(feed.reachedStartOf(RoomAttachmentKind.media), isFalse);

      await feed.loadOlder(RoomAttachmentKind.media, want: 2);
      expect(pager.asked, [null, "1"]);
      expect(timeline.pagesLoaded, 0);
      expect(feed.media.map((a) => a.$1.eventId), [r"$9", r"$6", r"$4"]);
      expect(feed.files.map((a) => a.$1.eventId), [r"$8", r"$3"]);
      expect(feed.links, hasLength(1));
      expect(feed.reachedStartOf(RoomAttachmentKind.media), isTrue);
      expect(feed.reachedStartOf(RoomAttachmentKind.files), isTrue);
      // Links still come from the timeline, which isn't at the start.
      expect(feed.reachedStartOf(RoomAttachmentKind.links), isFalse);
      expect(counts.count(SharedCategory.photosAndVideos).toString(), "2");
      expect(counts.count(SharedCategory.links).toString(), "1+");
      expect(counts.complete, isFalse);

      // Nothing more to ask the server for.
      await feed.loadOlder(RoomAttachmentKind.files);
      expect(pager.asked, hasLength(2));

      // The Links tab pages the timeline; its file shows up once.
      await feed.loadOlder(RoomAttachmentKind.links);
      expect(timeline.pagesLoaded, 1);
      expect(feed.files.map((a) => a.$1.eventId), [r"$8", r"$3", r"$1"]);
      expect(counts.complete, isTrue);

      counts.dispose();
      feed.dispose();
    });

    test("a message deleted after it was paged drops out", () async {
      final pager = _Pager([
        [
          msg(r"$5", [photo], 5),
          msg(r"$4", [gif], 4)
        ],
      ]);
      final feed = RoomAttachmentFeed(_Room(_Timeline([]), pager: pager));
      await feed.start();
      await feed.loadOlder(RoomAttachmentKind.media);
      expect(feed.media, hasLength(2));

      pager.redactions.add(r"$5");
      await Future<void>.delayed(Duration.zero);
      expect(feed.media.map((a) => a.$1.eventId), [r"$4"]);
      feed.dispose();
    });

    test("a failed filtered request falls back to the timeline", () async {
      final timeline = _HistoryTimeline([], [
        [
          msg(r"$2", [photo], 2)
        ]
      ]);
      final pager = _Pager([])..fail = true;
      final feed = RoomAttachmentFeed(_Room(timeline, pager: pager));
      await feed.start();
      await feed.loadOlder(RoomAttachmentKind.media);
      expect(feed.usesFilteredPages, isFalse);
      expect(timeline.pagesLoaded, 1);
      expect(feed.media.map((a) => a.$1.eventId), [r"$2"]);
      feed.dispose();
    });

    test("encrypted rooms (pager unavailable) page the timeline", () async {
      final timeline = _HistoryTimeline([], [
        [
          msg(r"$2", [photo], 2)
        ]
      ]);
      final feed = RoomAttachmentFeed(_Room(timeline, pager: _Unavailable()));
      await feed.start();
      expect(feed.usesFilteredPages, isFalse);
      await feed.loadOlder(RoomAttachmentKind.media);
      expect(timeline.pagesLoaded, 1);
      feed.dispose();
    });
  });
}

class _Unavailable extends Fake implements RoomMediaHistoryComponent {
  @override
  bool get available => false;
}
