/// Vommet: the account data that tells your homeserver whose invites to turn
/// away (MSC4155 / the spec's invite permission config). Pure logic, so it
/// can be unit tested; [MatrixInvitePermissions] reads and writes it.
///
/// What nether.im (Tuwunel 1.9.3, `service/users/invite_filter.rs`) reads,
/// in this order:
/// * any slot with a blanket block turns every invite away;
/// * then `m.ignored_user_list` (our Block users list) hides invites from
///   those people without telling them;
/// * then each slot's rule lists; the first verdict other than "allow" wins.
///
/// The slots:
/// * [stableType]: the spec's `default_action`. Upstream's "Allow
///   invitations" switch writes this one.
/// * [blanketType]: MSC4380's `block_all`, from before the spec adopted it.
///   Nobody writes it any more, but a leftover `true` still blocks all.
/// * [listsType]: MSC4155's rule lists (`blocked_servers` and friends). The
///   spec hasn't adopted the lists, so this unstable slot is where they go.
///
/// Every change keeps the keys we don't manage, so other apps' rules survive.
class InvitePermissionConfig {
  static const String stableType = "m.invite_permission_config";
  static const String blanketType =
      "org.matrix.msc4380.invite_permission_config";
  static const String listsType = "org.matrix.msc4155.invite_permission_config";

  const InvitePermissionConfig({this.stable, this.blanket, this.lists});

  /// Current content of each slot (null when the account has none).
  final Map<String, dynamic>? stable;
  final Map<String, dynamic>? blanket;
  final Map<String, dynamic>? lists;

  static bool _blocks(Map<String, dynamic>? content) =>
      content?["default_action"] == "block";

  /// Whether the server turns every invite away.
  bool get blocksAll =>
      _blocks(stable) ||
      _blocks(lists) ||
      _blocks(blanket) ||
      blanket?["block_all"] == true;

  /// The account data to write so that [blocksAll] becomes [block].
  /// Returns only the slots that change (type → new content).
  Map<String, Map<String, dynamic>> setBlocksAll(bool block) {
    final writes = <String, Map<String, dynamic>>{};
    if (block) {
      if (!blocksAll) {
        writes[stableType] = {...?stable, "default_action": "block"};
      }
      return writes;
    }
    // Every slot that blocks has to let go, or "Anyone" changes nothing.
    if (stable?.containsKey("default_action") == true) {
      writes[stableType] = Map.of(stable!)..remove("default_action");
    } else if (stable == null) {
      // Keep upstream's behaviour of writing the (empty) stable slot.
      writes[stableType] = {};
    }
    if (blanket?["block_all"] == true || _blocks(blanket)) {
      writes[blanketType] = Map.of(blanket!)
        ..["block_all"] = false
        ..remove("default_action");
    }
    if (_blocks(lists)) {
      writes[listsType] = Map.of(lists!)..remove("default_action");
    }
    return writes;
  }

  /// The servers (globs allowed) whose invites are turned away.
  List<String> get blockedServers {
    final value = lists?["blocked_servers"];
    if (value is! List) return const [];
    return value.whereType<String>().toList();
  }

  /// Whether the rule lists are switched off (`enabled: false`).
  bool get listsDisabled => lists?["enabled"] == false;

  /// New content for [listsType] with [server] added to `blocked_servers`.
  /// Null when it's already there. Turns the lists back on if another app
  /// switched them off, or the new block would do nothing.
  Map<String, dynamic>? withBlockedServer(String server) {
    final glob = normaliseServer(server);
    if (glob == null) {
      throw ArgumentError.value(server, "server", "not a server name");
    }
    final current = blockedServers;
    final present = current.any((s) => s.toLowerCase() == glob);
    if (present && !listsDisabled) return null;
    return {
      ...?lists,
      "blocked_servers": [...current, if (!present) glob],
    }..remove("enabled");
  }

  /// New content for [listsType] without [server] in `blocked_servers`.
  /// Null when it isn't there.
  Map<String, dynamic>? withoutBlockedServer(String server) {
    final current = blockedServers;
    final key = server.trim().toLowerCase();
    final kept = current.where((s) => s.toLowerCase() != key).toList();
    if (kept.length == current.length) return null;
    return {...?lists, "blocked_servers": kept};
  }

  /// A server name or glob as the server compares it: trimmed, lower case,
  /// no port. Null when it can't be a server name.
  static String? normaliseServer(String input) {
    var s = input.trim().toLowerCase();
    if (s.isEmpty || s.contains(RegExp(r"\s"))) return null;
    // People paste a Matrix ID or a link now and then.
    if (s.startsWith("@") && s.contains(":")) {
      s = s.substring(s.indexOf(":") + 1);
    }
    s = s.replaceFirst(RegExp(r"^https?://"), "");
    s = s.replaceFirst(RegExp(r"/.*$"), "");
    s = stripPort(s);
    if (s.isEmpty) return null;
    if (!RegExp(r"^[a-z0-9.\-*?\[\]:]+$").hasMatch(s)) return null;
    return s;
  }

  /// The host part of a server name (`example.org:8448` → `example.org`).
  static String stripPort(String server) {
    if (server.startsWith("[")) {
      final end = server.indexOf("]");
      return end == -1 ? server : server.substring(0, end + 1);
    }
    final colon = server.lastIndexOf(":");
    if (colon == -1) return server;
    final port = server.substring(colon + 1);
    return RegExp(r"^\d+$").hasMatch(port)
        ? server.substring(0, colon)
        : server;
  }

  /// The server of a Matrix user ID, without a port.
  static String? serverOf(String? userId) {
    if (userId == null) return null;
    final colon = userId.indexOf(":");
    if (colon == -1 || colon == userId.length - 1) return null;
    return stripPort(userId.substring(colon + 1)).toLowerCase();
  }

  /// Whether [glob] matches [server] the way the homeserver compares them
  /// (case-insensitive; `*` any run of characters, `?` one character).
  static bool matches(String glob, String server) {
    final g = glob.toLowerCase();
    final s = server.toLowerCase();
    if (!g.contains("*") && !g.contains("?")) return g == s;
    final pattern = RegExp("^${g.split("").map((c) => switch (c) {
          "*" => ".*",
          "?" => ".",
          _ => RegExp.escape(c),
        }).join()}\$");
    return pattern.hasMatch(s);
  }
}
