import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

class _Message extends Fake implements TimelineEventMessage {
  _Message(this.eventId, this.attachments);

  @override
  final String eventId;

  @override
  final List<Attachment>? attachments;
}

class _Other extends Fake implements TimelineEvent {
  @override
  String get eventId => "state";
}

class _File extends Fake implements FileProvider {}

ImageAttachment _image(String name) => ImageAttachment(
    MemoryImage(Uint8List.fromList([name.hashCode & 0xff])), _File(),
    name: name, mimeType: "image/png");

void main() {
  final a = _image("a.png");
  final b = _image("b.png");
  final c = _image("c.png");
  final video = VideoAttachment(_File(), name: "v.mp4", mimeType: "video/mp4");
  final doc = FileAttachment(_File(), name: "notes.txt");

  // Timelines are newest first.
  final events = <TimelineEvent>[
    _Message(r"$4", [c]),
    _Message(r"$3", [doc]),
    _Other(),
    _Message(r"$2", [a, video]),
    _Message(r"$1", [b]),
    _Message(r"$0", null),
  ];

  test("pictures and videos, oldest first, files and state skipped", () {
    final items = LightboxGalleryItem.fromEvents(events);
    expect(items.map((i) => i.key), [r"$1/0", r"$2/0", r"$2/1", r"$4/0"]);
  });

  test("finds the opened picture or video", () {
    final items = LightboxGalleryItem.fromEvents(events);
    expect(items.indexWhere((i) => i.shows(image: a.image)), 1);
    expect(items.indexWhere((i) => i.shows(video: video.file)), 2);
    expect(items.indexWhere((i) => i.shows(image: c.image)), 3);
  });

  test("media outside the timeline (a banner) isn't found", () {
    final items = LightboxGalleryItem.fromEvents(events);
    final banner = MemoryImage(Uint8List.fromList([1, 2, 3]));
    expect(items.indexWhere((i) => i.shows(image: banner)), -1);
    expect(items.indexWhere((i) => i.shows(video: doc.file)), -1);
  });
}
