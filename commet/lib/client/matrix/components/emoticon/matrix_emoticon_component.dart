import 'dart:async';
import 'dart:typed_data';

import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_pack.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_state_manager.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_import_emoticon_pack_task.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/emoticon_names.dart';
import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart' as matrix;

/// Manages custom emoticon packs from the matrix user account state
class MatrixEmoticonComponent extends EmoticonComponent<MatrixClient> {
  static const roomEmotesStateKey = "im.ponies.room_emotes";
  static const globalEmoteRoomsStateKey = "im.ponies.emote_rooms";

  /// Vommet: state event marking a "sticker room": a private room whose only
  /// purpose is holding packs. Account data fits only one personal pack
  /// (`im.ponies.user_emotes`), so further packs are room packs in sticker
  /// rooms. Vommet offers their packs in every room ([everywherePacks])
  /// without favouriting them; favouriting (`im.ponies.emote_rooms`) stays
  /// your choice and is what other image-pack clients read. Vommet hides
  /// sticker rooms from the room list and lists them under Settings ›
  /// Emoticons instead; invite a friend to share the room's packs.
  static const stickerRoomStateKey = "im.nether.vommet.sticker_room";

  final StreamController<void> _onStateChanged = StreamController.broadcast();

  // Vommet: always true for the account; once the account-data pack exists,
  // new packs go to a sticker room (upstream: ownedPacks.isEmpty, which hid
  // Import/New pack for anyone with a personal pack).
  @override
  bool get canCreatePack => true;

  /// The account-level component (personal packs), as opposed to a room's
  /// or space's.
  bool get isAccountLevel => state is MatrixEmoticonPersonalStateManager;

  @override
  MatrixClient client;

  String get ownerId => client.identifier;

  String get ownerDisplayName => client.self?.displayName ?? client.identifier;

  MatrixEmoticonStateManager state;

  MatrixEmoticonComponent(this.client, this.state) {
    refreshOwnedPacks();

    state.onStateChanged.listen((_) {
      refreshOwnedPacks();
      _onStateChanged.add(null);
    });
  }

  void refreshOwnedPacks() {
    final state = this.state.getAllStates();

    _ownedPacks = state.entries.where((e) {
      final val = e.value;
      if (val is Map<String, dynamic>) {
        return val.isNotEmpty;
      } else {
        return false;
      }
    }).map((e) {
      return MatrixEmoticonPack(this, e.key, e.value);
    }).toList();
  }

  @override
  Stream<void> get onStateChanged => _onStateChanged.stream;

  List<EmoticonPack> _ownedPacks = List.empty();

  @override
  List<EmoticonPack> get ownedPacks => _ownedPacks;

  String getDefaultDisplayName() {
    return "Personal";
  }

  ImageProvider? getDefaultImage() {
    return null;
  }

  IconData? getDefaultIcon() {
    return Icons.star;
  }

  bool isGloballyAvailable(String packId) {
    return true;
  }

  @override
  Future<void> createEmoticonPack(String name, Uint8List? avatarData) async {
    Uri? avatar;
    if (avatarData != null) {
      avatar = await client.getMatrixClient().uploadContent(avatarData);
    }

    var content = <String, dynamic>{
      "pack": {
        "display_name": name,
        if (avatar != null) "avatar_url": avatar.toString()
      }
    };

    await _writeNewPack(name, content);
  }

  @override
  Future<void> importEmoticonPack(String name, int avatarIndex,
      List<String> names, List<Uint8List> imageDatas,
      {EmoticonUsage? usage}) async {
    var task = MatrixImportEmoticonPackTask(imageDatas, client);
    backgroundTaskManager.addTask(task);
    var uris = await task.uploadImages();

    var content = _packContent(name, uris, avatarIndex, names, usage);

    await _writeNewPack(name, content);

    task.complete();
  }

  Map<String, dynamic> _packContent(String name, List<Uri?> uris,
      int avatarIndex, List<String> names, EmoticonUsage? usage) {
    var content = <String, dynamic>{
      "pack": {
        "display_name": name,
        "avatar_url": uris[avatarIndex].toString(),
        // MSC2545 pack usage; omitted means both.
        if (usage == EmoticonUsage.emoji) "usage": ["emoticon"],
        if (usage == EmoticonUsage.sticker) "usage": ["sticker"],
        if (usage == EmoticonUsage.all) "usage": ["emoticon", "sticker"],
      },
      "images": <String, dynamic>{}
    };

    for (var i = 0; i < names.length; i++) {
      var name = names[i];
      if (uris[i] == null) continue;
      content["images"]![name] = {
        "display_name": name,
        "url": uris[i]!.toString()
      };
    }

    return content;
  }

  /// Vommet: stores a new pack. The account's first personal pack goes to
  /// account data as upstream; later ones go to your first editable sticker
  /// room (created if you have none). Sticker-room packs are not
  /// favourited: [everywherePacks] offers them in every room anyway.
  Future<void> _writeNewPack(String name, Map<String, dynamic> content) async {
    if (isAccountLevel && ownedPacks.isNotEmpty) {
      var editable = stickerRoomComponents.where((c) => c.canCreatePack);
      var roomId = editable.isNotEmpty
          ? (editable.first as MatrixEmoticonComponent).state.id
          : await createStickerRoom(defaultStickerRoomName);
      await _writeRoomPack(roomId, name, content);
      return;
    }

    var key = getNewPackKeyState(name);
    await state.setState(key, content);
  }

  String getNewPackKeyState(String packName) {
    var states = state.getAllStates();

    // Check for existing and empty state keys, and reuse those keys first
    for (var pair in states.entries) {
      if (pair.value is Map && (pair.value as Map).isEmpty) {
        return pair.key;
      }
    }

    // Vommet: never reuse a live pack's key (upstream did, so importing a
    // second pack with the same name overwrote the first).
    return EmoticonNames.unique(packName, states.keys);
  }

  @override
  Future<void> addToPack(
      EmoticonPack pack, List<String> names, List<Uint8List> imageDatas,
      {EmoticonUsage? usage}) async {
    if (pack is! MatrixEmoticonPack || pack.component != this) {
      throw ArgumentError("Pack is not owned by this component");
    }

    var task = MatrixImportEmoticonPackTask(imageDatas, client);
    backgroundTaskManager.addTask(task);
    var uris = await task.uploadImages();

    // Copy so the cached account data / room state is not mutated before
    // the server accepts the change.
    var content = Map<String, dynamic>.from(state.getState(pack.stateKey));
    var images = Map<String, dynamic>.from(
        (content["images"] as Map?)?.cast<String, dynamic>() ?? {});

    var finalNames = EmoticonNames.uniqueAll(names, images.keys);
    for (var i = 0; i < finalNames.length; i++) {
      if (uris[i] == null) continue;
      images[finalNames[i]] = {
        "display_name": finalNames[i],
        "url": uris[i]!.toString(),
        if (usage == EmoticonUsage.emoji) "usage": ["emoticon"],
        if (usage == EmoticonUsage.sticker) "usage": ["sticker"],
        if (usage == EmoticonUsage.all) "usage": ["emoticon", "sticker"],
      };
    }
    content["images"] = images;

    await state.setState(pack.stateKey, content);
    task.complete();
  }

  static String get defaultStickerRoomName => "Sticker packs";

  static bool isStickerRoom(matrix.Room? room) =>
      room != null && room.getState(stickerRoomStateKey) != null;

  /// Emoticon components of every joined sticker room, editable or not.
  @override
  List<EmoticonComponent> get stickerRoomComponents {
    if (!isAccountLevel) return const [];
    var mx = client.getMatrixClient();
    return [
      for (var room in mx.rooms)
        if (room.membership == matrix.Membership.join && isStickerRoom(room))
          if (client.getRoom(room.id)?.getComponent<RoomEmoticonComponent>()
              case final c?)
            c,
    ];
  }

  @override
  Future<String> createStickerRoom(String name) async {
    var mx = client.getMatrixClient();
    var roomId = await mx.createRoom(
      name: name,
      topic: "Sticker and emoji packs, shared with everyone in this room. "
          "Vommet lists this room under Settings › Emoticons instead of "
          "your room list.",
      preset: matrix.CreateRoomPreset.privateChat,
      visibility: matrix.Visibility.private,
      initialState: [
        matrix.StateEvent(
            type: stickerRoomStateKey, stateKey: "", content: {"version": 1}),
      ],
    );

    if (mx.getRoomById(roomId) == null) {
      await mx.waitForRoomInSync(roomId, join: true);
    }

    // Other clients show the room normally; keep it out of the way there.
    try {
      await mx.getRoomById(roomId)?.addTag(matrix.TagType.lowPriority);
    } catch (e) {
      Log.w("Could not tag the sticker room low priority: $e");
    }

    return roomId;
  }

  @override
  Future<void> importIntoNewStickerRoom(String roomName, String name,
      int avatarIndex, List<String> names, List<Uint8List> imageDatas,
      {EmoticonUsage? usage}) async {
    var task = MatrixImportEmoticonPackTask(imageDatas, client);
    backgroundTaskManager.addTask(task);
    var uris = await task.uploadImages();

    var content = _packContent(name, uris, avatarIndex, names, usage);
    var roomId = await createStickerRoom(roomName);
    await _writeRoomPack(roomId, name, content);

    task.complete();
  }

  Future<void> _writeRoomPack(
      String roomId, String name, Map<String, dynamic> content) async {
    var mx = client.getMatrixClient();
    var packs = mx.getRoomById(roomId)?.states[roomEmotesStateKey] ?? {};
    var live = packs.entries
        .where((e) => e.value.content.isNotEmpty)
        .map((e) => e.key);
    var key = EmoticonNames.unique(name, live);

    await mx.setRoomStateWithKey(roomId, roomEmotesStateKey, key, content);
  }

  @override
  Future<void> deleteEmoticonPack(EmoticonPack pack) {
    var matrixPack = pack as MatrixEmoticonPack;
    return state.setState(matrixPack.stateKey, {});
  }

  @override
  List<EmoticonPack> everywherePacks() {
    var packs = globalPacks();
    for (var room in stickerRoomComponents) {
      packs.addAll(room.ownedPacks.where((p) => !packs.contains(p)));
    }
    return packs;
  }

  @override
  List<EmoticonPack> globalPacks() {
    var matrixClient = client.getMatrixClient();

    if (!matrixClient.accountData.containsKey(globalEmoteRoomsStateKey))
      return [];

    var rooms = matrixClient.accountData[globalEmoteRoomsStateKey]!
        .content['rooms'] as Map<String, Object?>;

    var packs = List<EmoticonPack>.empty(growable: true);

    for (var roomId in rooms.keys) {
      var room = client.getRoom(roomId);
      var space = client.getSpace(roomId);

      if (room == null && space == null) continue;
      if (rooms[roomId] is! Map<String, dynamic>) {
        continue;
      }

      var packKeys = rooms[roomId] as Map<String, dynamic>;

      for (var packKey in packKeys.keys) {
        List? emoji;

        if (room != null) {
          var component = room.getComponent<RoomEmoticonComponent>();
          if (component != null) {
            emoji = component.ownedPacks;
          }
        } else if (space != null) {
          var component = space.getComponent<SpaceEmoticonComponent>();
          if (component != null) {
            emoji = component.ownedPacks;
          }
        }

        if (emoji == null) continue;

        var matchingPacks =
            emoji.where((element) => element.identifier == packKey);

        if (matchingPacks.isEmpty) continue;

        packs.add(matchingPacks.first);
      }
    }

    return packs;
  }

  Future<void> deleteEmoticon(String packKey, String emoteName) async {
    var content = state.getState(packKey);

    if (content.containsKey('images')) {
      var images = content['images'] as Map<String, dynamic>;
      images.remove(emoteName);
      content['images'] = images;
    }

    return state.setState(packKey, content);
  }

  Future<void> setPackUsages(String packKey, List<String>? usages) async {
    var content = state.getState(packKey);

    var pack = content['pack'] as Map<String, dynamic>?;

    if (pack == null) return;

    pack['usage'] = usages?.isEmpty == true ? null : usages;
    content['pack'] = pack;

    return state.setState(packKey, content);
  }

  Future<void> updatePack(String packKey,
      {EmoticonUsage? usage, String? name, Uint8List? imageData}) async {
    var content = state.getState(packKey);

    if (usage != null) {
      content['pack']['usage'] = switch (usage) {
        EmoticonUsage.sticker => ["sticker"],
        EmoticonUsage.emoji => ["emoticon"],
        EmoticonUsage.all => ["emoticon", "sticker"],
        EmoticonUsage.inherit => null,
      };
    }

    if (name != null) {
      content['pack']['display_name'] = name;
    }

    if (imageData != null) {
      Uri url = await client.getMatrixClient().uploadContent(imageData);
      content['pack']['avatar_url'] = url.toString();
    }

    return state.setState(packKey, content);
  }

  Future<void> updateEmoticon(
    String packKey,
    String emoteName, {
    Uint8List? data,
    String? mimeType,
    EmoticonUsage? usage,
    required Emoticon previous,
  }) async {
    var content = state.getState(packKey);

    var emoteState = content['images'][previous.shortcode!];

    if (usage != null) {
      emoteState['usage'] = switch (usage) {
        EmoticonUsage.sticker => ["sticker"],
        EmoticonUsage.emoji => ["emoticon"],
        EmoticonUsage.all => ["emoticon", "sticker"],
        EmoticonUsage.inherit => null,
      };
    }

    if (data != null) {
      Uri url = await client.getMatrixClient().uploadContent(data);
      emoteState['url'] = url.toString();
    }

    var pack = {"pack": content['pack'], "images": {}};

    var keys = content['images'].keys.toList();

    // construct a new map this way, to keep ordering :O
    for (var key in keys) {
      if (key == previous.shortcode) {
        pack['images'][emoteName] = emoteState;
      } else {
        pack['images'][key] = content['images'][key];
      }
    }

    await state.setState(packKey, pack);
  }

  Future<Map<String, dynamic>>? createEmoticon(
    String packKey,
    String emoteName,
    Uint8List data,
  ) async {
    var content = state.getState(packKey);

    Uri url = await client.getMatrixClient().uploadContent(data);

    if (content['images'] == null) {
      content['images'] = {};
    }

    if (content['images'][emoteName] == null) {
      content['images'][emoteName] = {};
    }
    content['images'][emoteName]['url'] = url.toString();
    content['images'][emoteName]['display_name'] = emoteName;

    await state.setState(packKey, content);
    return content;
  }

  @override
  List<EmoticonPack> get availablePacks =>
      everywherePacks() + ownedPacks + UnicodeEmojis.packs!;

  Map<String, Map<String, String>> getEmotePacksFlat(
      matrix.ImagePackUsage emoticon) {
    var packs = everywherePacks() + ownedPacks;

    var result = <String, Map<String, String>>{};

    for (var pack in packs) {
      var key = "${pack.displayName}-${pack.hashCode}";
      result[key] = <String, String>{};
      for (var emote in pack.emotes) {
        result[key]![emote.shortcode!] =
            (emote as MatrixEmoticon).emojiUrl.toString();
      }
    }

    return result;
  }
}
