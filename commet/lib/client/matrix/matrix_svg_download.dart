import 'dart:typed_data';

import 'package:commet/utils/image/svg_image.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

extension MatrixSvgDownload on Client {
  /// Vommet: the original file behind [uri] when it is an SVG small enough to
  /// draw ([SvgImage.maxBytes]), otherwise null. Stops reading as soon as the
  /// file is too big or doesn't start like an SVG (Vommet issue 309).
  Future<Uint8List?> downloadSmallSvg(Uri uri) async {
    if (uri.authority.isEmpty || uri.pathSegments.isEmpty) return null;
    final server = Uri.encodeComponent(uri.authority);
    final mediaId = Uri.encodeComponent(uri.pathSegments.first);
    final authed = await authenticatedMediaSupported();
    final token = bearerToken;
    if (baseUri == null || (authed && token == null)) return null;
    final path = authed
        ? "_matrix/client/v1/media/download/$server/$mediaId"
        : "_matrix/media/v3/download/$server/$mediaId";

    final request = http.Request("GET", baseUri!.resolveUri(Uri(path: path)));
    if (authed) request.headers["authorization"] = "Bearer $token";

    final response = await httpClient.send(request);
    final length = response.contentLength;
    if (response.statusCode != 200 ||
        (length != null && length > SvgImage.maxBytes)) {
      await response.stream.listen(null).cancel();
      return null;
    }

    return SvgImage.readSmallSvg(response.stream);
  }
}
