// Vommet: which page messages a widget frame in the web app accepts, and
// where replies go. Plain Dart (no browser APIs) so the VM tests cover it.

class WidgetFrameOrigin {
  /// The origin pages loaded from [url] have, as browsers write it in a
  /// message's `origin` (scheme://host[:port], default port left out). Null
  /// for a URL a widget frame doesn't load: anything but http(s), or no host.
  static String? of(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != "https" && uri.scheme != "http") return null;
    return uri.origin;
  }

  /// Whether a page message is the widget's: it came from the frame's own
  /// window ([fromFrame]: `event.source` is the frame's contentWindow, so
  /// not another frame or tab), with the origin of the widget's URL
  /// ([widgetOrigin], see [of]). A widget that navigated elsewhere, or a
  /// page it framed itself, is not the widget any more.
  static bool accepts(
      {required bool fromFrame,
      required String? origin,
      required String? widgetOrigin}) {
    if (!fromFrame || origin == null || widgetOrigin == null) return false;
    return origin == widgetOrigin;
  }
}
