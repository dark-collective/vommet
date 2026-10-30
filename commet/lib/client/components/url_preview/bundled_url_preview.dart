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
    this.ogUrl,
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

  /// The page address the preview claims (`og:url`).
  final Uri? ogUrl;

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
      ogUrl: _webUrl(entry["og:url"]),
      image: image,
      encryptedImage: encrypted,
      imageType: _string(entry["og:image:type"]),
      imageSize: _int(entry["matrix:image:size"]),
      imageWidth: _int(entry["og:image:width"]),
      imageHeight: _int(entry["og:image:height"]),
    );
  }

  /// The site the preview says it is from when that isn't where the link
  /// goes, or null when they match (or it doesn't say). Compared by
  /// registrable domain, so `www.` and other subdomains don't count.
  ///
  /// The main check is `og:url`. Without one, a site name that is written as
  /// a domain ("paypal.com") counts too; a plain name ("PayPal") never does.
  String? get mismatchedHost {
    final linkHost = matchedUrl.host;
    if (linkHost.isEmpty) return null;

    final claimed = ogUrl?.host ?? _domainLike(siteName);
    if (claimed == null || claimed.isEmpty) return null;
    if (sameSite(claimed, linkHost)) return null;
    return _bare(claimed);
  }

  static final RegExp _domainPattern = RegExp(
      r"^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*[a-z0-9]$",
      caseSensitive: false);

  static String? _domainLike(String? name) {
    final text = name?.trim();
    if (text == null || !_domainPattern.hasMatch(text)) return null;
    return text.toLowerCase();
  }

  static Uri? _webUrl(Object? value) {
    final text = _string(value)?.trim();
    if (text == null) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || (uri.scheme != "https" && uri.scheme != "http")) {
      return null;
    }
    return uri.host.isEmpty ? null : uri;
  }

  /// Second-level suffixes under which names are registered one level
  /// deeper (`example.co.uk`). Not the whole Public Suffix List: a missing
  /// entry only makes two sites under it look alike (no warning), never
  /// the reverse.
  static const Set<String> twoLevelSuffixes = {
    "co.uk",
    "org.uk",
    "ac.uk",
    "gov.uk",
    "me.uk",
    "net.uk",
    "ltd.uk",
    "plc.uk",
    "sch.uk",
    "nhs.uk",
    "police.uk",
    "com.au",
    "net.au",
    "org.au",
    "edu.au",
    "gov.au",
    "id.au",
    "asn.au",
    "co.nz",
    "org.nz",
    "net.nz",
    "govt.nz",
    "ac.nz",
    "co.jp",
    "ne.jp",
    "or.jp",
    "ac.jp",
    "go.jp",
    "gr.jp",
    "co.kr",
    "or.kr",
    "ne.kr",
    "go.kr",
    "com.br",
    "net.br",
    "org.br",
    "gov.br",
    "com.cn",
    "net.cn",
    "org.cn",
    "gov.cn",
    "com.tw",
    "org.tw",
    "com.hk",
    "org.hk",
    "com.sg",
    "edu.sg",
    "com.mx",
    "com.ar",
    "com.co",
    "com.pe",
    "com.tr",
    "com.ua",
    "co.in",
    "net.in",
    "org.in",
    "gov.in",
    "ac.in",
    "co.za",
    "org.za",
    "co.il",
    "org.il",
    "ac.il",
    "com.my",
    "co.id",
    "com.ph",
    "com.vn",
    "co.th",
    "com.pk",
    "com.ng",
    "com.eg",
    "com.sa",
    "co.ke",
    "com.pl",
    "co.at",
    "or.at",
  };

  static String _bare(String host) {
    var h = host.toLowerCase();
    while (h.endsWith(".")) {
      h = h.substring(0, h.length - 1);
    }
    return h.startsWith("www.") ? h.substring(4) : h;
  }

  /// The registrable domain of [host]: its last two labels, or three under
  /// a [twoLevelSuffixes] entry. IP addresses stay whole.
  static String registrableDomain(String host) {
    final h = _bare(host);
    if (h.contains(":") || RegExp(r"^[0-9.]+$").hasMatch(h)) return h;
    final labels = h.split(".");
    if (labels.length <= 2) return h;
    final lastTwo = labels.sublist(labels.length - 2).join(".");
    final take = twoLevelSuffixes.contains(lastTwo) ? 3 : 2;
    return labels.sublist(labels.length - take).join(".");
  }

  /// Whether [a] and [b] belong to the same registrable domain.
  static bool sameSite(String a, String b) =>
      registrableDomain(a) == registrableDomain(b);

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
