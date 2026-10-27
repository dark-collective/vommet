import 'package:commet/client/matrix/forwarding/forward_content.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 665: matrix.to links to a message, made like Element's
/// (room id + event id + up to three `via` servers), so they open in Element
/// and in Vommet alike.
class MatrixPermalink {
  static const int maxVia = 3;

  /// The `via` servers for a link into a room whose joined members are
  /// [members] (user id, power level), chosen like Element's
  /// RoomPermalinkCreator: the server of the highest-powered member (power
  /// level 50 or more) first, then the servers with the most members, three
  /// at most. Servers [allowed] rejects (the room's server ACL) and IP
  /// literals are skipped.
  static List<String> viaServers(Iterable<(String, int)> members,
      {bool Function(String server)? allowed}) {
    bool usable(String server) =>
        server.isNotEmpty &&
        !_isIpLiteral(server) &&
        (allowed?.call(server) ?? true);

    String? highestServer;
    var highestLevel = 49;
    final population = <String, int>{};
    for (final (userId, level) in members) {
      final server = _serverOf(userId);
      if (server == null || !usable(server)) continue;
      population[server] = (population[server] ?? 0) + 1;
      if (level > highestLevel) {
        highestLevel = level;
        highestServer = server;
      }
    }

    final byPopulation = population.keys.toList()
      ..sort((a, b) => population[b]!.compareTo(population[a]!));

    final via = <String>[if (highestServer != null) highestServer];
    for (final server in byPopulation) {
      if (via.length >= maxVia) break;
      if (!via.contains(server)) via.add(server);
    }
    return via;
  }

  /// Whether [server] may take part in the room by its `m.room.server_acl`
  /// [content] (no ACL allows everyone).
  static bool aclAllows(Map<String, dynamic>? content, String server) {
    if (content == null) return true;
    final host = _hostOf(server);
    List<String> globs(String key) =>
        (content[key] is List ? content[key] as List : const [])
            .whereType<String>()
            .toList();

    if (content["allow_ip_literals"] == false && _isIpLiteral(server)) {
      return false;
    }
    if (globs("deny").any((g) => _globMatches(g, host))) return false;
    return globs("allow").any((g) => _globMatches(g, host));
  }

  /// A link to [eventId] in [room].
  static Future<String> forEvent(matrix.Room room, String eventId) async {
    List<matrix.User> users;
    try {
      users = await room.requestParticipants([matrix.Membership.join], true);
    } catch (_) {
      users = room.getParticipants([matrix.Membership.join]);
    }
    final acl = room.getState("m.room.server_acl")?.content;
    final via = viaServers(
        users.map((u) => (u.id, room.getPowerLevelByUserId(u.id))),
        allowed: (server) => aclAllows(acl, server));
    return ForwardContent.eventPermalink(room.id, eventId, via: via);
  }

  static String? _serverOf(String userId) {
    final colon = userId.indexOf(":");
    if (colon == -1 || colon == userId.length - 1) return null;
    return userId.substring(colon + 1);
  }

  /// [server] without its port.
  static String _hostOf(String server) {
    if (server.startsWith("[")) {
      final end = server.indexOf("]");
      return end == -1 ? server : server.substring(0, end + 1);
    }
    final colon = server.lastIndexOf(":");
    return colon == -1 ? server : server.substring(0, colon);
  }

  static final RegExp _ipv4 = RegExp(r"^\d{1,3}(\.\d{1,3}){3}$");

  static bool _isIpLiteral(String server) {
    final host = _hostOf(server);
    return host.startsWith("[") || _ipv4.hasMatch(host);
  }

  static bool _globMatches(String glob, String host) {
    final pattern =
        RegExp.escape(glob).replaceAll(r"\*", ".*").replaceAll(r"\?", ".");
    return RegExp("^$pattern\$", caseSensitive: false).hasMatch(host);
  }
}
