import 'dart:convert';

/// Who and where a forwarded message originally came from (MSC4553). Every
/// field is optional and is only a claim by the person who forwarded it.
class ForwardOrigin {
  const ForwardOrigin(
      {this.sender, this.roomId, this.eventId, this.originServerTs});

  final String? sender;
  final String? roomId;
  final String? eventId;
  final int? originServerTs;

  static ForwardOrigin? fromJson(Object? json) {
    if (json is! Map) return null;
    return ForwardOrigin(
      sender: json["sender"] is String ? json["sender"] as String : null,
      roomId: json["room_id"] is String ? json["room_id"] as String : null,
      eventId: json["event_id"] is String ? json["event_id"] as String : null,
      originServerTs: json["origin_server_ts"] is int
          ? json["origin_server_ts"] as int
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (eventId != null) "event_id": eventId,
        if (roomId != null) "room_id": roomId,
        if (sender != null) "sender": sender,
        if (originServerTs != null) "origin_server_ts": originServerTs,
      };
}

/// Builds and reads forwarded Matrix messages.
///
/// A forward is a new event sent by the person forwarding. With the sender
/// shown it follows MSC4553: the original content goes in
/// `org.matrix.msc4553.forwarded.content` with the origin next to it, and the
/// top-level `body`/`formatted_body` hold a "Forwarded from" fallback that
/// clients without MSC4553 show. With the sender hidden it is a plain copy.
///
/// Either way, anything that only makes sense next to the original event is
/// dropped from what is shown: relations (replies, threads, edits), the reply
/// fallback, mentions (so nobody is pinged again) and per-message profiles.
class ForwardContent {
  /// MSC4553's unstable prefix; `m.forwarded` once the MSC is accepted.
  static const String key = "org.matrix.msc4553.forwarded";

  /// MSC2723 forwards (FluffyChat and other Famedly clients). Read only; they
  /// carry no copy of the original content.
  static const String famedlyKey = "com.famedly.app.forwarded";

  static const Set<String> forwardableTypes = {
    "m.room.message",
    "m.sticker",
  };

  static const Set<String> _textTypes = {"m.text", "m.notice", "m.emote"};

  static const Set<String> _captionTypes = {
    "m.image",
    "m.video",
    "m.audio",
    "m.file",
  };

  static final RegExp _replyFallbackBody =
      RegExp(r'^>( \*)? <[^>]+>[^\n\r]+\r?\n(> [^\n]*\r?\n)*\r?\n');

  static final RegExp _replyFallbackHtml = RegExp(
    r'<mx-reply>.*</mx-reply>',
    caseSensitive: false,
    dotAll: true,
  );

  static const List<String> _forwardKeys = [key, famedlyKey, "m.forwarded"];

  static const List<String> _contextKeys = [
    "m.relates_to",
    "m.new_content",
    "m.mentions",
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

  /// Only ordinary messages can carry the original sender (MSC4553 leaves
  /// stickers, polls and the like out); everything else forwards as a copy.
  static bool canShowSender(String type) => type == "m.room.message";

  /// Whether [content] is media with a caption, which the forward can drop.
  static bool hasCaption(Map<String, dynamic> content) {
    if (!_captionTypes.contains(content["msgtype"])) return false;
    final filename = content["filename"];
    final body = content["body"];
    return filename is String && body is String && filename != body;
  }

  static Map<String, dynamic>? _forwardObject(Map<String, dynamic> content) {
    for (final k in _forwardKeys) {
      final value = content[k];
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    return null;
  }

  static bool isForward(Map<String, dynamic> content) =>
      _forwardObject(content) != null;

  static ForwardOrigin? originOf(Map<String, dynamic> content) {
    final forwarded = _forwardObject(content);
    if (forwarded == null) return null;
    return ForwardOrigin.fromJson(forwarded);
  }

  static Map<String, dynamic>? _validContent(Object? content) {
    if (content is! Map) return null;
    if (content["msgtype"] is! String || content["body"] is! String) {
      return null;
    }
    return Map<String, dynamic>.from(content);
  }

  /// The original message of a received MSC4553 forward, with this event's
  /// own relation and mentions, ready to render in place of the fallback.
  /// Null when [content] is not a forward or carries no valid copy.
  ///
  /// The returned content keeps the forward object, so the event is still
  /// recognised as a forward and forwarding it again points at the original.
  static Map<String, dynamic>? displayContent(Map<String, dynamic> content,
      {String Function(String userId)? displayName}) {
    final forwarded = content[key];
    if (forwarded is! Map) return null;
    final original = _validContent(forwarded["content"]);
    if (original == null) return null;

    final result = Map<String, dynamic>.of(original);
    for (final k in [..._forwardKeys, ..._contextKeys]) {
      result.remove(k);
    }

    if (original["msgtype"] == "m.emote") {
      final sender = forwarded["sender"];
      final actor = sender is String
          ? (displayName?.call(sender) ?? sender)
          : _genericActor;
      result["msgtype"] = "m.text";
      result["body"] = "$actor ${original["body"]}";
      result["format"] = "org.matrix.custom.html";
      result["formatted_body"] =
          "<em><strong>${_escape(actor)}</strong> ${_originalHtml(original, _plain(original))}</em>";
    }

    if (content["m.relates_to"] != null) {
      result["m.relates_to"] = content["m.relates_to"];
    }
    result["m.mentions"] = content["m.mentions"] ?? <String, dynamic>{};
    result[key] = Map<String, dynamic>.from(forwarded);
    return result;
  }

  /// Content of a forward of [original], the content of the event the user
  /// picked (decrypted, with its latest edit applied).
  ///
  /// [origin] describes that event; it is ignored when [original] is itself
  /// a forward, whose origin is kept so the new forward points at the first
  /// message. [via] are server names for the permalink to the original.
  static Map<String, dynamic> build(
    Map<String, dynamic> original, {
    ForwardOrigin? origin,
    String type = "m.room.message",
    bool showSender = false,
    bool hideCaption = false,
    List<String> via = const [],
    String Function(String userId)? displayName,
  }) {
    // What the original message says, without forward or reply wrapping.
    Map<String, dynamic> source;
    Map<String, dynamic>? forwarded = content(original);
    if (forwarded != null) {
      source = forwarded;
    } else {
      source = Map<String, dynamic>.of(original);
      for (final k in _forwardKeys) {
        source.remove(k);
      }
      _stripReplyFallback(source);
    }

    if (hideCaption && hasCaption(source)) {
      source["body"] = source["filename"];
      source.remove("filename");
      source.remove("format");
      source.remove("formatted_body");
    }

    if (!showSender || !canShowSender(type)) {
      return _plainCopy(source);
    }

    final existing = original[key];
    final ForwardOrigin? shown = existing is Map
        ? ForwardOrigin.fromJson(existing)
        : (_forwardObject(original) != null ? originOf(original) : origin);

    final result = Map<String, dynamic>.of(source);
    for (final k in [..._forwardKeys, ..._contextKeys]) {
      result.remove(k);
    }

    _addFallback(result, source, shown, via, displayName);

    result["m.mentions"] = <String, dynamic>{};
    result[key] = {
      ...?shown?.toJson(),
      "content": source,
    };
    return result;
  }

  /// The original content carried by a received forward, if it has a valid
  /// copy (MSC4553). Relations and mentions inside it are kept as they were.
  static Map<String, dynamic>? content(Map<String, dynamic> event) {
    final forwarded = event[key];
    if (forwarded is! Map) return null;
    return _validContent(forwarded["content"]);
  }

  static Map<String, dynamic> _plainCopy(Map<String, dynamic> source) {
    final result = Map<String, dynamic>.of(source);
    for (final k in [..._forwardKeys, ..._contextKeys]) {
      result.remove(k);
    }
    result["m.mentions"] = <String, dynamic>{};
    return result;
  }

  static void _stripReplyFallback(Map<String, dynamic> content) {
    final relation = content["m.relates_to"];
    if (relation is! Map || relation["m.in_reply_to"] == null) return;

    final body = content["body"];
    if (body is String) {
      content["body"] = body.replaceFirst(_replyFallbackBody, "");
    }

    final html = content["formatted_body"];
    if (html is String) {
      content["formatted_body"] = html.replaceFirst(_replyFallbackHtml, "");
    }
  }

  static const String _genericActor = "Sender";

  /// The text a forward quotes: the message text, or a media caption.
  static String _plain(Map<String, dynamic> source) {
    final body = source["body"];
    if (body is! String) return "";
    if (_captionTypes.contains(source["msgtype"])) {
      return hasCaption(source) ? body : "";
    }
    return body;
  }

  static String _originalHtml(Map<String, dynamic> source, String plain) {
    final html = source["formatted_body"];
    if (source["format"] == "org.matrix.custom.html" && html is String) {
      return html;
    }
    return _escape(plain).replaceAll("\n", "<br>");
  }

  static void _addFallback(
    Map<String, dynamic> result,
    Map<String, dynamic> source,
    ForwardOrigin? origin,
    List<String> via,
    String Function(String userId)? displayName,
  ) {
    final msgtype = source["msgtype"];
    final isText = _textTypes.contains(msgtype);
    final isMedia = _captionTypes.contains(msgtype);

    // Locations and unknown types keep their own body.
    if (!isText && !isMedia) return;

    if (isMedia) {
      result["filename"] = source["filename"] ?? source["body"];
    }

    final sender = origin?.sender;
    final eventLink = (origin?.roomId != null && origin?.eventId != null)
        ? eventPermalink(origin!.roomId!, origin.eventId!, via: via)
        : null;

    var plain = _plain(source);
    var html = _originalHtml(source, plain);

    if (msgtype == "m.emote") {
      final name =
          sender != null ? (displayName?.call(sender) ?? sender) : null;
      plain = "${name ?? _genericActor} $plain";
      final actor = sender != null
          ? '<a href="${_escape(userPermalink(sender))}">${_escape(name!)}</a>'
          : _genericActor;
      html = "<em><strong>$actor</strong> $html</em>";
      result["msgtype"] = "m.text";
    }

    var firstLine =
        sender != null ? "Forwarded from $sender" : "Forwarded message";
    var firstHtml = sender != null
        ? 'Forwarded from <a href="${_escape(userPermalink(sender))}">${_escape(sender)}</a>'
        : "Forwarded message";

    if (eventLink != null) {
      firstLine += " - view original message: $eventLink";
      firstHtml +=
          ' - <a href="${_escape(eventLink)}">view original message</a>';
    }

    final hasText = plain.trim().isNotEmpty;
    result["body"] = hasText ? "$firstLine\n$plain" : firstLine;
    result["format"] = "org.matrix.custom.html";
    result["formatted_body"] = hasText
        ? "<strong>$firstHtml</strong><br><blockquote>$html</blockquote>"
        : "<strong>$firstHtml</strong>";
  }

  static String userPermalink(String userId) =>
      "https://matrix.to/#/${Uri.encodeComponent(userId)}";

  static String eventPermalink(String roomId, String eventId,
      {List<String> via = const []}) {
    final query = via.isEmpty
        ? ""
        : "?${via.map((s) => "via=${Uri.encodeQueryComponent(s)}").join("&")}";
    return "https://matrix.to/#/${Uri.encodeComponent(roomId)}/${Uri.encodeComponent(eventId)}$query";
  }

  static const HtmlEscape _htmlEscape = HtmlEscape(
      HtmlEscapeMode(escapeLtGt: true, escapeQuot: true, escapeApos: true));

  static String _escape(String text) => _htmlEscape.convert(text);
}
