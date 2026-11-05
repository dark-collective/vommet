import 'package:commet/client/components/url_preview/bundled_url_preview.dart';
import 'package:commet/utils/text_utils.dart';

/// Vommet issue 352: a link written as `<https://example.org>` is sent
/// without a preview, as on Discord. The angle brackets stay in the plain
/// `body`, so any client that keeps the convention can see them.
///
/// Also follows MSC4095 (bundled URL previews): when an event carries
/// `m.url_previews` (unstable `com.beeper.linkpreviews`), only the URLs
/// listed there get a preview, and an empty list means none.
class UrlPreviewSuppression {
  static const urlPreviewsKey = "m.url_previews";
  static const unstableUrlPreviewsKey = "com.beeper.linkpreviews";

  // `<...>` holding something that looks like a web address. `<t:...>`
  // timestamps, `<@user:server>` in reply fallbacks and the like never
  // match, because they don't start with a scheme or www.
  static final _bracketed =
      RegExp(r'<((?:https?:\/\/|www\.)[^<>\s]+)>', caseSensitive: false);

  final Set<String> _wrapped;
  final Set<String> _bare;
  final Set<String>? _allowedByEvent;

  UrlPreviewSuppression._(this._wrapped, this._bare, this._allowedByEvent);

  /// [body] is the event's plain-text body (reply fallback already removed).
  /// [content] is the event content, read for MSC4095.
  factory UrlPreviewSuppression(String body, {Map<String, dynamic>? content}) {
    final wrapped = <String>{};
    for (final match in _bracketed.allMatches(body)) {
      // The same URL finder as getLinks, so `<https://x/page.>` matches the
      // link it finds (without the trailing dot).
      for (final uri in TextUtils.findUrls(match.group(1)!) ?? const <Uri>[]) {
        wrapped.add(uri.toString());
      }
    }

    final rest = body.replaceAll(_bracketed, " ");
    final bare = (TextUtils.findUrls(rest) ?? const <Uri>[])
        .map((uri) => uri.toString())
        .toSet();

    return UrlPreviewSuppression._(wrapped, bare, _readBundled(content));
  }

  static String? _normalize(String text) {
    try {
      return Uri.parse(text).toString();
    } catch (_) {
      return null;
    }
  }

  static Set<String>? _readBundled(Map<String, dynamic>? content) {
    // Vommet issue 676: the stable key is `matrix:matched_url`; plain
    // `matched_url` is the unstable spelling.
    return BundledUrlPreview.entriesOf(content)
        ?.map(BundledUrlPreview.matchedUrlOf)
        .nonNulls
        .map(_normalize)
        .nonNulls
        .toSet();
  }

  /// Whether [link] may get a preview: it isn't written only as `<link>` in
  /// the body, and the event's MSC4095 list, if any, includes it.
  bool allowsPreview(Uri link) {
    final text = link.toString();

    if (_allowedByEvent != null && !_allowedByEvent.contains(text)) {
      return false;
    }

    if (_wrapped.contains(text) && !_bare.contains(text)) {
      return false;
    }

    return true;
  }

  /// [links] without the ones that must not get a preview.
  List<Uri> filter(Iterable<Uri> links) => links.where(allowsPreview).toList();

  /// Whether a message with [body] has links and every one of them is
  /// written as `<link>`; the sender then marks the event with an empty
  /// MSC4095 list so clients that read it skip the preview as well.
  static bool allLinksSuppressed(String body) {
    final links = TextUtils.findUrls(body);
    if (links == null || links.isEmpty) return false;

    final suppression = UrlPreviewSuppression(body);
    return links.every((link) => !suppression.allowsPreview(link));
  }
}
