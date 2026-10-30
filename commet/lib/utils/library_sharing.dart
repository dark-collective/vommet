// Vommet issue 731, phase 2: sharing a collection (a sticker room and its
// packs). The pure parts: the permission map for each sharing mode, the
// mode a room is in, links to follow a collection, and which packs changed
// since you last looked.
import 'package:commet/client/matrix/components/emoticon/image_pack_types.dart';

/// How a collection is shared.
enum CollectionMode {
  /// Only you and the people you invite. Join rule `invite`.
  private("private"),

  /// Anyone with the link can follow it and gets your edits live; only you
  /// edit. Join rule `public`.
  followers("followers"),

  /// Like [followers], plus contributors (power level 50) edit its packs.
  /// Join rule `public` or `invite`.
  community("community");

  const CollectionMode(this.id);

  final String id;

  static CollectionMode? fromId(Object? id) =>
      values.where((m) => m.id == id).firstOrNull;
}

/// A collection to follow, from a pasted link, alias or room id.
class PackRoomLink {
  const PackRoomLink(this.idOrAlias, {this.via = const []});

  final String idOrAlias;
  final List<String> via;

  bool get isAlias => idOrAlias.startsWith("#");
}

class LibrarySharing {
  /// State (key "") holding the chosen mode: `{"mode": "<id>"}`. Admins
  /// only ([ImagePackTypes.packRoomPowerLevels] puts it at 100).
  static const modeType = "im.vommet.collection_mode";

  /// Account data: room id → pack state key → id of the pack event you
  /// last saw.
  static const seenType = "im.vommet.library_seen";

  /// The level of contributors in a community collection.
  static const contributorLevel = 50;
  static const adminLevel = 100;

  /// The mode stored in [modeContent]; without one, derived from the room:
  /// a public room is followed (or a community if anyone is at the
  /// contributor level), anything else is private.
  static CollectionMode modeOf(
      {Map<String, dynamic>? modeContent,
      String? joinRule,
      Map<String, dynamic>? powerLevels}) {
    final stored = CollectionMode.fromId(modeContent?["mode"]);
    if (stored != null) return stored;
    if (joinRule != "public") return CollectionMode.private;
    return contributorsOf(powerLevels).isNotEmpty
        ? CollectionMode.community
        : CollectionMode.followers;
  }

  /// The join rule of [mode]; [anyoneCanFollow] picks it for a community.
  static String joinRuleFor(CollectionMode mode,
          {bool anyoneCanFollow = true}) =>
      switch (mode) {
        CollectionMode.private => "invite",
        CollectionMode.followers => "public",
        CollectionMode.community => anyoneCanFollow ? "public" : "invite",
      };

  static Map<String, int> _users(Map<String, dynamic>? powerLevels) {
    final users = powerLevels?["users"];
    if (users is! Map) return {};
    return {
      for (final e in users.entries)
        if (e.key is String && e.value is int) e.key as String: e.value as int,
    };
  }

  /// Users at exactly the contributor level.
  static Set<String> contributorsOf(Map<String, dynamic>? powerLevels) => {
        for (final e in _users(powerLevels).entries)
          if (e.value == contributorLevel) e.key,
      };

  /// Users who may change the room: at 100 or above, plus the [creators]
  /// in a room where creators always rank highest (version 12 on).
  static Set<String> adminsOf(Map<String, dynamic>? powerLevels,
          {Set<String> creators = const {},
          bool creatorsRankHighest = false}) =>
      {
        for (final e in _users(powerLevels).entries)
          if (e.value >= adminLevel) e.key,
        if (creatorsRankHighest) ...creators,
        // Without a power levels event the creator is the admin.
        if (powerLevels == null) ...creators,
      };

  /// Whether [me] is the only admin while others are among the
  /// [joinedCount] members.
  static bool isOnlyAdmin(String me, Set<String> admins, int joinedCount) =>
      admins.length == 1 && admins.contains(me) && joinedCount > 1;

  /// Whether creators always rank highest (and so must stay out of
  /// `users`): room version 12 and later.
  static bool creatorsRankHighest(String? roomVersion) =>
      (int.tryParse(roomVersion ?? "") ?? 0) >= 12;

  /// The power levels for [mode], from the room's [current] ones: the
  /// pack-room map is forced (packs at 50, everything else at 100),
  /// everyone else starts at 0, and in a [CollectionMode.community]
  /// exactly the [contributors] are at 50. Other modes drop everyone at
  /// 50. Admins (100 and up) are never touched; in rooms where
  /// [creatorsRankHighest], the [creators] are kept out of `users`.
  static Map<String, dynamic> powerLevelsFor(
      {required Map<String, dynamic> current,
      required String markerType,
      required CollectionMode mode,
      Iterable<String> contributors = const [],
      Set<String> creators = const {},
      bool creatorsRankHighest = false}) {
    final map = ImagePackTypes.packRoomPowerLevels(markerType);
    final events = current["events"];
    final users = _users(current)
      ..removeWhere((_, level) => level == contributorLevel);
    if (creatorsRankHighest) users.removeWhere((u, _) => creators.contains(u));
    if (mode == CollectionMode.community) {
      for (final c in contributors) {
        if (creatorsRankHighest && creators.contains(c)) continue;
        if ((users[c] ?? 0) < contributorLevel) users[c] = contributorLevel;
      }
    }
    return {
      ...current,
      "events_default": map["events_default"],
      "redact": map["redact"],
      "users_default": 0,
      "events": {
        if (events is Map) ...events,
        ...(map["events"] as Map),
      },
      "users": users,
    };
  }

  /// A matrix.to link to [idOrAlias]; room ids get [via] servers.
  static String matrixToLink(String idOrAlias, {List<String> via = const []}) {
    final query = idOrAlias.startsWith("!") && via.isNotEmpty
        ? "?${via.map((s) => "via=${Uri.encodeQueryComponent(s)}").join("&")}"
        : "";
    return "https://matrix.to/#/$idOrAlias$query";
  }

  /// A collection from a pasted matrix.to link, `matrix:` URI,
  /// `#alias:server` or `!roomid` (each with optional `?via=`). Null when
  /// [input] is none of these.
  static PackRoomLink? parseLink(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;

    String? id;
    var query = "";
    const matrixTo = ["https://matrix.to/#/", "http://matrix.to/#/"];
    final prefix = matrixTo.where(text.startsWith).firstOrNull;
    if (prefix != null) {
      text = text.substring(prefix.length);
      final q = text.indexOf("?");
      if (q >= 0) {
        query = text.substring(q + 1);
        text = text.substring(0, q);
      }
      // A link to an event in the room: keep the room part.
      final slash = text.indexOf("/");
      if (slash >= 0) text = text.substring(0, slash);
      id = Uri.decodeComponent(text);
    } else if (text.startsWith("matrix:")) {
      final uri = Uri.tryParse(text);
      if (uri == null) return null;
      final parts = uri.path.split("/");
      if (parts.length < 2) return null;
      final sigil = switch (parts[0]) {
        "r" => "#",
        "roomid" => "!",
        _ => null,
      };
      if (sigil == null) return null;
      id = "$sigil${Uri.decodeComponent(parts[1])}";
      query = uri.query;
    } else {
      final q = text.indexOf("?");
      if (q >= 0) {
        query = text.substring(q + 1);
        text = text.substring(0, q);
      }
      id = text;
    }

    if (!_validId(id)) return null;
    final via = <String>[];
    for (final part in query.split("&")) {
      final eq = part.indexOf("=");
      if (eq < 0 || part.substring(0, eq) != "via") continue;
      final server = Uri.decodeQueryComponent(part.substring(eq + 1)).trim();
      if (server.isNotEmpty && !via.contains(server)) via.add(server);
    }
    // A room id's own server is a good place to join through.
    if (id.startsWith("!") && via.isEmpty) {
      final colon = id.indexOf(":");
      if (colon > 0) via.add(id.substring(colon + 1));
    }
    return PackRoomLink(id, via: via);
  }

  static bool _validId(String id) {
    if (id.length < 2 || id.contains(RegExp(r"\s"))) return false;
    // Aliases always name their server; room ids from version 12 on don't.
    if (id.startsWith("#")) {
      final colon = id.indexOf(":");
      return colon > 1 && colon < id.length - 1;
    }
    return id.startsWith("!");
  }

  // Changed since you last looked.

  static String? seenEventId(
      Map<String, dynamic> seen, String roomId, String stateKey) {
    final room = seen[roomId];
    if (room is! Map) return null;
    final id = room[stateKey];
    return id is String ? id : null;
  }

  /// Whether the pack [stateKey] in [roomId] changed since you last saw
  /// it: its current event [eventId] isn't the one you saw. A room you
  /// never looked at counts as seen (it is noted on first sight instead),
  /// and so does a pack [me] edited last.
  static bool isChanged(
      Map<String, dynamic> seen, String roomId, String stateKey,
      {required String? eventId, required String? sender, required String me}) {
    if (eventId == null || sender == me) return false;
    if (seen[roomId] is! Map) return false;
    return seenEventId(seen, roomId, stateKey) != eventId;
  }

  /// [seen] with the given packs of [roomId] marked seen (pack state key →
  /// event id); null when nothing changes, so nothing needs writing.
  static Map<String, dynamic>? markSeen(
      Map<String, dynamic> seen, String roomId, Map<String, String> events) {
    final room = seen[roomId];
    final current = <String, dynamic>{if (room is Map) ...room};
    var changed = room is! Map;
    for (final e in events.entries) {
      if (current[e.key] != e.value) {
        current[e.key] = e.value;
        changed = true;
      }
    }
    if (!changed) return null;
    return {...seen, roomId: current};
  }

  /// [seen] without rooms outside [keep]; null when nothing changes.
  static Map<String, dynamic>? forgetRooms(
      Map<String, dynamic> seen, Set<String> keep) {
    if (seen.keys.every(keep.contains)) return null;
    return {
      for (final e in seen.entries)
        if (keep.contains(e.key)) e.key: e.value,
    };
  }
}
