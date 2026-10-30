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

  /// Whether homeserver previews may be fetched here (Bundled + homeserver).
  bool get enabled => mode == UrlPreviewMode.all;

  /// Vommet issue 676: the user's own mode for this room; null = default.
  UrlPreviewMode? get userMode => userUrlPreviewMode(
      elementChoice: userChoice,
      vommetContent: room.roomAccountData[vommetUrlPreviewModeType]?.content);

  /// What applies when the user hasn't chosen for this room.
  UrlPreviewMode get defaultMode => resolveUrlPreviewMode(
      encrypted: encrypted,
      roomDefault: roomDefault,
      globalMode: globalUrlPreviewModeSetting);

  /// What applies in this room.
  UrlPreviewMode get mode => resolveUrlPreviewMode(
      encrypted: encrypted,
      userMode: userMode,
      roomDefault: roomDefault,
      globalMode: globalUrlPreviewModeSetting);

  /// Vommet issue 676: whether bundled previews may show here at all.
  bool get bundledAllowed => mode != UrlPreviewMode.off;

  /// Saves the user's mode for this room (null = follow the default).
  /// Element's on/off key carries on/off; "Bundled only" is off there plus
  /// Vommet's marker, so Element shows no homeserver previews either.
  Future<void> setUserMode(UrlPreviewMode? mode) async {
    final bundled = mode == UrlPreviewMode.bundledOnly;
    final marked =
        room.roomAccountData[vommetUrlPreviewModeType]?.content["mode"] ==
            "bundled";
    if (bundled != marked) {
      await room.client.setAccountDataPerRoom(room.client.userID!, room.id,
          vommetUrlPreviewModeType, bundled ? {"mode": "bundled"} : {});
    }
    await setUserChoice(mode == null ? null : mode == UrlPreviewMode.all);
  }

  /// The user's consent to others' bundled previews here; null = never chose.
  bool? get bundledConsent => bundledConsentFromContent(
      room.roomAccountData[bundledPreviewsConsentType]?.content);

  /// "Everyone in this chat" (true), "Never in this chat" (false), or ask
  /// again (null).
  Future<void> setBundledConsent(bool? allowed) =>
      room.client.setAccountDataPerRoom(
          room.client.userID!,
          room.id,
          bundledPreviewsConsentType,
          allowed == null ? {} : {"allowed": allowed});

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

/// Vommet issue 676: the global link preview default; null = Automatic.
UrlPreviewMode? get globalUrlPreviewModeSetting => globalUrlPreviewMode(
    stored: preferences.urlPreviewMode.value,
    legacyEncryptedOn: preferences.urlPreviewInE2EEChat.value);

/// Whether homeserver link previews may be fetched in [room], honouring its
/// settings.
bool urlPreviewsAllowedIn(Room room) {
  if (room is MatrixRoom) return MatrixRoomUrlPreviews(room.matrixRoom).enabled;
  return resolveUrlPreviewMode(
          encrypted: room.isE2EE, globalMode: globalUrlPreviewModeSetting) ==
      UrlPreviewMode.all;
}

/// Vommet issue 676: whether bundled previews may show in [room].
bool bundledUrlPreviewsAllowedIn(Room room) {
  if (room is MatrixRoom) {
    return MatrixRoomUrlPreviews(room.matrixRoom).bundledAllowed;
  }
  return true;
}
