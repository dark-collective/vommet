/// Vommet: where a player can stream a file from, instead of downloading the
/// whole file first (Vommet issue 338).
class StreamSource {
  final Uri uri;
  final Map<String, String> headers;

  const StreamSource(this.uri, {this.headers = const {}});
}

/// Vommet: a file provider whose file can also be streamed. Kept apart from
/// `FileProvider` so the other providers don't have to implement it.
abstract class StreamableFileProvider {
  /// Where to stream the file from, or null when it has to be downloaded
  /// first (encrypted files, files that are already cached).
  Future<StreamSource?> getStreamSource();
}
