import 'package:commet/client/components/url_preview/url_preview_room_policy.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: a Matrix room's URL preview settings (see
/// `url_preview_room_policy.dart` for where each one is stored).
class MatrixRoomUrlPreviews {
  MatrixRoomUrlPreviews(this.room);

  final matrix.Room room;

  bool get encrypted => room.encrypted;

  /// The admins' default for members; null when the room never set one.
  bool? get roomDefault =>
      previewsEnabledFromContent(room.getState(roomPreviewUrlsType)?.content);

  bool get canChangeRoomDefault =>
      room.membership == matrix.Membership.join &&
      room.canChangeStateEvent(roomPreviewUrlsType);

  /// The user's own choice for this room; null = follow the default.
  bool? get userChoice => encrypted
      ? previewsEnabledFromWebSettings(
          room.roomAccountData[webSettingsType]?.content)
      : previewsEnabledFromContent(
          room.roomAccountData[roomPreviewUrlsType]?.content);

  /// What applies when the user hasn't chosen for this room.
  bool get defaultEnabled => resolveRoomUrlPreviews(
      encrypted: encrypted,
      roomDefault: roomDefault,
      encryptedGlobal: preferences.urlPreviewInE2EEChat.value);

  bool get enabled => resolveRoomUrlPreviews(
      encrypted: encrypted,
      userChoice: userChoice,
      roomDefault: roomDefault,
      encryptedGlobal: preferences.urlPreviewInE2EEChat.value);

  /// Vommet issue 676: whether bundled previews may show here at all.
  bool get bundledAllowed => bundledPreviewsAllowed(
      encrypted: encrypted, userChoice: userChoice, roomDefault: roomDefault);

  /// The user's consent to others' bundled previews here; null = never chose.
  bool? get bundledConsent => bundledConsentFromContent(
      room.roomAccountData[bundledPreviewsConsentType]?.content);

  Future<void> setBundledConsent(bool allowed) =>
      room.client.setAccountDataPerRoom(room.client.userID!, room.id,
          bundledPreviewsConsentType, {"allowed": allowed});

  Future<void> setRoomDefault(bool enabled) => room.client.setRoomStateWithKey(
      room.id, roomPreviewUrlsType, "", {"disable": !enabled});

  Future<void> setUserChoice(bool? enabled) {
    final userId = room.client.userID!;
    if (encrypted) {
      return room.client.setAccountDataPerRoom(
          userId,
          room.id,
          webSettingsType,
          webSettingsWithPreviews(
              room.roomAccountData[webSettingsType]?.content, enabled));
    }
    return room.client.setAccountDataPerRoom(userId, room.id,
        roomPreviewUrlsType, enabled == null ? {} : {"disable": !enabled});
  }
}

/// Whether link previews may show in [room], honouring its settings.
bool urlPreviewsAllowedIn(Room room) {
  if (room is MatrixRoom) return MatrixRoomUrlPreviews(room.matrixRoom).enabled;
  return !(room.isE2EE && preferences.urlPreviewInE2EEChat.value == false);
}

/// Vommet issue 676: whether bundled previews may show in [room].
bool bundledUrlPreviewsAllowedIn(Room room) {
  if (room is MatrixRoom) {
    return MatrixRoomUrlPreviews(room.matrixRoom).bundledAllowed;
  }
  return true;
}
