// Vommet: validation for the fallback STUN server setting (Vommet issue 563).

/// Whether [value] is a single STUN URL: `stun:` or `stuns:` followed by a
/// host (and optional port), with no spaces.
bool isValidStunServerUrl(String value) =>
    RegExp(r"^stuns?:[^\s:/?#][^\s/?#]*$", caseSensitive: false)
        .hasMatch(value.trim());
