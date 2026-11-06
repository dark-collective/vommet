/// Server chooser logic for the room directory: name normalisation, the
/// saved-server list and the sections shown in the chooser.
class DirectoryServers {
  /// Suggested servers. Each one was checked to share its directory over
  /// federation (2026-10-05); don't add a server without checking it.
  static const List<String> suggested = [
    "matrix.org",
    "mozilla.org",
    "gnome.org",
    "fedora.im",
    "tchncs.de",
  ];

  static const int maxSaved = 50;

  static final RegExp _hostname = RegExp(
      r"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*(?::[0-9]{1,5})?$");
  static final RegExp _ipv6 = RegExp(r"^\[[0-9a-f:.]+\](?::[0-9]{1,5})?$");

  /// Turns user input such as "https://Matrix.org/" or "@me:matrix.org" into
  /// a server name ("matrix.org"). Returns null if it isn't a valid name.
  static String? normalize(String input) {
    var s = input.trim().toLowerCase();
    if (s.isEmpty) return null;

    // a user id or room alias: take the server part
    if (s.startsWith("@") || s.startsWith("#") || s.startsWith("!")) {
      var colon = s.indexOf(":");
      if (colon < 0) return null;
      s = s.substring(colon + 1);
    }

    s = s.replaceFirst(RegExp(r"^[a-z][a-z0-9+.-]*://"), "");
    var slash = s.indexOf("/");
    if (slash >= 0) s = s.substring(0, slash);
    if (s.endsWith(".")) s = s.substring(0, s.length - 1);
    if (s.isEmpty) return null;

    if (!_hostname.hasMatch(s) && !_ipv6.hasMatch(s)) return null;

    var port = RegExp(r":([0-9]+)$").firstMatch(s);
    if (port != null) {
      var value = int.parse(port.group(1)!);
      if (value < 1 || value > 65535) return null;
    }

    return s;
  }

  /// Moves [server] to the front of [saved] (most recently used first).
  static List<String> touch(List<String> saved, String server) {
    var result = [server, ...saved.where((s) => s != server)];
    if (result.length > maxSaved) result = result.sublist(0, maxSaved);
    return result;
  }

  static List<String> remove(List<String> saved, String server) =>
      saved.where((s) => s != server).toList();

  /// Builds the chooser sections. [own] = homeservers of signed-in accounts
  /// (the current one first). A server appears in only one section, the
  /// first that contains it. [search] narrows every section; [perSection]
  /// caps how many rows each section shows.
  static DirectoryServerSections sections({
    required List<String> own,
    required List<String> saved,
    List<String> suggestions = suggested,
    bool showSuggestions = true,
    String search = "",
    int perSection = 5,
  }) {
    var query = search.trim().toLowerCase();
    var seen = <String>{};

    List<String> pick(Iterable<String> source, {bool capped = true}) {
      var out = <String>[];
      for (var s in source) {
        if (seen.contains(s)) continue;
        if (query.isNotEmpty && !s.contains(query)) continue;
        seen.add(s);
        out.add(s);
      }
      return out;
    }

    var ownList = pick(own);
    var savedAll = pick(saved);
    // suggestions are hidden while searching, so typing never fills the
    // popover with servers the user didn't ask for
    var suggestedAll =
        showSuggestions && query.isEmpty ? pick(suggestions) : <String>[];

    var savedShown = savedAll.take(perSection).toList();
    var suggestedShown = suggestedAll.take(perSection).toList();

    String? custom;
    var normalized = normalize(search);
    if (normalized != null &&
        !own.contains(normalized) &&
        !saved.contains(normalized)) {
      custom = normalized;
    }

    return DirectoryServerSections(
      own: ownList,
      saved: savedShown,
      hiddenSaved: savedAll.length - savedShown.length,
      suggested: suggestedShown,
      customServer: custom,
    );
  }
}

class DirectoryServerSections {
  final List<String> own;
  final List<String> saved;

  /// Saved servers not shown because of the per-section cap; the chooser
  /// says "N more, type to search".
  final int hiddenSaved;
  final List<String> suggested;

  /// A valid server name typed into the search box that isn't one of ours
  /// or saved yet: offer "Browse <server>".
  final String? customServer;

  const DirectoryServerSections({
    required this.own,
    required this.saved,
    required this.hiddenSaved,
    required this.suggested,
    this.customServer,
  });
}
