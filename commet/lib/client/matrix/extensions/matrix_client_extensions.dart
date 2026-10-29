import 'package:commet/client/client.dart' as commet;
import 'package:commet/client/matrix/components/emoticon/image_pack_types.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_room_type.dart';
import 'package:commet/client/room_preview.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/fixed_model.dart';

extension MatrixExtensions on Client {
  Future<FileResponse> getContentFromUri(Uri uri) {
    return getContent(uri.authority, uri.pathSegments.first);
  }

  Future<FileResponse> getContentThumbnailFromUri(
      Uri uri, int width, int height,
      {Method? method}) {
    return getContentThumbnail(
        uri.authority, uri.pathSegments.first, width, height,
        method: method);
  }

  Future<RoomPreview?> getRoomPreview(String roomId,
      {List<String>? via}) async {
    var result = await request(RequestType.GET,
        "/client/unstable/im.nheko.summary/rooms/${Uri.encodeComponent(roomId)}/summary",
        query: {
          if (via != null) "via": via.join(","),
        });

    var name = result["name"] as String?;
    var id = result["room_id"] as String?;
    var avatar = result["avatar_url"] as String?;
    var topic = result["topic"] as String?;
    var numMembers = result["num_joined_members"] as int?;
    var joinRule = result["join_rule"] as String?;

    var type = matrixRoomType(result["room_type"] as String?);

    var visibility = switch (joinRule) {
      "public" => commet.RoomVisibilityPublic(),
      // Vommet: knock rooms preview as "Ask to join".
      "knock" || "knock_restricted" => commet.RoomVisibilityKnock([]),
      "invite" => commet.RoomVisibilityPrivate(),
      "private" => commet.RoomVisibilityPrivate(),
      "restricted" => commet.RoomVisibilityRestricted([]),
      _ => commet.RoomVisibilityPrivate(),
    };

    if (name != null && id != null) {
      ImageProvider? image;
      if (avatar != null) {
        var mxc = Uri.parse(avatar);
        image = MatrixMxcImage(mxc, autoLoadFullRes: false, this);
      }

      return GenericRoomPreview(id,
          displayName: name,
          type: type,
          avatar: image,
          numMembers: numMembers,
          visibility: visibility,
          topic: topic);
    }

    return null;
  }

  /// Vommet issue 731: the packs turned on everywhere, from both enable
  /// lists (the spec's `m.image_pack.rooms` and the old
  /// `im.ponies.emote_rooms`): room id → pack state keys.
  Map<String, Set<String>> get enabledImagePackRooms =>
      ImagePackTypes.mergeEnabledRooms(
          accountData[ImagePackTypes.enabledRooms]?.content,
          accountData[ImagePackTypes.legacyEnabledRooms]?.content);

  Future<void> addEmoticonRoomPack(String roomId, String packKey) =>
      _setEnabledImagePack(roomId, packKey, true);

  Future<void> removeEmoticonRoomPack(String roomId, String packKey) =>
      _setEnabledImagePack(roomId, packKey, false);

  /// Vommet issue 731: turns several packs of [roomId] on or off in one
  /// write (each write reads the lists as last synced, so one call per pack
  /// in a row would undo the earlier ones).
  Future<void> setEmoticonRoomPacks(String roomId, Iterable<String> packKeys,
          {required bool enabled}) =>
      _setEnabledImagePacks(roomId, packKeys, enabled);

  Future<void> _setEnabledImagePack(
          String roomId, String packKey, bool enabled) =>
      _setEnabledImagePacks(roomId, [packKey], enabled);

  /// Writes the merged list to both account-data types, so a pack turned
  /// off stays off in clients reading either one.
  Future<void> _setEnabledImagePacks(
      String roomId, Iterable<String> packKeys, bool enabled) async {
    var rooms = enabledImagePackRooms;
    if (enabled) {
      rooms.putIfAbsent(roomId, () => {}).addAll(packKeys);
    } else {
      rooms[roomId]?.removeAll(packKeys);
    }
    var content = ImagePackTypes.enabledRoomsContent(rooms);
    for (var type in ImagePackTypes.enabledRoomsTypes) {
      await setAccountData(userID!, type, content);
    }
  }

  bool isEmoticonPackGloballyAvailable(String roomId, String packKey) =>
      enabledImagePackRooms[roomId]?.contains(packKey) ?? false;

  // This is stupid, is there a better way to do this?
  Future<bool> isRoomAliasAvailable(String alias) async {
    try {
      await request(
        RequestType.GET,
        '/client/v3/directory/room/${Uri.encodeComponent(alias)}',
      );
      return false;
    } catch (exception) {
      if (exception is MatrixException) {
        if (exception.error == MatrixError.M_NOT_FOUND) {
          return true;
        }
      }
      return false;
    }
  }
}
