import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/utils/sticker_source_pack.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sticker extends Fake implements Emoticon {
  _Sticker(this.key);

  @override
  final String key;

  @override
  String? get shortcode => key.split("/").last;
}

class _Pack extends Fake implements EmoticonPack {
  _Pack(this.ownerId, this.identifier, List<String> keys)
      : emotes = keys.map(_Sticker.new).toList();

  @override
  final String ownerId;

  @override
  final String identifier;

  @override
  final List<Emoticon> emotes;
}

bool _all(String _) => true;

void main() {
  final personal = _Pack("@me:example.org", "", ["mxc://a/fox", "mxc://a/cat"]);
  final room = _Pack("!room:example.org", "foxes", ["mxc://a/fox"]);
  final space = _Pack("!space:example.org", "", ["mxc://a/owl"]);

  group("findStickerPack", () {
    test("finds the pack holding the image", () {
      expect(findStickerPack([room, space], "mxc://a/owl"), space);
    });

    test("is null when no pack holds the image", () {
      expect(findStickerPack([personal, room, space], "mxc://a/bat"), isNull);
    });

    test("prefers the tagged pack", () {
      const tag =
          StickerPackTag(roomId: "!room:example.org", stateKey: "foxes");
      expect(findStickerPack([personal, room], "mxc://a/fox", tag: tag), room);
    });

    test("falls back to matching when the tagged pack is unreadable", () {
      const tag = StickerPackTag(roomId: "!gone:example.org", stateKey: "x");
      expect(findStickerPack([space], "mxc://a/owl", tag: tag), space);
    });
  });

  group("StickerPackTag", () {
    test("round-trips through event content", () {
      final tag = StickerPackTag.forPack(room)!;
      final parsed =
          StickerPackTag.fromContent({stickerPackTagKey: tag.toJson()})!;
      expect(parsed.roomId, "!room:example.org");
      expect(parsed.stateKey, "foxes");
    });

    test("personal packs are not tagged", () {
      expect(StickerPackTag.forPack(personal), isNull);
      expect(
          stickerPackTagFor(_Sticker("mxc://a/cat"), [personal],
              canShare: _all),
          isNull);
    });

    test("a room pack is tagged even when a personal pack also holds it", () {
      final tag = stickerPackTagFor(_Sticker("mxc://a/fox"), [personal, room],
          canShare: _all);
      expect(tag?.roomId, "!room:example.org");
    });

    test("ignores malformed tags", () {
      expect(StickerPackTag.fromContent({}), isNull);
      expect(StickerPackTag.fromContent({stickerPackTagKey: "x"}), isNull);
      expect(
          StickerPackTag.fromContent({
            stickerPackTagKey: {"room_id": "@user:example.org", "state_key": ""}
          }),
          isNull);
    });
  });
  // Vommet issue 731: private pack rooms stay unnamed; MSC4459's field.
  group("MSC4459", () {
    test("packs whose room can't be shared are not tagged", () {
      expect(
          stickerPackTagFor(_Sticker("mxc://a/fox"), [personal, room],
              canShare: (id) => id != "!room:example.org"),
          isNull);
    });

    test("the tag carries via servers and the shortcode", () {
      final tag = stickerPackTagFor(_Sticker("mxc://a/fox"), [room],
          canShare: _all, via: (_) => ["example.org"])!;
      expect(tag.toSourcePacks("mxc://a/fox"), {
        "mxc://a/fox": {
          "room_id": "!room:example.org",
          "via": ["example.org"],
          "state_key": "foxes",
          "shortcode": "fox",
        }
      });
    });

    test("reads either name, for the sticker's own image", () {
      final refs = {
        "mxc://a/owl": {"room_id": "!space:example.org", "state_key": ""},
        "mxc://a/fox": {
          "room_id": "!room:example.org",
          "state_key": "foxes",
          "via": ["example.org", 3],
        },
      };
      for (final key in [imageSourcePacksKey, stableImageSourcePacksKey]) {
        final tag =
            StickerPackTag.fromContent({key: refs}, mxc: "mxc://a/fox")!;
        expect(tag.roomId, "!room:example.org");
        expect(tag.via, ["example.org"]);
      }
      expect(
          StickerPackTag.fromContent({imageSourcePacksKey: refs},
              mxc: "mxc://a/bat"),
          isNull);
    });

    test("Vommet's own field wins", () {
      final tag = StickerPackTag.fromContent({
        stickerPackTagKey: {"room_id": "!room:example.org", "state_key": "x"},
        imageSourcePacksKey: {
          "mxc://a/fox": {"room_id": "!other:example.org", "state_key": ""}
        },
      }, mxc: "mxc://a/fox")!;
      expect(tag.roomId, "!room:example.org");
    });

    test("via servers: most members first, at most three", () {
      expect(
          viaServers([
            "@a:one.org",
            "@b:two.org",
            "@c:two.org",
            "@d:three.org",
            "@e:four.org",
            "@f:four.org",
            "@g:four.org",
          ]),
          ["four.org", "two.org", "one.org"]);
    });
  });
}
