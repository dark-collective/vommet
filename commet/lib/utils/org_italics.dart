import 'package:commet/main.dart';
import 'package:commet/utils/underline_markdown.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart' as sdk_markdown;

// Org-mode style italics: `/word/` is sent as italic, like `*word*`.
//
// The rewrite swaps each matching pair of slashes for asterisks before the
// Markdown-to-HTML step. Only the delimiters change, so the result has the
// same length and the same inner text as the input; the composer preview
// relies on that to map parsed nodes back onto what the user typed.
//
// Org's rules keep paths and URLs safe: the opening slash must follow the
// start of the line, whitespace or opening punctuation; the closing slash
// must precede the end of the line, whitespace or closing punctuation; the
// text between them has no slash, newline or asterisk and doesn't start or
// end with a space. `\/` stays a literal slash. Code spans, fenced and
// indented code blocks, and Markdown link destinations are left alone.

final _inline = RegExp(r'''(?<=^|[\s(\[{"'*_~>|-])'''
    r'''/([^\s/*\\](?:[^/\n*]*[^\s/*\\])?)/'''
    r'''(?=$|[\s.,;:!?)\]}"'*_~|-])''');
final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');
final _indentedCode = RegExp(r'^( {4}|\t)');
final _codeSpan = RegExp(r'(`+)[\s\S]*?\1');

String orgItalicsToMarkdown(String input) {
  if (!input.contains('/')) return input;
  return rewriteOutsideCode(input, _rewriteText);
}

/// Applies [rewrite] to the parts of [input] that aren't code: fenced and
/// indented code blocks and inline code spans are passed through as-is.
String rewriteOutsideCode(String input, String Function(String) rewrite) {
  var lines = input.split('\n');
  String? fence;
  var previousBlank = true;

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];

    var fenceMatch = _fence.firstMatch(line);
    if (fence != null) {
      if (fenceMatch != null && fenceMatch.group(1)!.startsWith(fence)) {
        fence = null;
      }
      previousBlank = false;
      continue;
    }
    if (fenceMatch != null) {
      fence = fenceMatch.group(1)!;
      previousBlank = false;
      continue;
    }

    if (previousBlank && _indentedCode.hasMatch(line)) {
      continue;
    }
    previousBlank = line.trim().isEmpty;

    lines[i] = _rewriteLine(line, rewrite);
  }

  return lines.join('\n');
}

String _rewriteLine(String line, String Function(String) rewrite) {
  // Rewrite only the text between code spans.
  var out = StringBuffer();
  var start = 0;
  for (var span in _codeSpan.allMatches(line)) {
    out.write(rewrite(line.substring(start, span.start)));
    out.write(span.group(0));
    start = span.end;
  }
  out.write(rewrite(line.substring(start)));
  return out.toString();
}

String _rewriteText(String text) {
  return text.replaceAllMapped(_inline, (m) {
    // `[label](/path/)` is a link destination, not emphasis.
    if (m.start >= 2 && text.substring(m.start - 2, m.start) == '](') {
      return m.group(0)!;
    }

    return '*${m.group(1)}*';
  });
}

/// The Matrix SDK's `markdown()`, with Vommet's extra syntax: org-mode
/// italics when the setting is on, and Discord-style `__underline__`.
/// `matrix_room.dart` imports this file under the SDK file's alias, so the
/// send path picks it up without touching its body.
String markdown(
  String text, {
  Map<String, Map<String, String>> Function()? getEmotePacks,
  String? Function(String)? getMention,
  bool convertLinebreaks = true,
}) {
  var input =
      preferences.orgModeItalics.value ? orgItalicsToMarkdown(text) : text;
  var html = sdk_markdown.markdown(underlineToMarkers(input),
      getEmotePacks: getEmotePacks,
      getMention: getMention,
      convertLinebreaks: convertLinebreaks);
  return underlineMarkersToHtml(html);
}
