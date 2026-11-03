/// Vommet issue 826: whether a thread reply that matched a highlight push
/// rule ([highlight]) really mentions me. A reply in a thread points at the
/// thread's latest message, often mine; some clients then name me in
/// `m.mentions` or quote me in a reply fallback without the text naming me,
/// and that isn't an @. Keyword and @room highlights still count.
bool threadReplyNamesMe({
  required bool highlight,
  required String me,
  String? displayName,
  String? body,
  String? formattedBody,
  List<String>? mentionUserIds,
}) {
  if (!highlight) return false;

  final raw = [body, formattedBody].whereType<String>().join("\n");
  final text = [
    if (body != null) stripPlainReplyFallback(body),
    if (formattedBody != null) stripHtmlReplyFallback(formattedBody),
  ].join("\n");

  if (namesUser(text, me, displayName)) return true;
  // The only reference to me is inside the quoted message.
  if (namesUser(raw, me, displayName)) return false;
  // Nothing in the text names me: count it unless `m.mentions` naming me is
  // all that made it a highlight.
  return mentionUserIds?.contains(me) != true;
}

/// Drops the `> <@user> quoted` lines a reply fallback starts with.
String stripPlainReplyFallback(String body) {
  final lines = body.split("\n");
  var start = 0;
  while (start < lines.length && lines[start].startsWith(">")) {
    start++;
  }
  if (start == 0) return body;
  return lines.skip(start).join("\n");
}

String stripHtmlReplyFallback(String html) =>
    html.replaceAll(RegExp(r"<mx-reply>[\s\S]*?</mx-reply>"), "");

/// [text] contains [userId] (a pill links it, also URL-encoded) or
/// [displayName] as a whole word.
bool namesUser(String text, String userId, String? displayName) {
  if (text.isEmpty) return false;
  if (text.contains(userId) || text.contains(Uri.encodeComponent(userId))) {
    return true;
  }
  final name = displayName?.trim();
  if (name == null || name.isEmpty) return false;
  return RegExp(
    "(^|[^\\p{L}\\p{N}])${RegExp.escape(name)}(\$|[^\\p{L}\\p{N}])",
    caseSensitive: false,
    unicode: true,
  ).hasMatch(text);
}
