import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/utils/telegram_sticker_link.dart';

/// Vommet issue 450: Matrix stickers don't say which pack they came from, so
/// Vommet adds this field to the stickers it sends: the room (or space) and
/// state key of the pack's `im.ponies.room_emotes` event. Other clients
/// ignore it; a Vommet receiver that can read that room shows the pack.
const stickerPackTagKey = "im.vommet.sticker_pack";

/// Vommet issue 731: MSC4459's field for the same thing (mxc URL → pack),
/// which other clients read too. Vommet sends the unstable name and reads
/// both.
const imageSourcePacksKey = "com.beeper.msc4459.image_source_packs";
const stableImageSourcePacksKey = "m.image_source_packs";

/// Vommet issue 824: mautrix bridges (bridgev2) describe a bridged sticker
/// in `info["fi.mau.bridged_sticker"]`: `network`, `id`, `emoji` and
/// `pack_url`, which for Telegram is the set's t.me/addstickers link.
const bridgedStickerKey = "fi.mau.bridged_sticker";

/// The Telegram sticker set a bridged sticker's [content] names, if any.
TelegramStickerLink? bridgedTelegramPack(Map<String, dynamic> content) {
  final info = content["info"];
  if (info is! Map) return null;
  final bridged = info[bridgedStickerKey];
  if (bridged is! Map || bridged["network"] != "telegram") return null;
  final url = bridged["pack_url"];
  if (url is! String) return null;
  return TelegramStickerLink.parse(url);
}

class StickerPackTag {
  const StickerPackTag(
      {required this.roomId,
      required this.stateKey,
      this.via = const [],
      this.shortcode});

  final String roomId;
  final String stateKey;

  /// Servers to join [roomId] through (MSC4459).
  final List<String> via;

  /// The image's key in the pack (MSC4459).
  final String? shortcode;

  /// The tag in a sticker's [content]: Vommet's own field, else the MSC4459
  /// entry for the sticker's [mxc] URL (or its only entry).
  static StickerPackTag? fromContent(Map<String, dynamic> content,
      {String? mxc}) {
    final own = _parse(content[stickerPackTagKey]);
    if (own != null) return own;
    for (final key in [stableImageSourcePacksKey, imageSourcePacksKey]) {
      final refs = content[key];
      if (refs is! Map) continue;
      final ref = mxc != null
          ? refs[mxc]
          : refs.length == 1
              ? refs.values.first
              : null;
      final tag = _parse(ref);
      if (tag != null) return tag;
    }
    return null;
  }

  static StickerPackTag? _parse(Object? tag) {
    if (tag is! Map) return null;
    final roomId = tag["room_id"];
    final stateKey = tag["state_key"];
    if (roomId is! String || !roomId.startsWith("!")) return null;
    if (stateKey is! String) return null;
    final via = tag["via"];
    final shortcode = tag["shortcode"];
    return StickerPackTag(
        roomId: roomId,
        stateKey: stateKey,
        via: via is List ? via.whereType<String>().toList() : const [],
        shortcode: shortcode is String ? shortcode : null);
  }

  /// The tag for a sticker from [pack], or null for a personal pack (it
  /// lives in account data, which nobody else can read).
  static StickerPackTag? forPack(EmoticonPack pack) {
    if (!pack.ownerId.startsWith("!")) return null;
    return StickerPackTag(roomId: pack.ownerId, stateKey: pack.identifier);
  }

  Map<String, dynamic> toJson() => {"room_id": roomId, "state_key": stateKey};

  /// This tag as an MSC4459 reference for the image at [mxc].
  Map<String, dynamic> toSourcePacks(String mxc) => {
        mxc: {
          "room_id": roomId,
          if (via.isNotEmpty) "via": via,
          "state_key": stateKey,
          if (shortcode != null) "shortcode": shortcode,
        }
      };
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
///
/// Vommet issue 731: a tag names its room to everyone who sees the sticker,
/// so only packs whose room [canShare] (the room the sticker goes to, or a
/// public or knockable one, as MSC4459 asks) are tagged. [via] gives the
/// servers to join a pack's room through.
StickerPackTag? stickerPackTagFor(
    Emoticon sticker, List<EmoticonPack> candidates,
    {required bool Function(String roomId) canShare,
    List<String> Function(String roomId)? via}) {
  final shared = candidates
      .where((p) => StickerPackTag.forPack(p) != null && canShare(p.ownerId));
  final pack = findStickerPack(shared.toList(), sticker.key);
  if (pack == null) return null;
  return StickerPackTag(
      roomId: pack.ownerId,
      stateKey: pack.identifier,
      via: via?.call(pack.ownerId) ?? const [],
      shortcode: sticker.shortcode);
}

/// Up to three servers to join a room through: the ones most of its
/// joined members are on (as matrix.to links do).
List<String> viaServers(Iterable<String> memberIds) {
  final counts = <String, int>{};
  for (final id in memberIds) {
    final colon = id.indexOf(":");
    if (colon < 0) continue;
    final server = id.substring(colon + 1);
    counts[server] = (counts[server] ?? 0) + 1;
  }
  final servers = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return servers.take(3).toList();
}
