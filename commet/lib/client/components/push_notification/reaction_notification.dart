import 'package:intl/intl.dart';

/// Vommet issue 554: the opt-in "someone reacted to your message"
/// notification. Reactions match no push rule, so they never arrive as
/// notifications by themselves; MatrixRoom looks at them as they come in.
/// The event-shape decisions live here so they can be unit tested.
class ReactionNotification {
  static String notificationReactedTo(String emoji, String preview) =>
      Intl.message("reacted $emoji to: $preview",
          name: "notificationReactedTo",
          desc:
              "Body of the notification for a reaction to one of your messages. The reacting user's name is the title",
          args: [emoji, preview]);

  static String get notificationReactedCustomEmoji => Intl.message(
      "a custom emoji",
      name: "notificationReactedCustomEmoji",
      desc:
          "Stands in for a custom emoji (an image) with no name in a reaction notification");

  static String get notificationReactedYourMessage => Intl.message(
      "your message",
      name: "notificationReactedYourMessage",
      desc:
          "Stands in for the message preview in a reaction notification when the message has no text to show");

  static const int previewLength = 100;

  static Map? _annotation(Map<String, dynamic> content) {
    final relation = content["m.relates_to"];
    if (relation is! Map || relation["rel_type"] != "m.annotation") {
      return null;
    }
    if (relation["event_id"] is! String || relation["key"] is! String) {
      return null;
    }
    return relation;
  }

  /// The event a reaction's [content] reacts to, or null if it isn't a
  /// well-formed reaction.
  static String? targetEventId(Map<String, dynamic> content) =>
      _annotation(content)?["event_id"] as String?;

  /// Whether a bridge sent this on behalf of the user's own account (a
  /// double-puppeted reaction made on the other network), which is the
  /// user's own reaction coming back.
  static bool isBridgeEcho(Map<String, dynamic> content) =>
      content.containsKey("fi.mau.double_puppet_source");

  /// The emoji as shown in the notification: the key itself, or the
  /// shortcode of a custom (mxc) emoji.
  static String emojiLabel(Map<String, dynamic> content) {
    final key = _annotation(content)?["key"] as String? ?? "";
    if (!key.startsWith("mxc://")) return key;

    for (final field in ["shortcode", "com.beeper.reaction.shortcode"]) {
      final shortcode = content[field];
      if (shortcode is String && shortcode.trim().isNotEmpty) {
        final name = shortcode.trim();
        return name.startsWith(":") ? name : ":$name:";
      }
    }
    return notificationReactedCustomEmoji;
  }

  /// One line of the reacted-to message, cut to [previewLength] characters.
  static String preview(String? body) {
    final text = (body ?? "").replaceAll(RegExp(r"\s+"), " ").trim();
    if (text.isEmpty) return notificationReactedYourMessage;
    // By runes, so an emoji is never cut in half.
    final runes = text.runes.toList();
    if (runes.length <= previewLength) return text;
    return "${String.fromCharCodes(runes.take(previewLength - 1)).trimRight()}…";
  }

  static String body(Map<String, dynamic> content, String? targetBody) =>
      notificationReactedTo(emojiLabel(content), preview(targetBody));
}
