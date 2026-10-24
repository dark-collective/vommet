// Vommet: per-room URL preview settings, read the way Element reads them so
// a choice made in either client applies in both.
//
// - Room default (admins): state event `org.matrix.room.preview_urls`
//   `{"disable": bool}`. Only applies to unencrypted rooms.
// - The user's own choice for one room: room account data
//   `org.matrix.room.preview_urls` `{"disable": bool}` in an unencrypted
//   room; in an encrypted room `im.vector.web.settings`
//   `{"urlPreviewsEnabled_e2ee": bool}` (Element keeps the two apart, since a
//   preview sends the link to the homeserver).
// - Otherwise: on in unencrypted rooms, the app-wide "URL previews in
//   encrypted chats" preference (off by default) in encrypted ones.

/// Event type of the room default (state) and of the user's own choice in an
/// unencrypted room (room account data).
const String roomPreviewUrlsType = "org.matrix.room.preview_urls";

/// Room account data holding the user's choice in an encrypted room.
const String webSettingsType = "im.vector.web.settings";

/// Key inside [webSettingsType] for an encrypted room.
const String urlPreviewsE2eeKey = "urlPreviewsEnabled_e2ee";

/// Reads `{"disable": bool}`: true when previews are on, null when unset.
bool? previewsEnabledFromContent(Map<String, Object?>? content) {
  final disable = content?["disable"];
  return disable is bool ? !disable : null;
}

/// Reads the encrypted-room choice from `im.vector.web.settings`.
bool? previewsEnabledFromWebSettings(Map<String, Object?>? content) {
  final value = content?[urlPreviewsE2eeKey];
  return value is bool ? value : null;
}

/// `im.vector.web.settings` with the encrypted-room choice set to [enabled]
/// (removed when null), keeping every other key.
Map<String, Object?> webSettingsWithPreviews(
    Map<String, Object?>? content, bool? enabled) {
  final result = Map<String, Object?>.from(content ?? const {});
  if (enabled == null) {
    result.remove(urlPreviewsE2eeKey);
  } else {
    result[urlPreviewsE2eeKey] = enabled;
  }
  return result;
}

/// Whether link previews show in a room: the user's own choice for it, then
/// (unencrypted rooms only) the room default, then the app-wide fallback.
bool resolveRoomUrlPreviews({
  required bool encrypted,
  bool? userChoice,
  bool? roomDefault,
  required bool encryptedGlobal,
}) {
  if (userChoice != null) return userChoice;
  if (encrypted) return encryptedGlobal;
  return roomDefault ?? true;
}
