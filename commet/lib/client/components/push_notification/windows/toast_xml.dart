// Vommet: names and message text go into Windows toast XML. Unescaped, a
// message with "&" or "<" showed no toast at all, and one with markup could
// add its own elements (an action button opening any link, say).
import 'dart:convert';

class ToastXml {
  static const _escape = HtmlEscape();

  /// Characters XML 1.0 doesn't allow even escaped; one of them in a message
  /// would make the whole toast invalid.
  static final _invalid = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F￾￿]');

  /// [value] made safe for toast XML text and attribute values.
  static String text(String? value) =>
      _escape.convert((value ?? "").replaceAll(_invalid, ""));
}
