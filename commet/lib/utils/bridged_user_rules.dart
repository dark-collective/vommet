// Vommet issue 853: which users are bridged "ghosts" (puppets of people on
// another network), and how sure we are. Plain Dart so it can be unit tested;
// the preferences, profile lookups and strings live in bridged_users.dart.
import 'package:commet/utils/bridged_trust_rules.dart';

export 'package:commet/utils/bridged_trust_rules.dart';

enum BridgeNetwork {
  telegram,
  discord,
  whatsapp,
  signal,
  voiceBridge,
  irc,
  other
}

/// Where the answer comes from.
enum BridgeSource {
  /// The bridge put it on the user's profile (com.beeper.bridge.*).
  declared,

  /// Guessed from the user ID.
  guessed,

  /// The user set it for this person.
  yours,
}

/// Whether a direct message reaches a person.
enum BridgeDmReach {
  /// It does (a bridge the user marked "DMs reach them").
  reaches,

  /// Only if they linked their account on the other network.
  mayNot,

  /// Nobody reads it (a voice bridge puppet).
  nobody,
}

class BuiltInBridge {
  BuiltInBridge(this.id, this.network, this.localparts);

  /// Stored in the "networks without icons" preference (it used to turn
  /// off the guess).
  final String id;
  final BridgeNetwork network;

  /// Strict: a known prefix followed by an ID-like rest, so that a person who
  /// just picked "telegram_fan" as a name doesn't match.
  final List<RegExp> localparts;

  bool matches(String localpart) =>
      localparts.any((r) => r.hasMatch(localpart));
}

final List<BuiltInBridge> builtInBridges = [
  BuiltInBridge(
      "mautrix-telegram", BridgeNetwork.telegram, [RegExp(r"^telegram_\d+$")]),
  BuiltInBridge("mautrix-discord", BridgeNetwork.discord,
      [RegExp(r"^discord_\d+$"), RegExp(r"^_discord_\d+$")]),
  BuiltInBridge("nether-voicebridge", BridgeNetwork.voiceBridge,
      [RegExp(r"^nether-voicebridge_[a-z0-9._=\-]+$")]),
  BuiltInBridge(
      "mautrix-whatsapp", BridgeNetwork.whatsapp, [RegExp(r"^whatsapp_\d+$")]),
  BuiltInBridge("mautrix-signal", BridgeNetwork.signal, [
    RegExp(
        r"^signal_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
  ]),
  BuiltInBridge("irc", BridgeNetwork.irc, [RegExp(r"^irc_[a-z0-9._=\-]+$")]),
];

/// A trusted bridge server the user added: people on [server] whose ID
/// matches [pattern] (or, with no pattern, the usual IDs for [network]) are
/// bridged from [network]. Older entries are a full-ID glob such as
/// `@irc_*:example.org` with no separate server.
class UserBridgePattern {
  const UserBridgePattern(this.pattern, this.network,
      {this.dmsReach = false, this.server});

  /// A glob: a full user ID (`@irc_*:example.org`) or a localpart
  /// (`@signal_*`, `signal_*`). Empty for the network's usual IDs.
  final String pattern;
  final BridgeNetwork network;

  /// Hides the "they only see this if…" banner for this bridge.
  final bool dmsReach;

  final String? server;

  /// [server], or the one spelled out in an older full-ID [pattern].
  String? get serverName {
    if (server != null && server!.isNotEmpty) return server;
    final colon = pattern.indexOf(":");
    if (colon < 0) return null;
    final rest = pattern.substring(colon + 1);
    return rest.isEmpty || rest.contains("*") || rest.contains("?")
        ? null
        : rest;
  }

  static UserBridgePattern? decode(String stored) {
    final parts = stored.split("\t");
    if (parts.length < 2) return null;
    final server = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
    if (parts[0].isEmpty && server == null) return null;
    final network = networkFromName(parts[1]) ?? BridgeNetwork.other;
    return UserBridgePattern(parts[0], network,
        dmsReach: parts.length > 2 && parts[2] == "1", server: server);
  }

  String encode() => server == null
      ? "$pattern\t${network.name}\t${dmsReach ? 1 : 0}"
      : "$pattern\t${network.name}\t${dmsReach ? 1 : 0}\t$server";

  /// `*` is any run of characters, `?` one character; case-insensitive, and
  /// the whole user ID (or localpart) has to match.
  bool matches(String userId) {
    if (server != null && serverOfUserId(userId) != server!.toLowerCase()) {
      return false;
    }
    if (pattern.isEmpty) {
      final localpart = localpartOf(userId);
      if (localpart == null) return false;
      return builtInBridges
          .where((b) => b.network == network)
          .any((b) => b.matches(localpart));
    }
    if (pattern.contains(":")) return _glob(pattern).hasMatch(userId);
    final localpart = localpartOf(userId);
    if (localpart == null) return false;
    final glob =
        _glob(pattern.startsWith("@") ? pattern.substring(1) : pattern);
    return glob.hasMatch(localpart);
  }

  static RegExp _glob(String pattern) {
    final buffer = StringBuffer("^");
    for (final ch in pattern.split("")) {
      if (ch == "*") {
        buffer.write(".*");
      } else if (ch == "?") {
        buffer.write(".");
      } else {
        buffer.write(RegExp.escape(ch));
      }
    }
    buffer.write(r"$");
    return RegExp(buffer.toString(), caseSensitive: false);
  }
}

/// What a bridge wrote on the user's profile (MSC4133 extended profile,
/// `com.beeper.bridge.service` / `com.beeper.bridge.network`).
class DeclaredBridge {
  const DeclaredBridge({this.service, this.network});

  final String? service;
  final String? network;

  static DeclaredBridge? fromProfile(Map<String, Object?> profile) {
    final service = profile["com.beeper.bridge.service"];
    final network = profile["com.beeper.bridge.network"];
    if (service is! String && network is! String) return null;
    return DeclaredBridge(
        service: service is String ? service : null,
        network: network is String ? network : null);
  }

  BridgeNetwork get bridgeNetwork {
    for (final value in [network, service]) {
      if (value == null) continue;
      final known = networkFromName(value);
      if (known != null) return known;
    }
    return BridgeNetwork.other;
  }

  /// Shown when the network isn't one Vommet knows by name.
  String? get name => network ?? service;
}

class BridgedUser {
  const BridgedUser(this.network, this.source,
      {this.dms = BridgeDmReach.mayNot,
      this.networkName,
      this.verified = false,
      this.server});

  final BridgeNetwork network;
  final BridgeSource source;
  final BridgeDmReach dms;

  /// The bridge's own name for an [BridgeNetwork.other] network.
  final String? networkName;

  /// Their server is known to run this bridge, or the user said so (see
  /// bridged_trust_rules.dart). Otherwise their ID only looks bridged.
  final bool verified;

  /// The person's server.
  final String? server;

  bool get isGuess => source == BridgeSource.guessed;
}

/// Lenient: matches "telegram", "Telegram", "mautrix-telegram", "voiceBridge".
BridgeNetwork? networkFromName(String name) {
  final lower = name.toLowerCase();
  for (final n in BridgeNetwork.values) {
    if (lower == n.name.toLowerCase()) return n;
  }
  // "discord-voice" is the voice bridge's m.bridge protocol id; check it
  // before the plain "discord" substring below.
  if (lower.contains("voicebridge") ||
      lower.contains("voice-bridge") ||
      lower == "discord-voice") {
    return BridgeNetwork.voiceBridge;
  }
  for (final n in [
    BridgeNetwork.telegram,
    BridgeNetwork.discord,
    BridgeNetwork.whatsapp,
    BridgeNetwork.signal,
    BridgeNetwork.irc,
  ]) {
    if (lower.contains(n.name)) return n;
  }
  return null;
}

String? localpartOf(String userId) {
  if (!userId.startsWith("@")) return null;
  final colon = userId.indexOf(":");
  if (colon < 2) return null;
  return userId.substring(1, colon).toLowerCase();
}

/// The server part of a user ID, lowercased.
String? serverOfUserId(String userId) {
  if (!userId.startsWith("@")) return null;
  final colon = userId.indexOf(":");
  if (colon < 2 || colon == userId.length - 1) return null;
  return userId.substring(colon + 1).toLowerCase();
}

BridgeDmReach _reachOf(BridgeNetwork network) =>
    network == BridgeNetwork.voiceBridge
        ? BridgeDmReach.nobody
        : BridgeDmReach.mayNot;

/// The override value meaning "not a bridged user".
const String notBridgedOverride = "none";

/// Decides who is bridged, and whether it's verified. In order: what the
/// user set for this person, the user's trusted servers, the built-in
/// trusted servers, what the profile declares, then the built-in ID
/// patterns. A declaration or an ID guess is verified only when [trust]
/// trusts the person's server for that network, or [room] (the bridges
/// listed in the room the person is shown in) has a bridge on their server.
BridgedUser? classifyBridgedUser(
  String userId, {
  String? override,
  DeclaredBridge? declared,
  List<UserBridgePattern> patterns = const [],
  BridgeTrust trust = const BridgeTrust(),
  Iterable<SeenBridge> room = const [],
}) {
  final server = serverOfUserId(userId);
  if (override != null) {
    if (override == notBridgedOverride) return null;
    final network = networkFromName(override) ?? BridgeNetwork.other;
    return BridgedUser(network, BridgeSource.yours,
        dms: _reachOf(network), verified: true, server: server);
  }

  for (final p in patterns) {
    if (p.matches(userId)) {
      return BridgedUser(p.network, BridgeSource.yours,
          dms: p.dmsReach ? BridgeDmReach.reaches : _reachOf(p.network),
          verified: true,
          server: server);
    }
  }

  final trusted = trust.builtInFor(userId);
  if (trusted != null) {
    return BridgedUser(trusted.network, BridgeSource.guessed,
        dms: _reachOf(trusted.network), verified: true, server: server);
  }

  bool verified(BridgeNetwork network) =>
      server != null && trust.trusts(server, network, room: room);

  if (declared != null) {
    final network = declared.bridgeNetwork;
    return BridgedUser(network, BridgeSource.declared,
        dms: _reachOf(network),
        networkName: network == BridgeNetwork.other ? declared.name : null,
        verified: verified(network),
        server: server);
  }

  final localpart = localpartOf(userId);
  if (localpart == null) return null;
  for (final b in builtInBridges) {
    if (b.matches(localpart)) {
      return BridgedUser(b.network, BridgeSource.guessed,
          dms: _reachOf(b.network),
          verified: verified(b.network),
          server: server);
    }
  }
  return null;
}

/// The built-in bridge a user ID would be guessed as, ignoring settings.
BuiltInBridge? builtInBridgeFor(String userId) {
  final localpart = localpartOf(userId);
  if (localpart == null) return null;
  for (final b in builtInBridges) {
    if (b.matches(localpart)) return b;
  }
  return null;
}
