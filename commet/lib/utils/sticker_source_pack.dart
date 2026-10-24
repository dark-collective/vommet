import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';

/// Vommet issue 450: Matrix stickers don't say which pack they came from, so
/// Vommet adds this field to the stickers it sends: the room (or space) and
/// state key of the pack's `im.ponies.room_emotes` event. Other clients
/// ignore it; a Vommet receiver that can read that room shows the pack.
const stickerPackTagKey = "im.vommet.sticker_pack";

class StickerPackTag {
  const StickerPackTag({required this.roomId, required this.stateKey});

  final String roomId;
  final String stateKey;

  static StickerPackTag? fromContent(Map<String, dynamic> content) {
    final tag = content[stickerPackTagKey];
    if (tag is! Map) return null;
    final roomId = tag["room_id"];
    final stateKey = tag["state_key"];
    if (roomId is! String || !roomId.startsWith("!")) return null;
    if (stateKey is! String) return null;
    return StickerPackTag(roomId: roomId, stateKey: stateKey);
  }

  /// The tag for a sticker from [pack], or null for a personal pack (it
  /// lives in account data, which nobody else can read).
  static StickerPackTag? forPack(EmoticonPack pack) {
    if (!pack.ownerId.startsWith("!")) return null;
    return StickerPackTag(roomId: pack.ownerId, stateKey: pack.identifier);
  }

  Map<String, dynamic> toJson() => {"room_id": roomId, "state_key": stateKey};
}

/// The pack a sticker came from: the [tag]ged pack when it is among
/// [candidates], else the first candidate holding an image whose key (for
/// Matrix, its mxc URL) is [stickerKey]. Null when none is found.
EmoticonPack? findStickerPack(List<EmoticonPack> candidates, String stickerKey,
    {StickerPackTag? tag}) {
  if (tag != null) {
    for (final pack in candidates) {
      if (pack.ownerId == tag.roomId && pack.identifier == tag.stateKey) {
        return pack;
      }
    }
  }

  for (final pack in candidates) {
    if (pack.emotes.any((e) => e.key == stickerKey)) return pack;
  }

  return null;
}

/// Every pack this account can read for a sticker shown in [room]: the
/// room's packs, its spaces' packs, your favourites, sticker rooms and
/// personal packs, plus the [tag]ged room or space when you are in it.
List<EmoticonPack> stickerPackCandidates(Room room, {StickerPackTag? tag}) {
  final packs = <EmoticonPack>[];
  void addAll(Iterable<EmoticonPack>? more) {
    for (final pack in more ?? const <EmoticonPack>[]) {
      if (!packs.contains(pack)) packs.add(pack);
    }
  }

  if (tag != null) {
    addAll(room.client
        .getRoom(tag.roomId)
        ?.getComponent<RoomEmoticonComponent>()
        ?.ownedPacks);
    addAll(room.client
        .getSpace(tag.roomId)
        ?.getComponent<SpaceEmoticonComponent>()
        ?.ownedPacks);
  }

  addAll(room.getComponent<RoomEmoticonComponent>()?.availablePacks);

  final account = room.client.getComponent<EmoticonComponent>();
  for (final c in account?.stickerRoomComponents ?? <EmoticonComponent>[]) {
    addAll(c.ownedPacks);
  }

  return packs;
}

/// The room or space pack among [candidates] holding [sticker], as a tag
/// for the outgoing event; null when only personal packs hold it.
StickerPackTag? stickerPackTagFor(
    Emoticon sticker, List<EmoticonPack> candidates) {
  final shared = candidates.where((p) => StickerPackTag.forPack(p) != null);
  final pack = findStickerPack(shared.toList(), sticker.key);
  return pack == null ? null : StickerPackTag.forPack(pack);
}
