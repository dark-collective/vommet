// Discord-style `__underline__` (Vommet issue 54).
//
// Markdown reads `__x__` as bold; Vommet follows Discord and sends it
// underlined (`**x**` stays bold). The Matrix SDK's markdown() escapes any
// HTML in the input, so the delimiters become private-use characters that
// pass through the Markdown step untouched and are swapped for <u> tags
// after it. The plain `body` keeps what was typed.
import 'package:commet/utils/org_italics.dart';
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;

const _open = '';
const _close = '';

final _underline = RegExp(r'(?<![\w_])__(?=[^\s_])([^\n]*?[^\s_])__(?![\w_])');

String underlineToMarkers(String input) {
  if (!input.contains('__')) return input;
  return rewriteOutsideCode(
      input,
      (text) =>
          text.replaceAllMapped(_underline, (m) => '$_open${m[1]}$_close'));
}

String underlineMarkersToHtml(String html) =>
    html.replaceAll(_open, '<u>').replaceAll(_close, '</u>');

/// Composer preview: `__x__` as a `u` element.
class UnderlineSyntax extends md.InlineSyntax {
  UnderlineSyntax() : super(r'__(?=[^\s_])([^\n]*?[^\s_])__(?![\w_])');

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    var pos = startMatchPos ?? parser.pos;
    if (pos > 0 && RegExp(r'[\w_]').hasMatch(parser.source[pos - 1])) {
      return false;
    }
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element('u', [md.Text(match[1]!)]));
    return true;
  }
}
