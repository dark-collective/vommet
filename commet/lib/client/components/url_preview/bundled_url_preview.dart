import 'package:commet/client/components/url_preview/url_preview_suppression.dart';

/// Vommet issue 676: a link preview the sender bundled in the event
/// (MSC4095 `m.url_previews`, unstable `com.beeper.linkpreviews`). Showing it
/// asks nobody for the link: not the homeserver, not the site.
///
/// The sender's app wrote it, so it can claim any title, text or picture;
/// the timeline shows the link's real domain under it and asks once per chat
/// before showing previews from others.
class BundledUrlPreview {
  static const matchedUrlKey = "matrix:matched_url";

  /// MSC4095's "unstable prefix" for the matched URL is no prefix at all.
  static const unstableMatchedUrlKey = "matched_url";

  static const encryptedImageKey = "matrix:image:encrypted";
  static const unstableEncryptedImageKey = "beeper:image:encryption";

  /// Longest title or description kept; the card shows one or two lines.
  static const maxTextLength = 500;

  BundledUrlPreview._({
    required this.matchedUrl,
    this.title,
    this.description,
    this.siteName,
    this.image,
    this.encryptedImage,
    this.imageType,
    this.imageSize,
    this.imageWidth,
    this.imageHeight,
  });

  /// The link in the message body this preview belongs to.
  final Uri matchedUrl;
  final String? title;
  final String? description;
  final String? siteName;

  /// An unencrypted `mxc://` image. Never a web address: loading that would
  /// show the reader's IP address to whatever server the sender named.
  final Uri? image;

  /// An encrypted image (an EncryptedFile whose `url` is `mxc://`).
  final Map<String, Object?>? encryptedImage;

  final String? imageType;
  final int? imageSize;
  final int? imageWidth;
  final int? imageHeight;

  /// Whether the entry carries preview data. An entry with only the matched
  /// URL just allows a homeserver preview for that link (MSC4095).
  bool get hasData =>
      title != null ||
      description != null ||
      siteName != null ||
      image != null ||
      encryptedImage != null;

  /// The image's media URI, encrypted or not.
  Uri? get imageMxc {
    final url = encryptedImage?["url"];
    if (url is String) return Uri.tryParse(url);
    return image;
  }

  /// The event's MSC4095 entries; null when it has no list.
  static List<Map>? entriesOf(Map<String, dynamic>? content) {
    if (content == null) return null;
    final list = content[UrlPreviewSuppression.urlPreviewsKey] ??
        content[UrlPreviewSuppression.unstableUrlPreviewsKey];
    if (list is! List) return null;
    return list.whereType<Map>().toList();
  }

  static String? matchedUrlOf(Map entry) {
    final url = entry[matchedUrlKey] ?? entry[unstableMatchedUrlKey];
    return url is String ? url : null;
  }

  /// The bundled preview for [link] in [content], if one carries data.
  static BundledUrlPreview? forLink(Map<String, dynamic>? content, Uri link) {
    final text = link.toString();
    for (final entry in entriesOf(content) ?? const <Map>[]) {
      final matched = matchedUrlOf(entry);
      if (matched == null || _normalize(matched) != text) continue;

      final preview = fromEntry(entry);
      if (preview != null && preview.hasData) return preview;
    }
    return null;
  }

  static BundledUrlPreview? fromEntry(Map entry) {
    final matched = matchedUrlOf(entry);
    final matchedUrl = matched == null ? null : Uri.tryParse(matched);
    if (matchedUrl == null) return null;

    final encrypted = _encryptedFile(
        entry[encryptedImageKey] ?? entry[unstableEncryptedImageKey]);

    Uri? image;
    final imageText = _string(entry["og:image"]);
    if (encrypted == null && imageText != null) {
      final uri = Uri.tryParse(imageText);
      if (uri != null && uri.scheme == "mxc") image = uri;
    }

    return BundledUrlPreview._(
      matchedUrl: matchedUrl,
      title: _text(entry["og:title"]),
      description: _text(entry["og:description"])?.replaceAll("\n", "    "),
      siteName: _text(entry["og:site_name"]),
      image: image,
      encryptedImage: encrypted,
      imageType: _string(entry["og:image:type"]),
      imageSize: _int(entry["matrix:image:size"]),
      imageWidth: _int(entry["og:image:width"]),
      imageHeight: _int(entry["og:image:height"]),
    );
  }

  /// An EncryptedFile that can be decrypted, or null.
  static Map<String, Object?>? _encryptedFile(Object? value) {
    if (value is! Map) return null;
    final url = value["url"];
    final key = value["key"];
    final hashes = value["hashes"];
    if (url is! String || !url.startsWith("mxc://")) return null;
    if (value["iv"] is! String) return null;
    if (key is! Map || key["k"] is! String) return null;
    final ops = key["key_ops"];
    if (ops is! List || !ops.contains("decrypt")) return null;
    if (hashes is! Map || hashes["sha256"] is! String) return null;
    return Map<String, Object?>.from(value);
  }

  static String? _normalize(String text) {
    try {
      return Uri.parse(text).toString();
    } catch (_) {
      return null;
    }
  }

  static String? _string(Object? value) {
    if (value is String) return value.isEmpty ? null : value;
    if (value is num) return value.toString();
    return null;
  }

  static String? _text(Object? value) {
    final text = _string(value)?.trim();
    if (text == null || text.isEmpty) return null;
    if (text.length <= maxTextLength) return text;
    return "${text.substring(0, maxTextLength)}…";
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
