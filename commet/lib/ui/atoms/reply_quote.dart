import 'package:commet/main.dart';
import 'package:commet/utils/bold_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: how a reply shows the message it answers.
enum ReplyStyle {
  /// Commet's look: one line above the message, joined to the avatar.
  compact,

  /// Element-like: a coloured bar, the name and up to two lines, inside the
  /// message under the sender's name.
  quote,

  /// Telegram-like: a card tinted in the quoted person's colour.
  card;

  static const ReplyStyle fallback = ReplyStyle.quote;

  static ReplyStyle parse(String value) => ReplyStyle.values
      .firstWhere((s) => s.name == value, orElse: () => fallback);

  static ReplyStyle get current => parse(preferences.replyStyle.value);

  /// Whether the quote goes inside the message instead of above it.
  bool get inline => this != ReplyStyle.compact;

  String get label => switch (this) {
        ReplyStyle.compact => replyStyleCompact,
        ReplyStyle.quote => replyStyleQuote,
        ReplyStyle.card => replyStyleCard,
      };
}

/// What kind of media the quoted message holds, shown with an icon instead
/// of its file name. No thumbnail: that would show spoilered or unpreviewed
/// pictures.
enum ReplyQuoteMedia {
  image(Icons.image_outlined),
  video(Icons.videocam_outlined),
  audio(Icons.mic_none),
  file(Icons.insert_drive_file_outlined),
  sticker(Icons.emoji_emotions_outlined);

  const ReplyQuoteMedia(this.icon);
  final IconData icon;

  String get label => switch (this) {
        ReplyQuoteMedia.image => replyQuoteMediaImage,
        ReplyQuoteMedia.video => replyQuoteMediaVideo,
        ReplyQuoteMedia.audio => replyQuoteMediaAudio,
        ReplyQuoteMedia.file => replyQuoteMediaFile,
        ReplyQuoteMedia.sticker => replyQuoteMediaSticker,
      };
}

/// The quoted message of a reply, in the [ReplyStyle.quote] or
/// [ReplyStyle.card] look. Tapping it jumps to the original.
class ReplyQuote extends StatelessWidget {
  const ReplyQuote({
    required this.style,
    required this.senderName,
    required this.body,
    this.senderColor,
    this.media,
    this.onTap,
    super.key,
  });

  final ReplyStyle style;
  final String? senderName;
  final String? body;
  final Color? senderColor;
  final ReplyQuoteMedia? media;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        tiamat.Text.adjustColor(context, senderColor ?? scheme.primary);
    final card = style == ReplyStyle.card;
    final textStyle = Theme.of(context).textTheme.bodyMedium;

    final name = Text(senderName ?? replyQuoteLoading,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: withBoldText(
            context,
            textStyle?.copyWith(
                color: color, fontWeight: FontWeight.w700, height: 1.3)));

    final text = Text(
        media != null
            ? media!.label
            : body ?? (senderName == null ? "…" : replyQuoteUnknown),
        maxLines: card ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: withBoldText(
            context,
            textStyle?.copyWith(
                height: 1.3,
                color: card ? scheme.onSurface : scheme.onSurfaceVariant)));

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        name,
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (media != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child:
                  Icon(media!.icon, size: 16, color: scheme.onSurfaceVariant),
            ),
          Flexible(child: text),
        ]),
      ],
    );

    Widget result = card
        ? Container(
            decoration: BoxDecoration(
              color: color.withAlpha(38),
              border: Border(left: BorderSide(color: color, width: 4)),
            ),
            padding: const EdgeInsets.fromLTRB(8, 4, 10, 5),
            child: content,
          )
        : IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: content,
                  ),
                ),
              ],
            ),
          );

    return Padding(
      key: ValueKey("reply-quote-${style.name}"),
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(card ? 6 : 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, child: result),
          ),
        ),
      ),
    );
  }
}

String get replyStyleCompact => Intl.message("Compact",
    name: "replyStyleCompact",
    desc:
        "Reply style choice: the quoted message is one short line above the reply");

String get replyStyleQuote => Intl.message("Quote",
    name: "replyStyleQuote",
    desc:
        "Reply style choice: the quoted message sits inside the reply with a coloured bar, like Element");

String get replyStyleCard => Intl.message("Card",
    name: "replyStyleCard",
    desc:
        "Reply style choice: the quoted message is a tinted card inside the reply, like Telegram");

String get replyQuoteLoading => Intl.message("Loading",
    name: "replyQuoteLoading",
    desc:
        "Shown as the name in a reply's quote while the quoted message loads");

String get replyQuoteUnknown => Intl.message("Message not found",
    name: "replyQuoteUnknown",
    desc: "Shown in a reply's quote when the quoted message can't be loaded");

String get replyQuoteMediaImage => Intl.message("Photo",
    name: "replyQuoteMediaImage",
    desc: "Shown in a reply's quote when the quoted message is a picture");

String get replyQuoteMediaVideo => Intl.message("Video",
    name: "replyQuoteMediaVideo",
    desc: "Shown in a reply's quote when the quoted message is a video");

String get replyQuoteMediaAudio => Intl.message("Voice message",
    name: "replyQuoteMediaAudio",
    desc:
        "Shown in a reply's quote when the quoted message is a voice message or audio file");

String get replyQuoteMediaFile => Intl.message("File",
    name: "replyQuoteMediaFile",
    desc: "Shown in a reply's quote when the quoted message is a file");

String get replyQuoteMediaSticker => Intl.message("Sticker",
    name: "replyQuoteMediaSticker",
    desc: "Shown in a reply's quote when the quoted message is a sticker");
