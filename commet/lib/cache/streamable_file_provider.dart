import 'package:http/http.dart' as http;

/// Vommet: where a player can stream a file from, instead of downloading the
/// whole file first (Vommet issue 338).
class StreamSource {
  final Uri uri;
  final Map<String, String> headers;

  /// Vommet: completes when the whole file has arrived and checked out;
  /// fails when it didn't (an encrypted file whose checksum is wrong), and
  /// the player must stop. Null for files streamed straight from the
  /// homeserver.
  final Future<void>? verified;

  /// Vommet: called when the player is done with the stream (stops a
  /// download that is still running and deletes its private copy).
  final Future<void> Function()? close;

  const StreamSource(this.uri,
      {this.headers = const {}, this.verified, this.close});
}

/// Vommet: a file provider whose file can also be streamed. Kept apart from
/// `FileProvider` so the other providers don't have to implement it.
abstract class StreamableFileProvider {
  /// Where to stream the file from, or null when it has to be downloaded
  /// first (files that are already cached, or no stream can be set up).
  Future<StreamSource?> getStreamSource();
}

final Map<String, bool> _rangeSupport = {};

/// Vommet: whether the server behind [uri] answers HTTP range requests.
/// A player can only stream a file it can seek in: an MP4 whose index sits
/// at the end (phone screen recordings) needs a seek to the end and back,
/// and without ranges it never decodes a frame (Vommet issue 529). The
/// answer is remembered per server.
Future<bool> serverSupportsRangeRequests(http.Client client, Uri uri,
    {Map<String, String> headers = const {}}) async {
  final key = uri.origin;
  final known = _rangeSupport[key];
  if (known != null) return known;

  final request = http.Request("GET", uri)
    ..headers.addAll(headers)
    ..headers["range"] = "bytes=0-0";
  final response = await client.send(request);
  // Don't download the whole file when the range was ignored.
  await response.stream.listen(null).cancel();

  final supported = response.statusCode == 206;
  if (response.statusCode == 200 || supported) _rangeSupport[key] = supported;
  return supported;
}

/// Vommet: forgets what [serverSupportsRangeRequests] learnt (tests).
void resetRangeSupportCache() => _rangeSupport.clear();
