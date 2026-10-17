import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Vommet: spoilers on pictures and videos (MSC4193, "Spoilers on Media").
///
/// A spoilered media event carries a flag (and optionally a reason) at the
/// top level of its content. Vommet sends the MSC's unstable keys only (what
/// Sable, Cinny and mautrix-discord use) and reads both those and the stable
/// `m.spoiler` keys the MSC will use once accepted.
///
/// Received spoilered media is covered (blurhash or a plain fill, never the
/// media itself) until the viewer taps it; see [MediaSpoilerReveal].
class MediaSpoiler {
  const MediaSpoiler({required this.key, this.reason});

  static const String unstableKey = "page.codeberg.everypizza.msc4193.spoiler";
  static const String unstableReasonKey =
      "page.codeberg.everypizza.msc4193.spoiler.reason";
  static const String stableKey = "m.spoiler";
  static const String stableReasonKey = "m.spoiler.reason";

  static const List<String> _allKeys = [
    unstableKey,
    unstableReasonKey,
    stableKey,
    stableReasonKey,
  ];

  /// Longest reason shown; longer ones are cut with an ellipsis.
  static const int maxReasonLength = 200;

  /// Identifies the message for [MediaSpoilerReveal] (its event id).
  final String key;

  /// Why it is a spoiler, as the sender wrote it; null when none was given.
  final String? reason;

  /// Whether [content] (an event's content) marks its media as a spoiler.
  static bool isSpoiler(Map<String, dynamic> content) =>
      content[unstableKey] == true || content[stableKey] == true;

  /// The spoiler of [content], or null when it isn't one. [key] identifies
  /// the message (its event id).
  static MediaSpoiler? parse(Map<String, dynamic> content,
      {required String key}) {
    if (!isSpoiler(content)) return null;
    return MediaSpoiler(key: key, reason: reasonOf(content));
  }

  /// The trimmed, length-capped reason of [content]; unstable key first.
  static String? reasonOf(Map<String, dynamic> content) {
    for (final k in [unstableReasonKey, stableReasonKey]) {
      final value = content[k];
      if (value is! String) continue;
      final reason = value.trim().replaceAll(RegExp(r"\s+"), " ");
      if (reason.isEmpty) continue;
      return reason.length > maxReasonLength
          ? "${reason.substring(0, maxReasonLength)}…"
          : reason;
    }
    return null;
  }

  /// The keys to add to a media event's content to send it as a spoiler.
  /// Empty when [spoiler] is false. A blank [reason] is left out.
  static Map<String, dynamic> contentFor(
      {required bool spoiler, String? reason}) {
    if (!spoiler) return const {};
    final trimmed = reason?.trim();
    return {
      unstableKey: true,
      if (trimmed != null && trimmed.isNotEmpty) unstableReasonKey: trimmed,
    };
  }

  /// Copies the spoiler keys (unstable and stable) of [from] into [to], so
  /// an edit of a spoilered message stays a spoiler.
  static void copyKeys(Map<String, dynamic> from, Map<String, dynamic> to) {
    if (!isSpoiler(from)) return;
    for (final k in _allKeys) {
      if (from.containsKey(k)) to[k] = from[k];
    }
  }

  static String get labelSpoiler => Intl.message("Spoiler",
      name: "labelSpoiler",
      desc: "Stands in for a spoilered picture or video in previews, e.g. "
          "notifications and the room list");

  static String get labelImageSpoiler => Intl.message("Image (spoiler)",
      name: "labelImageSpoiler",
      desc: "Stands in for a spoilered picture in notifications, reply "
          "previews and the room list, instead of its file name or thumbnail");

  static String get labelVideoSpoiler => Intl.message("Video (spoiler)",
      name: "labelVideoSpoiler",
      desc: "Stands in for a spoilered video in notifications, reply "
          "previews and the room list, instead of its file name or thumbnail");

  static String labelSpoilerWithCaption(String label, String caption) =>
      Intl.message("$label: $caption",
          name: "labelSpoilerWithCaption",
          args: [label, caption],
          desc: "Preview of a spoilered picture or video that has a caption; "
              "label is e.g. 'Image (spoiler)', caption is the sender's text");

  /// Preview text for spoilered media: the kind plus "(spoiler)" and the
  /// caption if there is one. Never the file name, which may give it away.
  static String previewText({bool? isVideo, String? caption}) {
    final label = switch (isVideo) {
      true => labelVideoSpoiler,
      false => labelImageSpoiler,
      null => labelSpoiler,
    };
    final text = caption?.trim();
    if (text == null || text.isEmpty) return label;
    return labelSpoilerWithCaption(label, text);
  }

  /// [previewText] for raw event content (background notifications), or
  /// null when [content] isn't spoilered media.
  static String? previewTextForContent(Map<String, dynamic> content) {
    if (!isSpoiler(content)) return null;
    final msgtype = content["msgtype"];
    if (msgtype is! String ||
        !const ["m.image", "m.video", "m.file"].contains(msgtype)) {
      return null;
    }
    final body = content["body"];
    final filename = content["filename"];
    final caption =
        body is String && filename is String && body != filename ? body : null;
    return previewText(
        isVideo: switch (msgtype) {
          "m.image" => false,
          "m.video" => true,
          _ => null,
        },
        caption: caption);
  }

  @override
  bool operator ==(Object other) =>
      other is MediaSpoiler && other.key == key && other.reason == reason;

  @override
  int get hashCode => Object.hash(key, reason);
}

/// Vommet: which spoilered messages this viewer has revealed. Per message,
/// in memory only: nothing is saved or sent, and a restart covers them all
/// again.
class MediaSpoilerReveal {
  MediaSpoilerReveal._();

  static final ValueNotifier<Set<String>> revealed = ValueNotifier({});

  static bool isRevealed(String key) => revealed.value.contains(key);

  /// Whether [spoiler] should still be covered (null = not a spoiler).
  static bool isHidden(MediaSpoiler? spoiler) =>
      spoiler != null && !isRevealed(spoiler.key);

  static void reveal(String key) {
    if (isRevealed(key)) return;
    revealed.value = {...revealed.value, key};
  }

  /// Covers it again.
  static void hide(String key) {
    if (!isRevealed(key)) return;
    revealed.value = {...revealed.value}..remove(key);
  }

  /// Covers everything again (tests).
  static void reset() => revealed.value = {};
}
