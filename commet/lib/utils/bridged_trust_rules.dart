// Vommet: when a bridge mark is "verified". An ID that looks bridged proves
// nothing by itself (anyone can register @telegram_123 on their own server),
// so a mark is only trusted when the person's server is known to run that
// bridge. Plain Dart so it can be unit tested; bridged_users.dart feeds it the
// settings and the bridges seen in room state.
import 'package:commet/utils/bridged_user_rules.dart';

/// A server known to run a bridge, for user IDs matching [localparts] only:
/// these servers also host normal users.
class TrustedBridgeServer {
  TrustedBridgeServer(this.id, this.server, this.network, this.localparts);

  /// Stored in the "trusted servers you turned off" preference.
  final String id;
  final String server;
  final BridgeNetwork network;
  final List<RegExp> localparts;

  bool matches(String userId) {
    if (serverOfUserId(userId) != server) return false;
    final localpart = localpartOf(userId);
    return localpart != null && localparts.any((r) => r.hasMatch(localpart));
  }
}

final List<TrustedBridgeServer> builtInTrustedServers = [
  TrustedBridgeServer("t2bot-telegram", "t2bot.io", BridgeNetwork.telegram,
      [RegExp(r"^telegram_\d+$")]),
  TrustedBridgeServer("t2bot-discord", "t2bot.io", BridgeNetwork.discord,
      [RegExp(r"^_discord_\d+$")]),
  TrustedBridgeServer("matrix-org-oftc", "matrix.org", BridgeNetwork.irc,
      [RegExp(r"^_oftc_.+$")]),
  // Listed on docs.mau.fi as public mautrix bridges.
  TrustedBridgeServer("tchncs-telegram", "tchncs.de", BridgeNetwork.telegram,
      [RegExp(r"^telegram_\d+$")]),
  TrustedBridgeServer("tchncs-whatsapp", "tchncs.de", BridgeNetwork.whatsapp,
      [RegExp(r"^whatsapp_(lid-)?\d+$")]),
  TrustedBridgeServer("tchncs-signal", "tchncs.de", BridgeNetwork.signal, [
    RegExp(
        r"^signal_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
  ]),
  // Nether's own voice bridge, for rooms where its bot can't post m.bridge.
  TrustedBridgeServer(
      "nether-voicebridge",
      "nether.im",
      BridgeNetwork.voiceBridge,
      [RegExp(r"^nether-voicebridge_[a-z0-9._=\-]+$")]),
];

/// A bridge listed in a room's state (`m.bridge` / `uk.half-shot.bridge`):
/// the server its bot is on and the network it bridges.
class SeenBridge {
  const SeenBridge(this.server, this.network);

  final String server;
  final BridgeNetwork network;

  /// Null when the event names no bot or a protocol Vommet doesn't know.
  static SeenBridge? from({String? protocol, String? bridgeBot}) {
    if (protocol == null || bridgeBot == null) return null;
    final server = serverOfUserId(bridgeBot);
    final network = networkFromName(protocol);
    if (server == null || network == null) return null;
    return SeenBridge(server, network);
  }

  @override
  bool operator ==(Object other) =>
      other is SeenBridge && other.server == server && other.network == network;

  @override
  int get hashCode => Object.hash(server, network);
}

/// The networks bridged by a bot on [server] among [bridges]: what the
/// user's own homeserver is trusted for.
Set<BridgeNetwork> networksOnServer(
        String server, Iterable<SeenBridge> bridges) =>
    {
      for (final b in bridges)
        if (b.server == server) b.network
    };

/// What trust is based on, apart from the room.
class BridgeTrust {
  const BridgeTrust(
      {this.disabledBuiltIns = const {},
      this.ownServer,
      this.ownNetworks = const {}});

  /// Ids of [builtInTrustedServers] the user turned off.
  final Set<String> disabledBuiltIns;

  /// The user's homeserver, trusted for [ownNetworks] only.
  final String? ownServer;
  final Set<BridgeNetwork> ownNetworks;

  TrustedBridgeServer? builtInFor(String userId) {
    for (final t in builtInTrustedServers) {
      if (!disabledBuiltIns.contains(t.id) && t.matches(userId)) return t;
    }
    return null;
  }

  /// Whether a person on [server] who looks like a [network] user is one:
  /// the user's homeserver once a bridge for [network] was seen on it, or
  /// a bridge on [server] listed in the room ([room]).
  bool trusts(String server, BridgeNetwork network,
          {Iterable<SeenBridge> room = const []}) =>
      (server == ownServer && ownNetworks.contains(network)) ||
      room.any((b) => b.server == server && b.network == network);
}

/// How the non-bridged `[m]` mark is shown.
enum MatrixMarkMode { bridgedRooms, everywhere, never }

MatrixMarkMode matrixMarkModeFromName(String? name) =>
    MatrixMarkMode.values.firstWhere((m) => m.name == name,
        orElse: () => MatrixMarkMode.bridgedRooms);

/// Which people name safety compares with each other: someone with a
/// verified network icon on screen only clashes with others of that
/// network; everyone else is "plain".
const String plainMarkGroup = "plain";

String markGroup(BridgedUser? user,
    {required bool marksOn, Set<BridgeNetwork> hidden = const {}}) {
  if (user == null || !user.verified || !marksOn) return plainMarkGroup;
  if (hidden.contains(user.network)) return plainMarkGroup;
  if (user.network == BridgeNetwork.other) {
    return "other:${user.networkName ?? ""}";
  }
  return user.network.name;
}
