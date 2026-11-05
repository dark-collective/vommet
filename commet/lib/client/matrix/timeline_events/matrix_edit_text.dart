import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 569: the text put in the composer to edit a message.
///
/// The plain text of a formatted message keeps a link's text but not where it
/// points, so editing a message with a link like "[here](https://...)" sent
/// it back as plain "here" and every such link was lost (and so were the
/// links of later forwards of it). Links whose text differs from their
/// address come back as markdown links here.
class MatrixEditText {
  static const Set<String> _textTypes = {"m.text", "m.notice"};

  /// The edit text of [event], or null when the plain text already is it
  /// (no links with their own text, or not a formatted text message).
  static String? of(TimelineEvent event, Timeline timeline) {
    if (event is! MatrixTimelineEventMessage) return null;
    final display = event.getDisplayEvent(timeline);
    final text = markdownOf(display);
    if (text == null) return null;
    return event.stripFallback(text, timeline: timeline);
  }

  /// The plain text of [event] with its named links as markdown links, or
  /// null when it has none.
  static String? markdownOf(matrix.Event event) {
    if (!_textTypes.contains(event.content["msgtype"])) return null;
    if (event.content["format"] != "org.matrix.custom.html") return null;
    final html = event.content["formatted_body"];
    if (html is! String || html.isEmpty) return null;

    final rewritten = linksAsMarkdown(html);
    if (rewritten == null) return null;

    final json = event.toJson();
    json["content"] = {...event.content, "formatted_body": rewritten};
    return matrix.Event.fromJson(json, event.room).plaintextBody;
  }

  /// [html] with each link whose text differs from its address written out
  /// as `[text](address)`, or null when there is no such link.
  static String? linksAsMarkdown(String html) {
    final body = html_parser.parse(html).body;
    if (body == null) return null;

    var changed = false;
    for (final a in body.querySelectorAll("a").toList()) {
      final href = a.attributes["href"]?.trim();
      if (href == null || href.isEmpty || !_isWebLink(href)) continue;
      if (_sameAsAddress(a.text.trim(), href)) continue;

      for (final t in _textNodes(a)) {
        t.text = t.text.replaceAllMapped(RegExp(r'[\[\]]'), (m) => "\\${m[0]}");
      }

      final parent = a.parent;
      if (parent == null) continue;
      final nodes = [
        dom.Text("["),
        ...a.nodes.toList(),
        dom.Text("](${_destination(href)})"),
      ];
      for (final node in nodes) {
        parent.insertBefore(node, a);
      }
      a.remove();
      changed = true;
    }

    return changed ? body.innerHtml : null;
  }

  // Mentions and room links (matrix.to, matrix:) stay as their text, like
  // before; only ordinary links get their address back.
  static bool _isWebLink(String href) {
    final lower = href.toLowerCase();
    if (lower.startsWith("https://matrix.to/")) return false;
    return lower.startsWith("https://") ||
        lower.startsWith("http://") ||
        lower.startsWith("mailto:");
  }

  /// Text that is the address itself ("nether.im", "https://nether.im/")
  /// becomes a link again when the edit is sent.
  static bool _sameAsAddress(String text, String href) {
    String bare(String s) => s
        .toLowerCase()
        .replaceFirst(RegExp(r'^(https?://|mailto:)'), "")
        .replaceFirst(RegExp(r'/+$'), "");
    return text.isEmpty || bare(text) == bare(href);
  }

  static String _destination(String href) =>
      href.replaceAll(" ", "%20").replaceAll("(", "%28").replaceAll(")", "%29");

  static Iterable<dom.Text> _textNodes(dom.Node node) sync* {
    for (final child in node.nodes) {
      if (child is dom.Text) {
        yield child;
      } else {
        yield* _textNodes(child);
      }
    }
  }
}
