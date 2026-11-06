import 'package:matrix/matrix.dart' as matrix;

/// Vommet: [matrix.Event.plaintextBody] parses a formatted message's HTML on
/// every call, and the room list reads each room's last message on every
/// rebuild. The text depends only on the HTML, so remember it per HTML
/// string (the most recent few hundred).
extension MatrixPlaintextCache on matrix.Event {
  static const int _maxEntries = 512;
  static final Map<String, String> _byHtml = {};

  /// Same as [matrix.Event.plaintextBody], without re-parsing HTML seen
  /// recently.
  String get cachedPlaintextBody {
    final html = formattedText;
    if (html.isEmpty || content['format'] != 'org.matrix.custom.html') {
      return plaintextBody;
    }
    final cached = _byHtml.remove(html);
    if (cached != null) {
      _byHtml[html] = cached;
      return cached;
    }
    final text = plaintextBody;
    _byHtml[html] = text;
    if (_byHtml.length > _maxEntries) _byHtml.remove(_byHtml.keys.first);
    return text;
  }

  /// For tests: forget everything.
  static void clear() => _byHtml.clear();

  /// For tests: how many HTML strings are remembered.
  static int get length => _byHtml.length;
}
