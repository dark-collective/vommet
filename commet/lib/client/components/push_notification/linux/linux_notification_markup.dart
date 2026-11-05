import 'dart:convert';

/// Vommet: text for the body of a Linux desktop notification.
///
/// Daemons that report the "body-markup" capability (dunst, KDE, xfce4,
/// mako, ...) read the body as a small HTML subset, so a message, room or
/// sender name containing `<b>` or `<a href=...>` would be rendered as
/// markup. Anything that came from another user goes through here before it
/// is put into the body. The summary (title) is always plain text in the
/// freedesktop spec, so it is never escaped.
class LinuxNotificationMarkup {
  static const _text = HtmlEscape(HtmlEscapeMode.element);
  static const _attribute = HtmlEscape(HtmlEscapeMode.attribute);

  // Characters that are not allowed in XML; GMarkup-based daemons drop the
  // whole notification body when they see them.
  static final _invalid = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F￾￿]');

  /// [value] escaped for use as text inside markup (&, < and >).
  static String text(String? value) =>
      _text.convert((value ?? "").replaceAll(_invalid, ""));

  /// [value] escaped for use inside a double-quoted attribute.
  static String attribute(String? value) =>
      _attribute.convert((value ?? "").replaceAll(_invalid, ""));

  /// A plain-text [value] ready to send as a notification body: escaped when
  /// the daemon reads markup, unchanged when it shows the body as plain text.
  static String body(String? value, {required bool markup}) =>
      markup ? text(value) : (value ?? "");
}
