import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_notifications_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 814: the New Home Notifications card.

final _now = DateTime(2026, 10, 28, 12);

NotificationEntry _e(String room, String event,
        {int hoursAgo = 1, bool read = false, int count = 1}) =>
    NotificationEntry(
        clientId: "c",
        roomId: room,
        eventId: event,
        senderId: "@a:x",
        time: _now.subtract(Duration(hours: hoursAgo)),
        read: read,
        count: count);

List<String> _ids(List<NotificationEntry> list) =>
    [for (final e in list) e.eventId];

void main() {
  group("arrangeNotifications", () {
    test("unread first, then Earlier, each newest first", () {
      final list = arrangeNotifications([
        _e("!r", "\$old", hoursAgo: 5),
        _e("!r", "\$read", hoursAgo: 1, read: true),
        _e("!r", "\$new", hoursAgo: 2),
        _e("!r", "\$readOld", hoursAgo: 9, read: true)
      ], now: _now, oneEntry: (_) => false);
      expect(_ids(list.unread), ["\$new", "\$old"]);
      expect(_ids(list.earlier), ["\$read", "\$readOld"]);
      expect(list.length, 4);
    });

    test("only the last 7 days", () {
      final list = arrangeNotifications([
        _e("!r", "\$in", hoursAgo: 24 * 7 - 1),
        _e("!r", "\$out", hoursAgo: 24 * 7 + 1, read: true)
      ], now: _now, oneEntry: (_) => false);
      expect(_ids(list.unread), ["\$in"]);
      expect(list.earlier, isEmpty);
    });

    test("Hide read leaves Earlier out", () {
      final list = arrangeNotifications(
          [_e("!r", "\$a"), _e("!r", "\$b", read: true)],
          now: _now, oneEntry: (_) => false, hideRead: true);
      expect(_ids(list.unread), ["\$a"]);
      expect(list.earlier, isEmpty);
    });

    test("one entry per event, an unread copy wins", () {
      final list = arrangeNotifications(
          [_e("!r", "\$a", read: true), _e("!r", "\$a")],
          now: _now, oneEntry: (_) => false);
      expect(_ids(list.unread), ["\$a"]);
      expect(list.earlier, isEmpty);
    });

    test("a DM keeps its newest entry and counts the unread ones", () {
      final list = arrangeNotifications([
        _e("!dm", "\$1", hoursAgo: 1),
        _e("!dm", "\$2", hoursAgo: 2),
        _e("!dm", "\$3", hoursAgo: 3, count: 2),
        _e("!dm", "\$4", hoursAgo: 4, read: true),
        _e("!room", "\$x", hoursAgo: 2),
        _e("!room", "\$y", hoursAgo: 3)
      ], now: _now, oneEntry: (key) => key == "c/!dm");
      expect(_ids(list.unread), ["\$1", "\$x", "\$y"]);
      expect(list.unread.first.count, 4);
      expect(list.earlier, isEmpty);
    });

    test("a one-entry room that's read shows once under Earlier", () {
      final list = arrangeNotifications([
        _e("!dm", "\$1", hoursAgo: 1, read: true),
        _e("!dm", "\$2", hoursAgo: 2, read: true)
      ], now: _now, oneEntry: (_) => true);
      expect(list.unread, isEmpty);
      expect(_ids(list.earlier), ["\$1"]);
    });

    test("a newer read entry turns unread when an older one isn't", () {
      final list = arrangeNotifications([
        _e("!dm", "\$1", hoursAgo: 1, read: true),
        _e("!dm", "\$2", hoursAgo: 2)
      ], now: _now, oneEntry: (_) => true);
      expect(_ids(list.unread), ["\$1"]);
      expect(list.unread.first.read, isFalse);
    });
  });

  group("notificationPreview", () {
    Map<String, dynamic> msg(String type, String body,
            [Map<String, dynamic> more = const {}]) =>
        {"msgtype": type, "body": body, ...more};

    test("text, without a reply fallback", () {
      expect(notificationPreview("m.room.message", msg("m.text", "hi there")),
          "hi there");
      expect(
          notificationPreview("m.room.message",
              msg("m.text", "> <@b:x> earlier\n> more\n\nmy reply")),
          "my reply");
    });

    test("an edit shows its new text", () {
      expect(
          notificationPreview("m.room.message", {
            ...msg("m.text", "* fixed"),
            "m.new_content": msg("m.text", "fixed")
          }),
          "fixed");
    });

    test("media", () {
      expect(notificationPreview("m.room.message", msg("m.image", "a.png")),
          "📷 Photo");
      expect(
          notificationPreview(
              "m.room.message", msg("m.image", "look!", {"filename": "a.png"})),
          "📷 Photo · look!");
      expect(notificationPreview("m.room.message", msg("m.file", "notes.pdf")),
          "📎 notes.pdf");
      expect(notificationPreview("m.room.message", msg("m.video", "v.mp4")),
          "🎬 Video");
      expect(
          notificationPreview("m.room.message",
              msg("m.audio", "rec.ogg", {"org.matrix.msc3245.voice": {}})),
          "🎤 Voice message");
      expect(notificationPreview("m.room.message", msg("m.audio", "song.mp3")),
          "🎵 song.mp3");
      expect(notificationPreview("m.sticker", {"body": "cat"}), "Sticker");
    });

    test("spoilers hide names and captions", () {
      expect(
          notificationPreview(
              "m.room.message", msg("m.image", "x", {"filename": "a.png"}),
              spoiler: true),
          "📷 Photo (spoiler)");
      expect(
          notificationPreview("m.room.message", msg("m.file", "secret.pdf"),
              spoiler: true),
          "📎 File (spoiler)");
    });

    test("other types", () {
      expect(
          notificationPreview("m.room.encrypted", {}), "🔒 Encrypted message");
      expect(notificationPreview("m.room.member", {}), isNull);
    });
  });

  group("highlightRuns", () {
    test("marks every match, case-insensitively", () {
      expect(highlightRuns("Hey Fox, fox!", ["fox"]), [
        ("Hey ", false),
        ("Fox", true),
        (", ", false),
        ("fox", true),
        ("!", false)
      ]);
    });

    test("overlaps merge; short terms are ignored", () {
      expect(highlightRuns("foxtrot", ["fox", "xtro", "t"]),
          [("foxtro", true), ("t", false)]);
    });

    test("no terms, one plain run", () {
      expect(highlightRuns("plain", const []), [("plain", false)]);
      expect(highlightRuns("", ["a"]), isEmpty);
    });
  });

  test("keywordTerms drops globs", () {
    expect(keywordTerms(["deploy", "re*", null, "", "a?b", "[x]"]), ["deploy"]);
  });

  group("Notifications card settings", () {
    test("Hide read is a card setting and round-trips", () {
      const card = HomeCard("mentions", unreadOnly: true);
      expect(card.configurable, isTrue);
      final again = HomeCard.fromJson(card.toJson())!;
      expect(again.unreadOnly, isTrue);
      expect(cardSummary(again), "Unread only · last 7 days");
      expect(cardSummary(const HomeCard("mentions")), "Last 7 days");
    });
  });
}
