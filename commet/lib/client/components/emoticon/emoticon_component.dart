import 'dart:async';
import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/space_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';

import 'emoji_pack.dart';

abstract class EmoticonComponent<T extends Client> implements Component<T> {
  List<EmoticonPack> globalPacks();
  List<EmoticonPack> get ownedPacks;
  List<EmoticonPack> get availablePacks;
  bool get canCreatePack;
  Stream<void> get onStateChanged;

  Future<void> createEmoticonPack(String name, Uint8List? avatarData);

  /// [usage] sets the pack's intended use (stickers, emoji, both); null
  /// leaves it unset, which clients treat as both.
  Future<void> importEmoticonPack(String name, int avatarIndex,
      List<String> names, List<Uint8List> imageDatas,
      {EmoticonUsage? usage});
  Future<void> deleteEmoticonPack(EmoticonPack pack);

  /// Vommet: adds images to [pack], an existing pack owned by this
  /// component. Clashing shortcodes get a `_2`, `_3`… suffix. A non-null
  /// [usage] is set on each added image (e.g. custom emoji added to a
  /// sticker pack stay emoji).
  Future<void> addToPack(
      EmoticonPack pack, List<String> names, List<Uint8List> imageDatas,
      {EmoticonUsage? usage});

  /// Vommet (account level): emoticon components of the sticker rooms you
  /// are in — private rooms that only hold packs, for packs beyond the one
  /// personal pack an account can have. Empty for room/space components.
  List<EmoticonComponent> get stickerRoomComponents;

  /// Vommet (account level): creates a sticker room named [name] and returns
  /// its id.
  Future<String> createStickerRoom(String name);

  /// Vommet (account level): creates a sticker room named [roomName] holding
  /// one new pack.
  Future<void> importIntoNewStickerRoom(String roomName, String name,
      int avatarIndex, List<String> names, List<Uint8List> imageDatas,
      {EmoticonUsage? usage});
}

/// Vommet: true for sticker rooms, which room lists skip (they are listed
/// under Settings › Account › Emoticons instead).
bool isStickerRoom(Room room) =>
    room.getComponent<RoomEmoticonComponent>()?.isStickerRoom == true;

abstract class RoomEmoticonComponent<R extends Client, T extends Room>
    extends EmoticonComponent<R> implements RoomComponent<R, T> {
  /// Vommet: true for a sticker room (see
  /// [EmoticonComponent.stickerRoomComponents]); hidden from room lists.
  bool get isStickerRoom;

  Future<TimelineEvent?> sendSticker(
      Emoticon sticker, TimelineEvent? inReplyTo);

  List<EmoticonPack> get availablePacks;
  List<EmoticonPack> get availableEmoji;
  List<EmoticonPack> get availableStickers;
}

abstract class SpaceEmoticonComponent<R extends Client, T extends Space>
    extends EmoticonComponent<R> implements SpaceComponent<R, T> {}
