// Vommet: links from outside the app (#85).

enum MatrixLinkKind { room, roomAlias, user }

/// A room, room alias or user named by a `https://matrix.to/#/...` link or a
/// `matrix:` URI (MSC2312, in the spec since v1.2).
class MatrixLinkTarget {
  final MatrixLinkKind kind;

  /// With its sigil: `!room:server`, `#alias:server` or `@user:server`.
  final String identifier;

  /// With its `$` sigil, when the link points at an event in the room.
  final String? eventId;

  final List<String> via;

  const MatrixLinkTarget(this.kind, this.identifier,
      {this.eventId, this.via = const []});

  /// The room address `MatrixClient.parseAddressToIdAndVia` understands:
  /// `!room:server?via=a,b`.
  String get roomAddress =>
      via.isEmpty ? identifier : "$identifier?via=${via.join(",")}";

  static bool isMatrixLink(Uri uri) => parse(uri) != null;

  static MatrixLinkTarget? parse(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == "matrix") return _parseMatrixUri(uri);
    if ((scheme == "https" || scheme == "http") &&
        uri.host.toLowerCase() == "matrix.to") {
      return _parseMatrixTo(uri);
    }
    return null;
  }

  // matrix:[//authority/]r/alias:server[/e/event][?via=a&via=b&action=join]
  static MatrixLinkTarget? _parseMatrixUri(Uri uri) {
    final segments = _decodeSegments(uri.path);
    if (segments == null || segments.length < 2) return null;

    final via = uri.queryParametersAll["via"] ?? const <String>[];
    final String? eventId;
    if (segments.length >= 4 && segments[2] == "e") {
      eventId = "\$${segments[3]}";
    } else {
      eventId = null;
    }

    final id = segments[1];
    if (id.isEmpty) return null;

    switch (segments[0]) {
      case "u":
        return MatrixLinkTarget(MatrixLinkKind.user, "@$id");
      case "r":
        return MatrixLinkTarget(MatrixLinkKind.roomAlias, "#$id",
            eventId: eventId, via: via);
      case "roomid":
        return MatrixLinkTarget(MatrixLinkKind.room, "!$id",
            eventId: eventId, via: via);
    }
    return null;
  }

  // https://matrix.to/#/!room:server/$event?via=a&via=b
  static MatrixLinkTarget? _parseMatrixTo(Uri uri) {
    var fragment = uri.fragment;
    if (fragment.startsWith("/")) fragment = fragment.substring(1);
    if (fragment.isEmpty) return null;

    final queryStart = fragment.indexOf("?");
    final path =
        queryStart == -1 ? fragment : fragment.substring(0, queryStart);
    final query = queryStart == -1 ? "" : fragment.substring(queryStart + 1);

    final segments = _decodeSegments(path);
    if (segments == null || segments.isEmpty) return null;

    final id = segments[0];
    if (id.length < 2) return null;

    final via = Uri(query: query).queryParametersAll["via"] ?? const <String>[];
    final eventId = segments.length >= 2 && segments[1].startsWith("\$")
        ? segments[1]
        : null;

    switch (id[0]) {
      case "@":
        return MatrixLinkTarget(MatrixLinkKind.user, id);
      case "#":
        return MatrixLinkTarget(MatrixLinkKind.roomAlias, id,
            eventId: eventId, via: via);
      case "!":
        return MatrixLinkTarget(MatrixLinkKind.room, id,
            eventId: eventId, via: via);
    }
    return null;
  }

  static List<String>? _decodeSegments(String path) {
    if (path.startsWith("/")) path = path.substring(1);
    try {
      return path.split("/").map(Uri.decodeComponent).toList();
    } on ArgumentError {
      return null;
    }
  }
}
