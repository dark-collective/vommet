import 'package:commet/client/matrix/components/emoticon/image_pack_types.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 731: packs under the spec's names and the old ones.
void main() {
  group("pick", () {
    final a = {
      "images": <String, dynamic>{"a": {}}
    };
    final b = {
      "images": <String, dynamic>{"b": {}}
    };

    test("one copy", () {
      expect(ImagePackTypes.pick(stable: a), a);
      expect(ImagePackTypes.pick(legacy: b), b);
      expect(ImagePackTypes.pick(), isEmpty);
    });

    test("the newer copy wins, the spec's on a tie or unknown time", () {
      expect(
          ImagePackTypes.pick(stable: a, stableTs: 1, legacy: b, legacyTs: 2),
          b);
      expect(
          ImagePackTypes.pick(stable: a, stableTs: 2, legacy: b, legacyTs: 1),
          a);
      expect(
          ImagePackTypes.pick(stable: a, stableTs: 1, legacy: b, legacyTs: 1),
          a);
      expect(ImagePackTypes.pick(stable: a, legacy: b), a);
    });

    test("a newer delete wins", () {
      expect(
          ImagePackTypes.pick(stable: a, stableTs: 1, legacy: {}, legacyTs: 2),
          isEmpty);
    });
  });

  test("enable lists merge and serialize", () {
    final merged = ImagePackTypes.mergeEnabledRooms({
      "rooms": {
        "!a:x": {"": {}},
        "!b:x": {"cats": {}},
      }
    }, {
      "rooms": {
        "!a:x": {"dogs": {}},
        "!c:x": "not a map",
      }
    });
    expect(merged, {
      "!a:x": {"", "dogs"},
      "!b:x": {"cats"},
    });

    merged["!b:x"]!.remove("cats");
    expect(ImagePackTypes.enabledRoomsContent(merged), {
      "rooms": {
        "!a:x": {"": {}, "dogs": {}},
      }
    });
    expect(ImagePackTypes.mergeEnabledRooms(null, null), isEmpty);
  });

  group("order", () {
    test("numbers images, keeping numbered ones in order, new ones last", () {
      final content = ImagePackTypes.withOrder({
        "pack": {"display_name": "Cats"},
        "images": {
          "new": {"url": "mxc://x/new"},
          "second": {"url": "mxc://x/2", "order": 5},
          "first": {"url": "mxc://x/1", "fi.mau.msc4389.order": 1},
        },
      });
      final images = content["images"] as Map;
      expect(images.keys, ["first", "second", "new"]);
      expect(images["first"]["order"], 0);
      expect(images["second"]["fi.mau.msc4389.order"], 1);
      expect(images["new"]["order"], 2);
      expect(images["new"]["url"], "mxc://x/new");
      expect(content["pack"], {"display_name": "Cats"});
    });

    test("leaves packs without images alone", () {
      expect(ImagePackTypes.withOrder({}), isEmpty);
      expect(ImagePackTypes.withOrder({"images": {}}), {"images": {}});
    });

    test("sorts by number, missing counts as 0, ties keep their order", () {
      final sorted = ImagePackTypes.sortedImages<dynamic>({
        "c": {"order": 2},
        "a": {},
        "b": {"fi.mau.msc4389.order": 1},
        "z": {"order": 0},
      });
      expect(sorted.map((e) => e.key), ["a", "z", "b", "c"]);
    });
  });

  test("pack room types", () {
    expect(ImagePackTypes.isPackRoomType("m.image_pack"), isTrue);
    expect(ImagePackTypes.isPackRoomType("com.beeper.image_pack"), isTrue);
    expect(ImagePackTypes.isPackRoomType("m.space"), isFalse);
    expect(ImagePackTypes.isPackRoomType(null), isFalse);
  });

  test("pack room power levels: messages off, packs at 50, room at 100", () {
    final pl =
        ImagePackTypes.packRoomPowerLevels("im.nether.vommet.sticker_room");
    final events = pl["events"] as Map;
    expect(pl["events_default"], 100);
    expect(pl["redact"], 100);
    expect(events["m.room.image_pack"], 50);
    expect(events["im.ponies.room_emotes"], 50);
    expect(events["im.nether.vommet.sticker_room"], 100);
    expect(events["m.room.power_levels"], 100);
  });
}
