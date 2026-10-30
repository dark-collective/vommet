// Vommet (Vommet issue 349): the homeserver typed on the login page. A bare
// address means https, as before; typing http:// or https:// in front keeps
// that scheme, so a local server such as http://127.0.0.1:8008 can be used.

final _scheme = RegExp(r'^https?://', caseSensitive: false);

/// Whether [input] starts with `http://` or `https://`.
bool homeserverInputHasScheme(String input) => _scheme.hasMatch(input.trim());

/// The homeserver URL for what the user typed, or null when it isn't an
/// http(s) address with a host.
Uri? homeserverUriFromInput(String input) {
  input = input.trim();
  if (input.isEmpty) return null;
  // Some other scheme, such as ftp://, rather than a bare host.
  if (!homeserverInputHasScheme(input) && input.contains("://")) return null;

  final uri =
      Uri.tryParse(homeserverInputHasScheme(input) ? input : "https://$input");
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != "http" && uri.scheme != "https") return null;
  if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) return null;

  return uri;
}

/// Whether [uri] is plain http to a server off this device, so the password
/// and messages cross the network unencrypted. Loopback is exempt: it never
/// leaves the machine.
bool homeserverUriIsInsecure(Uri uri) =>
    uri.scheme == "http" && !_isLoopbackHost(uri.host);

bool _isLoopbackHost(String host) {
  host = host.toLowerCase();
  if (host == "localhost" || host.endsWith(".localhost")) return true;
  if (host == "::1" || host == "0:0:0:0:0:0:0:1") return true;
  try {
    return Uri.parseIPv4Address(host).first == 127;
  } on FormatException {
    return false;
  }
}
