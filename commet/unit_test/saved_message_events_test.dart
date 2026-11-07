import 'dart:async';
import 'dart:typed_data';
import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/bookmarks/bookmarks.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_encrypted.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/client/timeline_events/timeline_event_unknown.dart';
import 'package:commet/ui/organisms/bookmarks/saved_message_events.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

class _File extends Fake implements FileProvider {}

class _Message extends Fake implements TimelineEventMessage {
  _Message(this.attachments);
  @override
  final List<Attachment>? attachments;
}

class _Encrypted extends Fake implements TimelineEventEncrypted {}

class _Sticker extends Fake implements TimelineEventSticker {}

class _Unknown extends Fake implements TimelineEventUnknown {}

List<Bookmark> saves(int n, {String room = 'a'}) => List.generate(
      n,
      (i) => Bookmark(roomId: room, eventId: '$i', savedTs: n - i),
    );
Future<void> flush() async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.value();
  }
}

void main() {
  test('classification follows room conventions without opening media', () {
    final image = MemoryImage(Uint8List.fromList([1]));
    ImageAttachment photo(String mime) =>
        ImageAttachment(image, _File(), name: 'a', mimeType: mime);
    final video = VideoAttachment(_File(), name: 'v', mimeType: 'video/mp4');
    final gif = VideoAttachment(
      _File(),
      name: 'g',
      mimeType: 'video/mp4',
      isGif: true,
    );
    for (final mime in ['image/jpeg', 'image/webp', 'image/apng']) {
      expect(
        savedMediaMatches(_Message([photo(mime)]), RoomAttachmentFilter.photos),
        isTrue,
      );
    }
    for (final event in <TimelineEvent>[
      _Message([photo('image/gif')]),
      _Message([gif]),
      _Sticker(),
      _Encrypted(),
      _Message([AudioAttachment(_File(), name: 'a')]),
    ]) {
      expect(savedMediaMatches(event, RoomAttachmentFilter.photos), isFalse);
      expect(savedMediaMatches(event, RoomAttachmentFilter.videos), isFalse);
    }
    final mixed = _Message([video, photo('image/png')]);
    expect(savedMediaMatches(mixed, RoomAttachmentFilter.photos), isTrue);
    expect(savedMediaMatches(mixed, RoomAttachmentFilter.videos), isTrue);
  });
  test(
    '24 per batch and three actual in-flight lookups; cached switches do not refetch',
    () async {
      final pending = <Completer<TimelineEvent?>>[];
      int active = 0, peak = 0;
      final loader = SavedMessageEvents((b) async {
        active++;
        if (active > peak) peak = active;
        final c = Completer<TimelineEvent?>();
        pending.add(c);
        try {
          return await c.future;
        } finally {
          active--;
        }
      });
      final items = saves(80);
      loader.configure(items, media: true);
      expect(pending.length, 3);
      expect(loader.remaining, 56);
      for (var i = 0; i < 24; i++) {
        pending[i].complete(_Message([]));
        await flush();
      }
      expect(pending.length, 24);
      expect(loader.checkedCount, 24);
      expect(loader.busy, isFalse);
      expect(peak, 3);
      loader.configure(items, media: true);
      expect(pending.length, 24);
      loader.more();
      expect(pending.length, 27);
      for (var i = 24; i < 48; i++) {
        pending[i].complete(_Message([]));
        await flush();
      }
      expect(loader.checkedCount, 48);
      expect(pending.length, 48);
      loader.more();
      expect(pending.length, 51);
      loader.dispose(); // no future completions may notify a disposed view
      for (var i = 48; i < pending.length; i++) {
        pending[i].complete(null);
      }
    },
  );
  test(
    'scope changes cancel queued work and do not free stalled workers',
    () async {
      final requests = <Bookmark>[];
      final pending = <Completer<TimelineEvent?>>[];
      final loader = SavedMessageEvents((b) {
        requests.add(b);
        final c = Completer<TimelineEvent?>();
        pending.add(c);
        return c.future;
      });
      loader.configure(saves(40), media: true);
      loader.configure(saves(30, room: 'b'), media: true);
      expect(requests.length, 3);
      for (var i = 0; i < 3; i++) {
        pending[i].complete(_Message([]));
        await flush();
      }
      expect(requests.length, 6);
      expect(requests.skip(3).every((b) => b.roomId == 'b'), isTrue);
      loader.dispose();
      for (final c in pending.where((c) => !c.isCompleted)) {
        c.complete(null);
      }
      await flush();
    },
  );
  test(
    'failure and undecryptable events are unavailable; explicit retry can recover',
    () async {
      var retry = false;
      final loader = SavedMessageEvents((b) async {
        if (retry) return _Message([]);
        if (b.eventId == '0') throw StateError('offline');
        return _Encrypted();
      });
      addTearDown(loader.dispose);
      final items = saves(2);
      loader.configure(items, media: true);
      await flush();
      expect(loader.checkedCount, 2);
      expect(loader.unavailableCount, 2);
      expect(loader.remaining, 0);
      retry = true;
      loader.retry();
      await flush();
      expect(loader.unavailableCount, 0);
      expect(loader.checkedCount, 2);
    },
  );
  test('the plain list keeps undecrypted and non-message events', () async {
    final encrypted = _Encrypted();
    final sticker = _Sticker();
    final loader = SavedMessageEvents(
      (b) async => b.eventId == '0' ? encrypted : sticker,
    );
    addTearDown(loader.dispose);
    final items = saves(2);
    loader.configure(items, media: false);
    for (final b in items) {
      loader.request(b);
    }
    await flush();
    expect(loader.event(items[0]), same(encrypted));
    expect(loader.event(items[1]), same(sticker));
    expect(loader.unavailableCount, 0);
  });
  test('media scan counts polls and deleted messages as checked', () async {
    final loader = SavedMessageEvents((_) async => _Unknown());
    addTearDown(loader.dispose);
    final items = saves(2);
    loader.configure(items, media: true);
    await flush();
    expect(loader.checkedCount, 2);
    expect(loader.unavailableCount, 0);
  });
  test('redaction wins over cached and in-flight media results', () async {
    final c = Completer<TimelineEvent?>();
    final loader = SavedMessageEvents((_) => c.future);
    addTearDown(loader.dispose);
    final items = saves(1);
    loader.configure(items, media: true);
    loader.redacted('a', '0');
    c.complete(_Message([]));
    await flush();
    expect(loader.event(items.single), isNull);
    expect(loader.unavailableCount, 0);
    expect(loader.checkedCount, 1);
  });
  test('old scope completions are cached without entering current results',
      () async {
    final pending = <String, Completer<TimelineEvent?>>{};
    final loader = SavedMessageEvents(
        (b) => (pending[b.roomId] = Completer<TimelineEvent?>()).future);
    addTearDown(loader.dispose);
    final a = saves(1), b = saves(1, room: 'b');
    loader.retain([...a, ...b]);
    loader.configure(a, media: true);
    loader.configure(b, media: true);
    pending['a']!.complete(_Message([]));
    await flush();
    expect(loader.checkedCount, 0);
    expect(loader.checked(a.single), isTrue);
    loader.configure(a, media: true);
    expect(loader.checkedCount, 1);
    expect(loader.busy, isFalse);
    pending['b']!.complete(_Message([]));
    await flush();
  });
  test('leaving a room invalidates cached and in-flight previews', () async {
    final pending = Completer<TimelineEvent?>();
    final loader = SavedMessageEvents((_) => pending.future);
    addTearDown(loader.dispose);
    final items = saves(1);
    loader.configure(items, media: true);
    loader.roomUnavailable(items);
    pending.complete(_Message([]));
    await flush();
    expect(loader.unavailableCount, 1);
    expect(loader.event(items.single), isNull);
  });
  test('retry after room leave waits for the invalidated worker then runs',
      () async {
    final old = Completer<TimelineEvent?>();
    var calls = 0;
    final loader = SavedMessageEvents((_) async {
      calls++;
      return calls == 1 ? await old.future : _Message([]);
    });
    addTearDown(loader.dispose);
    final items = saves(1);
    loader.configure(items, media: true);
    loader.roomUnavailable(items);
    loader.retry();
    expect(calls, 1);
    expect(loader.busy, isTrue);
    old.complete(_Message([]));
    await flush();
    expect(calls, 2);
    expect(loader.checkedCount, 1);
    expect(loader.unavailableCount, 0);
    expect(loader.busy, isFalse);
  });
  test(
    'all-media previews are requested explicitly rather than scanning 1000 references',
    () async {
      var requests = 0;
      final loader = SavedMessageEvents((_) async {
        requests++;
        return _Message([]);
      });
      addTearDown(loader.dispose);
      final items = saves(1000);
      loader.configure(items, media: false);
      await flush();
      expect(requests, 0);
      loader.request(items.first);
      await flush();
      loader.request(items.first);
      expect(requests, 1);
    },
  );
}
