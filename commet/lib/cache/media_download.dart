import 'dart:typed_data';

/// Vommet issue 1065: headers for downloading a media file.
///
/// dart:io asks for gzip on every request, and some homeservers' proxies
/// (nginx with gzip for every type, e.g. matrix.4d2.org) then compress
/// media on the fly. Audio, video and pictures are compressed already, so
/// that saves nothing, and the answer loses its Content-Length: the
/// download size is unknown and every file arrives chunked. The file is
/// asked for as it is stored instead.
const Map<String, String> mediaDownloadHeaders = {
  "accept-encoding": "identity",
};

/// Vommet issue 1065: how long a media download may go without an answer or
/// a byte before it fails. Voice messages and videos were fetched with a
/// client of their own with no timeout at all (pictures go through the
/// SDK's, 35 s), so a connection that stalled kept the player loading for
/// good. Tests shorten it.
Duration mediaStallTimeout = const Duration(seconds: 30);

/// Vommet issue 1065: reads a media download's body into one buffer.
///
/// With a [contentLength] the bytes go straight into a buffer of that size,
/// returned without another copy. Without one (a chunked answer) they are
/// gathered with a [BytesBuilder]; adding them one by one to a growable
/// `List<int>` and copying that into a [Uint8List] at the end, as before,
/// took 8 bytes of memory per byte and a loop per byte. [onChunk] gets the
/// number of bytes received so far after each chunk.
Future<Uint8List> readMediaBody(Stream<List<int>> body,
    {int? contentLength, void Function(int received)? onChunk}) async {
  final length = contentLength;
  Uint8List? buffer = length != null && length > 0 ? Uint8List(length) : null;
  BytesBuilder? builder = buffer == null ? BytesBuilder() : null;
  var received = 0;

  await for (final chunk in body) {
    if (buffer != null && received + chunk.length <= buffer.length) {
      buffer.setRange(received, received + chunk.length, chunk);
    } else {
      // More than the server said: keep what came and go on without a
      // fixed size.
      if (buffer != null) {
        builder = BytesBuilder()
          ..add(Uint8List.sublistView(buffer, 0, received));
        buffer = null;
      }
      builder!.add(chunk);
    }
    received += chunk.length;
    onChunk?.call(received);
  }

  if (buffer != null) {
    return received == buffer.length
        ? buffer
        : Uint8List.sublistView(buffer, 0, received);
  }
  return builder!.takeBytes();
}
