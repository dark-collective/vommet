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

/// Vommet issue 676: room account data holding the user's consent to
/// previews other people's apps bundle in this room: `{"allowed": bool}`,
/// true = "Everyone in this chat", false = "Never in this chat" (hidden).
const String bundledPreviewsConsentType = "im.vommet.bundled_url_previews";

/// Reads [bundledPreviewsConsentType]: null when the user never chose.
bool? bundledConsentFromContent(Map<String, Object?>? content) {
  final allowed = content?["allowed"];
  return allowed is bool ? allowed : null;
}

/// Whether bundled previews may show in a room at all: yes unless the user
/// turned previews off for it (or, in an unencrypted room where they never
/// chose, its admins did). Showing one sends the link nowhere, so the
/// encrypted-room default, which is about the homeserver, doesn't apply.
bool bundledPreviewsAllowed({
  required bool encrypted,
  bool? userChoice,
  bool? roomDefault,
}) {
  if (userChoice != null) return userChoice;
  if (!encrypted && roomDefault == false) return false;
  return true;
}

/// Whether a bundled preview shows straight away, asks first, or stays
/// hidden.
enum BundledPreviewDecision { show, ask, hide }

/// Vommet issue 676: the user's choice for one person's bundled previews.
enum BundledPreviewPersonTrust { always, never }

/// Global account data listing whose bundled previews always or never show:
/// `{"always": [userIds], "never": [userIds]}`.
const String bundledPreviewsPeopleType =
    "im.vommet.bundled_url_previews.people";

/// The Always and Never lists of [bundledPreviewsPeopleType].
class BundledPreviewPeople {
  const BundledPreviewPeople(
      {this.always = const <String>{}, this.never = const <String>{}});

  final Set<String> always;
  final Set<String> never;

  static const empty = BundledPreviewPeople();

  bool get isEmpty => always.isEmpty && never.isEmpty;

  static BundledPreviewPeople fromContent(Map<String, Object?>? content) {
    Set<String> ids(Object? value) => value is List
        ? value.whereType<String>().where((id) => id.isNotEmpty).toSet()
        : <String>{};
    return BundledPreviewPeople(
        always: ids(content?["always"]), never: ids(content?["never"]));
  }

  /// Never wins when someone is on both lists.
  BundledPreviewPersonTrust? trustOf(String userId) {
    if (never.contains(userId)) return BundledPreviewPersonTrust.never;
    if (always.contains(userId)) return BundledPreviewPersonTrust.always;
    return null;
  }

  /// The lists with [userId] moved to [trust] (off both when null).
  BundledPreviewPeople withTrust(
      String userId, BundledPreviewPersonTrust? trust) {
    final a = {...always}..remove(userId);
    final n = {...never}..remove(userId);
    if (trust == BundledPreviewPersonTrust.always) a.add(userId);
    if (trust == BundledPreviewPersonTrust.never) n.add(userId);
    return BundledPreviewPeople(always: a, never: n);
  }

  /// [previous] with both lists replaced (sorted), keeping other keys.
  Map<String, Object?> toContent([Map<String, Object?>? previous]) => {
        ...?previous,
        "always": always.toList()..sort(),
        "never": never.toList()..sort(),
      };

  bool sameAs(BundledPreviewPeople other) =>
      always.length == other.always.length &&
      never.length == other.never.length &&
      always.containsAll(other.always) &&
      never.containsAll(other.never);
}

/// Vommet issue 676: whose bundled previews show, in this order:
/// - your own: show;
/// - previews off in this chat ([chatPreviewsOff]) or "Never in this chat"
///   ([chatAllowed] false): hide;
/// - the sender is on the Never list: hide;
/// - the sender is on the Always list, or "Always show from people I've
///   verified" is on ([trustVerified]) and the message came encrypted from
///   one of the sender's cross-signed sessions while you verified them
///   ([fromVerifiedSession]): show;
/// - the chat is allowed: show;
/// - "Ask before showing" is off: show;
/// - the chat is unencrypted ([encrypted] false): show (Vommet issue 779;
///   the homeserver reads those messages anyway, so the card only got in
///   the way);
/// - otherwise ask.
BundledPreviewDecision resolveBundledPreview({
  required bool fromSelf,
  bool chatPreviewsOff = false,
  bool? chatAllowed,
  BundledPreviewPersonTrust? person,
  bool trustVerified = false,
  bool fromVerifiedSession = false,
  required bool askInNewChats,
  bool encrypted = true,
}) {
  if (fromSelf) return BundledPreviewDecision.show;
  if (chatPreviewsOff || chatAllowed == false) {
    return BundledPreviewDecision.hide;
  }
  if (person == BundledPreviewPersonTrust.never) {
    return BundledPreviewDecision.hide;
  }
  if (person == BundledPreviewPersonTrust.always ||
      (trustVerified && fromVerifiedSession)) {
    return BundledPreviewDecision.show;
  }
  if (chatAllowed == true || !askInNewChats || !encrypted) {
    return BundledPreviewDecision.show;
  }
  return BundledPreviewDecision.ask;
}

/// Vommet issue 676: in an unencrypted chat whose mode fetches homeserver
/// previews, the homeserver's preview wins and a bundled one is only the
/// fallback. Elsewhere (encrypted chats, Bundled only) bundled is all there
/// is.
bool homeserverPreviewFirst(
        {required bool encrypted, required UrlPreviewMode mode}) =>
    !encrypted && mode == UrlPreviewMode.all;

/// Vommet issue 676 phase 3: what a chat previews.
enum UrlPreviewMode {
  /// No previews at all.
  off,

  /// Only previews the sender's app bundled; no link goes anywhere.
  bundledOnly,

  /// Bundled previews, and homeserver previews for other links.
  all,
}

/// Stored names of the global default; "auto" = [automaticUrlPreviewMode].
const String urlPreviewModeAuto = "auto";

String urlPreviewModeName(UrlPreviewMode? mode) => switch (mode) {
      null => urlPreviewModeAuto,
      UrlPreviewMode.off => "off",
      UrlPreviewMode.bundledOnly => "bundled",
      UrlPreviewMode.all => "all",
    };

UrlPreviewMode? urlPreviewModeFromName(String? name) => switch (name) {
      "off" => UrlPreviewMode.off,
      "bundled" => UrlPreviewMode.bundledOnly,
      "all" => UrlPreviewMode.all,
      _ => null,
    };

/// The global default, null = Automatic. Before this setting existed, the
/// "URL previews in encrypted chats" switch on meant homeserver previews
/// everywhere, so it lands on [UrlPreviewMode.all].
UrlPreviewMode? globalUrlPreviewMode(
    {String? stored, required bool legacyEncryptedOn}) {
  if (stored != null) return urlPreviewModeFromName(stored);
  return legacyEncryptedOn ? UrlPreviewMode.all : null;
}

/// Automatic: bundled only in encrypted chats (the homeserver never learns
/// a link); in others homeserver previews too, unless the room's admins
/// turned previews off.
UrlPreviewMode automaticUrlPreviewMode(
    {required bool encrypted, bool? roomDefault}) {
  if (encrypted) return UrlPreviewMode.bundledOnly;
  return roomDefault == false ? UrlPreviewMode.off : UrlPreviewMode.all;
}

/// Room account data marking the user's "Bundled only" choice for a room;
/// Element's own key then says previews are off: `{"mode": "bundled"}`.
const String vommetUrlPreviewModeType = "im.vommet.url_previews";

/// The user's own mode for a room from Element's on/off choice
/// ([elementChoice]) and Vommet's marker ([vommetContent]). The marker only
/// counts while Element's choice is off, so choosing on or off in Element
/// still wins.
UrlPreviewMode? userUrlPreviewMode(
    {bool? elementChoice, Map<String, Object?>? vommetContent}) {
  if (elementChoice == null) return null;
  if (elementChoice) return UrlPreviewMode.all;
  return vommetContent?["mode"] == "bundled"
      ? UrlPreviewMode.bundledOnly
      : UrlPreviewMode.off;
}

/// What applies in a room: the user's choice for it, then the global
/// default, then Automatic.
UrlPreviewMode resolveUrlPreviewMode({
  required bool encrypted,
  UrlPreviewMode? userMode,
  bool? roomDefault,
  UrlPreviewMode? globalMode,
}) =>
    userMode ??
    globalMode ??
    automaticUrlPreviewMode(encrypted: encrypted, roomDefault: roomDefault);
