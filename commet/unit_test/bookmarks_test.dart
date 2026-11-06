import 'package:commet/client/components/bookmarks/bookmarks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("parse skips bad entries and duplicates, newest first", () {
    final items = Bookmarks.parse({
      "version": 1,
      "items": [
        {"room_id": "!a:x", "event_id": "\$1", "saved_ts": 10, "tags": []},
        {"room_id": "!a:x", "event_id": "\$2", "saved_ts": 30},
        {"room_id": "!a:x", "event_id": "\$1", "saved_ts": 50},
        {"room_id": "", "event_id": "\$3"},
        {"event_id": "\$4"},
        "junk",
      ],
    });
    expect(items.map((b) => b.eventId), ["\$2", "\$1"]);
    expect(items.last.savedTs, 10);
  });

  test("parse tolerates missing or wrong content", () {
    expect(Bookmarks.parse(null), isEmpty);
    expect(Bookmarks.parse({"items": "nope"}), isEmpty);
  });

  test("tags are cleaned when read", () {
    final b = Bookmark.fromJson({
      "room_id": "!a:x",
      "event_id": "\$1",
      "tags": [" Recipes ", "#recipes", "", 4, "Work"],
      "note": "  ",
    })!;
    expect(b.tags, ["recipes", "work"]);
    expect(b.note, isNull);
  });

  test("serialize round-trips and keeps only ids, tags and note", () {
    const b = Bookmark(
        roomId: "!a:x",
        eventId: "\$1",
        savedTs: 5,
        tags: ["work"],
        note: "for later");
    final content = Bookmarks.serialize([b]);
    expect(content["version"], 1);
    final item = (content["items"] as List).single as Map;
    expect(
        item.keys.toSet(), {"room_id", "event_id", "saved_ts", "tags", "note"});
    final back = Bookmarks.parse(content).single;
    expect(back.tags, ["work"]);
    expect(back.note, "for later");
  });

  test("serialize caps the list", () {
    final many = [
      for (var i = 0; i < Bookmarks.maxItems + 5; i++)
        Bookmark(roomId: "!a:x", eventId: "\$$i", savedTs: i),
    ];
    expect((Bookmarks.serialize(many)["items"] as List).length,
        Bookmarks.maxItems);
  });

  test("tagsOf lists the most used first", () {
    const items = [
      Bookmark(roomId: "!a", eventId: "1", savedTs: 0, tags: ["b", "a"]),
      Bookmark(roomId: "!a", eventId: "2", savedTs: 0, tags: ["a"]),
      Bookmark(roomId: "!a", eventId: "3", savedTs: 0, tags: ["c"]),
    ];
    expect(Bookmarks.tagsOf(items), ["a", "b", "c"]);
  });

  test("cleanTags trims long tags", () {
    expect(
        Bookmarks.cleanTags(["x" * 50]).single.length, Bookmarks.maxTagLength);
  });
}
