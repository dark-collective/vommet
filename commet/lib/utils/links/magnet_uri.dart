// Vommet issue 1139: a magnet is an opaque target, never a web domain.
class MagnetUri {
  static Uri? parse(String raw) {
    if (RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(raw)) return null;
    final uri = Uri.tryParse(raw);
    return uri != null && isValid(uri) ? uri : null;
  }

  static bool isValid(Uri uri) {
    final raw = uri.toString();
    if (uri.scheme != 'magnet' ||
        uri.hasAuthority ||
        uri.path.isNotEmpty ||
        uri.hasFragment ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(raw) ||
        RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(raw) ||
        RegExp(r'%(?:0[0-9a-f]|1[0-9a-f]|7f)', caseSensitive: false)
            .hasMatch(raw)) return false;
    try {
      final topics = uri.queryParametersAll['xt'] ?? const <String>[];
      return topics.any((topic) =>
          RegExp(r'^urn:btih:([0-9a-fA-F]{40}|[a-zA-Z2-7]{32})$')
              .hasMatch(topic) ||
          RegExp(r'^urn:btmh:1220[0-9a-fA-F]{64}$').hasMatch(topic));
    } on FormatException {
      return false;
    }
  }
}
