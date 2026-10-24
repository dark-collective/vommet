import 'dart:async';
import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
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

  @override
  List<Uri>? getLinks({Timeline? timeline}) => links;
}

class _Timeline extends Fake implements Timeline {
  _Timeline(this.events);

  @override
  List<TimelineEvent> events;

  @override
  StreamController<int> onEventAdded = StreamController.broadcast(sync: true);

  @override
  bool isEventRedacted(TimelineEvent event) => false;

  @override
  bool get canLoadHistory => false;
}

class _Room extends Fake implements Room {
  _Room(this.timeline);

  @override
  final Timeline? timeline;
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
}
