/// Builds the content of a forwarded Matrix message.
///
/// A forward is a copy of the original content, sent as a new event by the
/// person forwarding it. Anything that only makes sense next to the original
/// event is removed:
///   - relations (`m.relates_to`): replies, threads and edits point at events
///     in the source room
///   - the reply fallback quoted at the top of `body` / `formatted_body`
///   - `m.new_content` (the caller should pass the latest edit's content)
///   - mentions, so the forward does not ping the same people again
///   - per-message profiles, which would show the forward under the original
///     sender's name
class ForwardContent {
  static const Set<String> forwardableTypes = {
    "m.room.message",
    "m.sticker",
  };

  static final RegExp _replyFallbackBody =
      RegExp(r'^>( \*)? <[^>]+>[^\n\r]+\r?\n(> [^\n]*\r?\n)*\r?\n');

  static final RegExp _replyFallbackHtml = RegExp(
    r'<mx-reply>.*</mx-reply>',
    caseSensitive: false,
    dotAll: true,
  );

  static const List<String> _removedKeys = [
    "m.relates_to",
    "m.new_content",
    "m.per_message_profile",
    "com.beeper.per_message_profile",
  ];

  static bool canForward(String type, Map<String, dynamic> content) {
    if (!forwardableTypes.contains(type)) return false;
    if (type == "m.room.message" && content["msgtype"] is! String) {
      return false;
    }
    return true;
  }

  static Map<String, dynamic> build(Map<String, dynamic> original) {
    final content = Map<String, dynamic>.of(original);

    final relation = content["m.relates_to"];
    final wasReply = relation is Map && relation["m.in_reply_to"] != null;

    for (final key in _removedKeys) {
      content.remove(key);
    }

    if (wasReply) {
      final body = content["body"];
      if (body is String) {
        content["body"] = body.replaceFirst(_replyFallbackBody, "");
      }

      final html = content["formatted_body"];
      if (html is String) {
        content["formatted_body"] = html.replaceFirst(_replyFallbackHtml, "");
      }
    }

    content["m.mentions"] = <String, dynamic>{};

    return content;
  }
}
