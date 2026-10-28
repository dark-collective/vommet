/// Vommet issue 410: whether a file fits the homeserver's upload limit, and
/// what to call the server in the message when it doesn't.
class UploadSizeLimit {
  /// True only when both sizes are known and the file is over the limit. An
  /// unknown size or limit (0 = not known, as the background client reports)
  /// lets the file through and leaves the decision to the server.
  static bool exceeds(int? size, int? limit) =>
      size != null && limit != null && limit > 0 && size > limit;

  /// The server part of a Matrix user id (`@sam:example.org` gives
  /// `example.org`), or null when there is none.
  static String? serverOf(String? userId) {
    if (userId == null) return null;
    final colon = userId.indexOf(":");
    if (colon < 0 || colon == userId.length - 1) return null;
    return userId.substring(colon + 1);
  }
}
