import 'package:commet/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The tags the Matrix spec lets clients render in `formatted_body`
  // (client-server API, m.room.message msgtypes). A tag missing from the
  // renderer's list is dropped together with its text.
  const specTags = {
    'font', 'del', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'p', //
    'a', 'ul', 'ol', 'sup', 'sub', 'li', 'b', 'i', 'u', 'strong', 'em', //
    's', 'code', 'hr', 'br', 'div', 'table', 'thead', 'tbody', 'tr', 'th', //
    'td', 'caption', 'pre', 'span', 'img', 'details', 'summary',
  };

  test('every tag the Matrix spec allows is rendered', () {
    expect(specTags.difference(matrixAllowedHtmlTags), isEmpty);
  });

  test('<font color> text is kept', () {
    expect(matrixAllowedHtmlTags, contains('font'));
  });

  test('colours: #RRGGBB only, always opaque', () {
    expect(ColorHtmlExtension.parseColor("#2D862D"), const Color(0xFF2D862D));
    expect(ColorHtmlExtension.parseColor("2d862d"), const Color(0xFF2D862D));
    // Anything else keeps the normal text colour.
    for (final bad in [
      null,
      "",
      "red",
      "#FFF",
      "#002D862D",
      "#2D862Z",
      "#2D862D; x",
      "javascript:x"
    ]) {
      expect(ColorHtmlExtension.parseColor(bad), isNull, reason: "$bad");
    }
  });
}
