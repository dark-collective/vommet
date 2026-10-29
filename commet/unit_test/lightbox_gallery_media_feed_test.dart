// Vommet: a picture opened from the Media tab is browsed through the tab's
// own list. In unencrypted rooms that list also holds pictures paged from
// the server's filtered history, which the timeline never loads; walking
// the timeline opened them alone, without arrows.
import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Message extends Fake implements TimelineEventMessage {
  _Message(this.eventId, this.attachments);

  @override
  final String eventId;

  @override
  final List<Attachment>? attachments;

  @override
  String get senderId => "@someone:example.org";
}

class _File extends Fake implements FileProvider {}

class _Member extends Fake implements Member {
  @override
  String get displayName => "Someone";
}

class _Room extends Fake implements Room {
  @override
  Member getMemberOrFallback(String id) => _Member();
}

/// A feed whose older pages are [older], one batch per [loadOlder].
class _Feed extends RoomAttachmentFeed {
  _Feed() : super(_Room());

  final List<List<RoomAttachment>> older = [];
  final List<(RoomAttachmentKind?, RoomAttachmentFilter)> loads = [];

  @override
  Future<void> loadOlder(RoomAttachmentKind? kind,
      {RoomAttachmentFilter filter = RoomAttachmentFilter.all,
      int want = 24,
      int maxPages = 6}) async {
    loads.add((kind, filter));
    if (older.isEmpty) {
      reachedStart = true;
    } else {
      media.addAll(older.removeAt(0));
    }
    notifyListeners();
  }
}

// A 1x1 PNG; each picture gets its own copy so they don't compare equal.
const _png = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];

ImageAttachment _image(String id) =>
    ImageAttachment(MemoryImage(Uint8List.fromList(_png)), _File(),
        name: "$id.png", mimeType: "image/png");

/// A message with one picture, as the feed lists it.
List<RoomAttachment> _picture(String id) {
  final image = _image(id);
  return [
    (_Message(id, [image]), image)
  ];
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void _expectShown(WidgetTester tester, String key) =>
    expect(tester.getTopLeft(find.byKey(ValueKey(key))).dx, 0);

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("the source lists the tab's media oldest first, through the chip", () {
    final video =
        VideoAttachment(_File(), name: "clip.mp4", mimeType: "video/mp4");
    final second = _image(r"$2b");
    final feed = _Feed()
      ..media.addAll([
        ..._picture(r"$3"),
        (_Message(r"$2", [video, second]), video),
        (_Message(r"$2", [video, second]), second),
        ..._picture(r"$1"),
      ]);

    expect(
        RoomMediaGallerySource(feed, RoomAttachmentFilter.all)
            .items
            .map((item) => item.key),
        [r"$1/0", r"$2/1", r"$2/0", r"$3/0"]);
    expect(
        RoomMediaGallerySource(feed, RoomAttachmentFilter.photos)
            .items
            .map((item) => item.key),
        [r"$1/0", r"$2/1", r"$3/0"]);
    expect(RoomMediaGallerySource(feed, RoomAttachmentFilter.all).canLoadOlder,
        isTrue);
    feed.reachedStart = true;
    expect(RoomMediaGallerySource(feed, RoomAttachmentFilter.all).canLoadOlder,
        isFalse);
  });

  // The regression: $2 came from the filtered pages only (no timeline at
  // all here), and must still have neighbours on both sides.
  testWidgets("a picture only in the Media tab's list opens in a gallery",
      (tester) async {
    final feed = _Feed()
      ..media.addAll([..._picture(r"$3"), ..._picture(r"$2")])
      ..older.add(_picture(r"$1"));
    final source = RoomMediaGallerySource(feed, RoomAttachmentFilter.all);
    final opened = (feed.media[1].$2 as ImageAttachment).image;

    Future<void>? gallery;
    await tester.pumpWidget(MaterialApp(
        home: LightboxGalleryScope.source(
            source: source,
            newestFirst: true,
            child: Builder(
                builder: (context) => TextButton(
                    onPressed: () => gallery = LightboxGallery.showIfInTimeline(
                        context,
                        image: opened),
                    child: const Text("open"))))));
    await tester.tap(find.text("open"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(gallery, isNotNull);
    _expectShown(tester, r"$2/0");

    // Opened at the oldest loaded picture, the gallery asked the feed for
    // older Media through the tab's chip.
    expect(feed.loads, isNotEmpty);
    expect(feed.loads,
        everyElement((RoomAttachmentKind.media, RoomAttachmentFilter.all)));
    expect(find.text("2 / 3 · Someone"), findsOneWidget);

    // Like the grid: right goes to the older picture, left to the newer.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectShown(tester, r"$1/0");
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    _expectShown(tester, r"$3/0");
    expect(find.text("1 / 3 · Someone"), findsOneWidget);
  });

  // Vommet issue 771 on the tab's own list: Jump to message follows the
  // gallery onto a picture paged from the filtered history.
  testWidgets("Jump to message works for the tab's own list", (tester) async {
    final feed = _Feed()
      ..media.addAll([..._picture(r"$3"), ..._picture(r"$2")])
      ..older.add(_picture(r"$1"));
    final jumped = <String>[];
    final opened = (feed.media[0].$2 as ImageAttachment).image;
    await tester.pumpWidget(MaterialApp(
        home: LightboxGalleryScope.source(
            source: RoomMediaGallerySource(feed, RoomAttachmentFilter.all),
            newestFirst: true,
            onJumpToEvent: jumped.add,
            child: Builder(
                builder: (context) => TextButton(
                    onPressed: () => LightboxGallery.showIfInTimeline(context,
                        image: opened),
                    child: const Text("open"))))));
    await tester.tap(find.text("open"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    _expectShown(tester, r"$3/0");

    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectShown(tester, r"$1/0");
    await tester.tap(find.byKey(const ValueKey("lightbox_menu_button")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Jump to message"));
    await tester.pumpAndSettle();
    expect(jumped, [r"$1"]);
    expect(find.byType(LightboxGallery), findsNothing);
  });

  testWidgets("going past the loaded end loads the feed's older pages",
      (tester) async {
    final feed = _Feed()
      ..media.addAll([
        for (var i = 9; i >= 6; i--) ..._picture("\$$i"),
      ])
      ..older.add(_picture(r"$5"))
      ..older.add(_picture(r"$4"));
    await tester.pumpWidget(MaterialApp(
        home: LightboxGallery(
            source: RoomMediaGallerySource(feed, RoomAttachmentFilter.photos),
            initialKey: r"$9/0",
            newestFirst: true)));
    await tester.pump();

    for (final key in [r"$8/0", r"$7/0", r"$6/0"]) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
      _expectShown(tester, key);
    }
    // Nearing the oldest loaded picture fetched the next pages, through
    // the chip, so the arrows carry on into them.
    expect(feed.loads, isNotEmpty);
    expect(feed.loads,
        everyElement((RoomAttachmentKind.media, RoomAttachmentFilter.photos)));
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectShown(tester, r"$5/0");
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectShown(tester, r"$4/0");
    expect(find.text("6 / 6 · Someone"), findsOneWidget);
  });

  testWidgets("an arrow past the oldest loaded picture asks for more",
      (tester) async {
    // The batches asked for on opening (and while the strip fills) bring
    // no picture; the gallery stops asking after a few.
    final feed = _Feed()
      ..media.addAll(_picture(r"$2"))
      ..older.addAll([for (var i = 0; i < 5; i++) <RoomAttachment>[]])
      ..older.add(_picture(r"$1"));
    await tester.pumpWidget(MaterialApp(
        home: LightboxGallery(
            source: RoomMediaGallerySource(feed, RoomAttachmentFilter.all),
            initialKey: r"$2/0",
            newestFirst: true)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    _expectShown(tester, r"$2/0");
    expect(feed.older, hasLength(1), reason: "the empty batches stop it");
    expect(find.text("1 / 1 · Someone"), findsOneWidget);

    // Right on the oldest loaded picture asks the feed for the next page.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(feed.older, isEmpty);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectShown(tester, r"$1/0");
    expect(find.text("2 / 2 · Someone"), findsOneWidget);
  });
}
