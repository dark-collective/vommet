import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/utils/sticker_source_pack.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sticker extends Fake implements Emoticon {
  _Sticker(this.key);

  @override
  final String key;
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
      expect(stickerPackTagFor(_Sticker("mxc://a/cat"), [personal]), isNull);
    });

    test("a room pack is tagged even when a personal pack also holds it", () {
      final tag = stickerPackTagFor(_Sticker("mxc://a/fox"), [personal, room]);
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
}
