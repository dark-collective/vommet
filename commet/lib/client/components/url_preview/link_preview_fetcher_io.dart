import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/client/components/url_preview/outgoing_url_preview.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Desktop, Android and iOS make previews for the links they send.
const bool canMakeLinkPreviews = true;

/// Longest the page (and, separately, its image) may take.
const Duration linkPreviewTimeout = Duration(seconds: 5);

/// Most HTML read from a page; the head with its tags comes first.
const int maxLinkPreviewHtmlBytes = 1024 * 1024;

/// Largest preview image downloaded, before it is downscaled.
const int maxLinkPreviewImageBytes = 5 * 1024 * 1024;

/// Longest side of the image that is sent.
const int linkPreviewImageSide = 800;

/// Fetches [url] from this device and reads its preview. The site sees this
/// device's IP address, as if the link were opened. Null when the page
/// gives nothing to show, can't be reached in time, or isn't on the public
/// internet.
Future<OutgoingUrlPreview?> fetchOutgoingUrlPreview(Uri url) async {
  if (url.scheme != "http" && url.scheme != "https") return null;

  final client = _client();
  try {
    final page = await _getHtml(client, url).timeout(linkPreviewTimeout);
    if (page == null) return null;
    final (html, finalUrl) = page;

    final meta = PageMetadata.parse(html, finalUrl);
    if (meta.isEmpty) return null;

    OutgoingPreviewImage? image;
    if (meta.image != null) {
      try {
        image =
            await _getImage(client, meta.image!).timeout(linkPreviewTimeout);
      } catch (_) {
        // The preview goes without its picture.
      }
    }

    final preview = OutgoingUrlPreview(
      matchedUrl: url,
      title: meta.title,
      description: meta.description,
      siteName: meta.siteName,
      image: image,
    );
    return preview.hasData ? preview : null;
  } catch (error) {
    // Never the address: only that a preview failed and why.
    Log.d("Link preview not made: ${error.runtimeType}");
    return null;
  } finally {
    client.close(force: true);
  }
}

/// No cookies (HttpClient keeps none), no proxy, and every connection
/// checks the addresses it resolves, so a redirect or a DNS answer can't
/// point the fetch at this device or its network.
HttpClient _client() {
  return HttpClient()
    ..connectionTimeout = linkPreviewTimeout
    ..maxConnectionsPerHost = 2
    ..findProxy = ((_) => "DIRECT")
    ..userAgent = "Mozilla/5.0 (compatible; Vommet link preview)"
    ..connectionFactory = _publicConnection;
}

Future<ConnectionTask<Socket>> _publicConnection(
    Uri uri, String? proxyHost, int? proxyPort) async {
  if (uri.scheme != "http" && uri.scheme != "https") {
    throw const SocketException("Not a web address");
  }

  final literal = InternetAddress.tryParse(uri.host);
  final addresses =
      literal != null ? [literal] : await InternetAddress.lookup(uri.host);
  if (addresses.isEmpty ||
      !addresses.every((address) => isPublicAddress(address.rawAddress))) {
    throw const SocketException("Not a public address");
  }

  final port = uri.hasPort ? uri.port : (uri.scheme == "https" ? 443 : 80);
  Future<Socket> connect() async {
    final socket = await Socket.connect(addresses.first, port,
        timeout: linkPreviewTimeout);
    if (uri.scheme != "https") return socket;
    // TLS for the site's name, not the address we connected to.
    return SecureSocket.secure(socket, host: uri.host);
  }

  return ConnectionTask.fromSocket(connect(), () {});
}

Future<(String, Uri)?> _getHtml(HttpClient client, Uri url) async {
  final request = await client.getUrl(url);
  request.followRedirects = true;
  request.maxRedirects = 3;
  request.headers.set(HttpHeaders.acceptHeader,
      "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1");
  final response = await request.close();

  final type = response.headers.contentType;
  final isHtml = type == null ||
      type.mimeType == "text/html" ||
      type.mimeType == "application/xhtml+xml";
  if (response.statusCode != HttpStatus.ok || !isHtml) {
    await response.drain<void>().catchError((_) {});
    return null;
  }

  final bytes =
      await _readCapped(response, maxLinkPreviewHtmlBytes, truncate: true);
  if (bytes == null) return null;

  var finalUrl = url;
  for (final redirect in response.redirects) {
    finalUrl = finalUrl.resolveUri(redirect.location);
  }
  final charset = type?.charset?.toLowerCase();
  final text = charset == "iso-8859-1" || charset == "latin1"
      ? latin1.decode(bytes)
      : utf8.decode(bytes, allowMalformed: true);
  return (text, finalUrl);
}

Future<OutgoingPreviewImage?> _getImage(HttpClient client, Uri url) async {
  final request = await client.getUrl(url);
  request.maxRedirects = 3;
  final response = await request.close();
  final type = response.headers.contentType?.mimeType;
  const allowed = {"image/jpeg", "image/png", "image/gif", "image/webp"};
  if (response.statusCode != HttpStatus.ok || !allowed.contains(type)) {
    await response.drain<void>().catchError((_) {});
    return null;
  }
  if (response.contentLength > maxLinkPreviewImageBytes) {
    await response.drain<void>().catchError((_) {});
    return null;
  }

  final bytes = await _readCapped(response, maxLinkPreviewImageBytes);
  if (bytes == null) return null;
  return compute(downscaleLinkPreviewImage, bytes);
}

/// The body, at most [limit] bytes. Past it: the first [limit] bytes when
/// [truncate], else null.
Future<Uint8List?> _readCapped(HttpClientResponse response, int limit,
    {bool truncate = false}) async {
  final builder = BytesBuilder(copy: false);
  final done = Completer<Uint8List?>();
  late StreamSubscription<List<int>> subscription;
  subscription = response.listen((chunk) {
    final room = limit - builder.length;
    if (chunk.length >= room) {
      if (truncate) builder.add(chunk.sublist(0, room));
      subscription.cancel();
      if (!done.isCompleted) {
        done.complete(truncate ? builder.takeBytes() : null);
      }
      return;
    }
    builder.add(chunk);
  }, onError: (Object error) {
    if (!done.isCompleted) done.completeError(error);
  }, onDone: () {
    if (!done.isCompleted) done.complete(builder.takeBytes());
  }, cancelOnError: true);
  return done.future;
}

/// Decodes [bytes], refuses huge pictures, and re-encodes at most
/// [linkPreviewImageSide] on the longest side (which also drops EXIF).
/// Runs in an isolate.
OutgoingPreviewImage? downscaleLinkPreviewImage(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (decoder == null || info == null) return null;
  if (info.width <= 0 || info.height <= 0) return null;
  if (info.width * info.height > 40 * 1000 * 1000) return null;

  var image = decoder.decode(bytes, frame: 0);
  if (image == null) return null;

  if (image.width > linkPreviewImageSide ||
      image.height > linkPreviewImageSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: linkPreviewImageSide)
        : img.copyResize(image, height: linkPreviewImageSide);
  }

  final png = image.hasAlpha;
  return OutgoingPreviewImage(
    bytes: png ? img.encodePng(image) : img.encodeJpg(image, quality: 85),
    mimeType: png ? "image/png" : "image/jpeg",
    width: image.width,
    height: image.height,
  );
}
