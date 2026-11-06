import 'dart:typed_data';

import 'package:commet/client/components/url_preview/bundled_url_preview.dart';
import 'package:commet/client/components/url_preview/url_preview_suppression.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Vommet issue 676 phase 2: a link preview this device made for a message
/// it is about to send. It travels inside the event (MSC4095), so nobody
/// who reads the message has to fetch the link, and the homeserver never
/// learns it in an encrypted room.
class OutgoingUrlPreview {
  const OutgoingUrlPreview({
    required this.matchedUrl,
    this.title,
    this.description,
    this.siteName,
    this.image,
  });

  /// The link in the message body, exactly as receivers find it.
  final Uri matchedUrl;
  final String? title;
  final String? description;
  final String? siteName;

  /// Already downscaled; uploaded (encrypted in an encrypted room) on send.
  final OutgoingPreviewImage? image;

  bool get hasData =>
      title != null || description != null || siteName != null || image != null;

  /// The link [message] would get a preview for: its first previewable
  /// http(s) link, the same one the timeline previews. Null when there is
  /// none (links written as `<url>`, matrix.to links, `www.` without a
  /// scheme).
  static Uri? linkFor(String message) {
    final links = TextUtils.findUrls(message);
    if (links == null) return null;

    final first = UrlPreviewSuppression(message).filter(links).firstOrNull;
    if (first == null) return null;
    if (first.scheme != "http" && first.scheme != "https") return null;
    if (first.host.isEmpty || first.authority == "matrix.to") return null;
    return first;
  }

  /// The MSC4095 entry for this preview, in the unstable spelling the event
  /// key uses (`com.beeper.linkpreviews`). [imageMxc] is a plain upload;
  /// [encryptedImage] an EncryptedFile, used instead in encrypted rooms.
  Map<String, Object?> toEntry({
    Uri? imageMxc,
    Map<String, Object?>? encryptedImage,
  }) {
    final entry = <String, Object?>{
      BundledUrlPreview.unstableMatchedUrlKey: matchedUrl.toString(),
      if (title != null) "og:title": title,
      if (description != null) "og:description": description,
      if (siteName != null) "og:site_name": siteName,
    };

    final picture = image;
    if (picture != null && (imageMxc != null || encryptedImage != null)) {
      if (encryptedImage != null) {
        entry[BundledUrlPreview.unstableEncryptedImageKey] = encryptedImage;
      } else {
        entry["og:image"] = imageMxc.toString();
      }
      entry["og:image:type"] = picture.mimeType;
      entry["og:image:width"] = picture.width;
      entry["og:image:height"] = picture.height;
      entry["matrix:image:size"] = picture.bytes.length;
    }
    return entry;
  }
}

class OutgoingPreviewImage {
  const OutgoingPreviewImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;
}

/// What a page says about itself, read from its HTML.
class PageMetadata {
  const PageMetadata({this.title, this.description, this.siteName, this.image});

  final String? title;
  final String? description;
  final String? siteName;

  /// An absolute http(s) address; only this device ever fetches it.
  final Uri? image;

  bool get isEmpty =>
      title == null && description == null && siteName == null && image == null;

  /// Reads Open Graph tags, falling back to Twitter cards, `<title>` and the
  /// meta description. [page] is the address the HTML came from (after
  /// redirects), for relative image paths.
  static PageMetadata parse(String html, Uri page) {
    final document = html_parser.parse(html);
    final meta = <String, String>{};
    for (final element in document.getElementsByTagName("meta")) {
      final key = (element.attributes["property"] ?? element.attributes["name"])
          ?.trim()
          .toLowerCase();
      final value = element.attributes["content"];
      if (key == null || value == null) continue;
      meta.putIfAbsent(key, () => value);
    }

    String? first(List<String> keys) {
      for (final key in keys) {
        final value = _clean(meta[key]);
        if (value != null) return value;
      }
      return null;
    }

    final title = first(["og:title", "twitter:title"]) ??
        _clean(_text(document.getElementsByTagName("title").firstOrNull));

    Uri? image;
    final imageText = first(
        ["og:image:secure_url", "og:image", "og:image:url", "twitter:image"]);
    if (imageText != null) {
      final resolved = Uri.tryParse(imageText);
      if (resolved != null) {
        final absolute = page.resolveUri(resolved);
        if (absolute.scheme == "http" || absolute.scheme == "https") {
          image = absolute;
        }
      }
    }

    return PageMetadata(
      title: title,
      description:
          first(["og:description", "twitter:description", "description"]),
      siteName: first(["og:site_name"]),
      image: image,
    );
  }

  static String? _text(dom.Element? element) => element?.text;

  static String? _clean(String? value) {
    final text = value?.replaceAll(RegExp(r"\s+"), " ").trim();
    if (text == null || text.isEmpty) return null;
    if (text.length <= BundledUrlPreview.maxTextLength) return text;
    return "${text.substring(0, BundledUrlPreview.maxTextLength)}…";
  }
}

/// Whether an IP address (its raw bytes) is on the public internet. Link
/// previews never connect to anything else: not this device, not the local
/// network, not link-local, carrier-grade NAT or reserved ranges.
bool isPublicAddress(List<int> raw) {
  if (raw.length == 4) return _isPublicIPv4(raw);
  if (raw.length != 16) return false;

  // IPv4-mapped (::ffff:a.b.c.d) and IPv4-compatible (::a.b.c.d).
  final zeros = raw.sublist(0, 10).every((b) => b == 0);
  if (zeros && raw[10] == 0xff && raw[11] == 0xff) {
    return _isPublicIPv4(raw.sublist(12));
  }
  if (zeros && raw[10] == 0 && raw[11] == 0) return false;

  // NAT64 (64:ff9b::/96) carries an IPv4 address too.
  if (raw[0] == 0x00 &&
      raw[1] == 0x64 &&
      raw[2] == 0xff &&
      raw[3] == 0x9b &&
      raw.sublist(4, 12).every((b) => b == 0)) {
    return _isPublicIPv4(raw.sublist(12));
  }

  // Only global unicast (2000::/3), minus documentation (2001:db8::/32)
  // and Teredo (2001::/32), whose IPv4 part can't be checked.
  if ((raw[0] & 0xe0) != 0x20) return false;
  if (raw[0] == 0x20 && raw[1] == 0x01) {
    if (raw[2] == 0x0d && raw[3] == 0xb8) return false;
    if (raw[2] == 0 && raw[3] == 0) return false;
  }
  // 6to4 (2002::/16) embeds an IPv4 address.
  if (raw[0] == 0x20 && raw[1] == 0x02) {
    return _isPublicIPv4(raw.sublist(2, 6));
  }
  return true;
}

bool _isPublicIPv4(List<int> ip) {
  final a = ip[0], b = ip[1], c = ip[2];
  if (a == 0 || a == 10 || a == 127) return false;
  if (a >= 224) return false; // multicast, reserved, broadcast
  if (a == 100 && b >= 64 && b <= 127) return false; // carrier-grade NAT
  if (a == 169 && b == 254) return false; // link-local
  if (a == 172 && b >= 16 && b <= 31) return false;
  if (a == 192 && b == 168) return false;
  if (a == 192 && b == 0 && (c == 0 || c == 2)) return false;
  if (a == 198 && (b == 18 || b == 19)) return false; // benchmarking
  if (a == 198 && b == 51 && c == 100) return false;
  if (a == 203 && b == 0 && c == 113) return false;
  return true;
}
