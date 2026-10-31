import 'package:commet/utils/telegram_sticker_link.dart';
import 'package:signal_sticker_api/signal_sticker_api.dart';

/// Vommet: one entry of a pasted list of sticker pack links.
class StickerPackLink {
  const StickerPackLink._(this.raw, {this.telegram, this.signal});

  /// The text as pasted.
  final String raw;

  /// Set for Telegram sticker / custom-emoji set links.
  final TelegramStickerLink? telegram;

  /// Set for Signal sticker pack links.
  final PackInfo? signal;

  /// Looks like a link, but not one to a pack we can import.
  bool get isSupported => telegram != null || signal != null;

  /// Two links with the same key are the same pack.
  String get key {
    if (telegram != null) return "tg:${telegram!.setName.toLowerCase()}";
    if (signal != null) return "signal:${signal!.packId.toLowerCase()}";
    return "other:$raw";
  }

  static const _signal = SignalStickerClient();

  /// Parses one link; null when [text] doesn't look like a link at all.
  static StickerPackLink? parse(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return null;

    final telegram = TelegramStickerLink.parse(raw);
    if (telegram != null) return StickerPackLink._(raw, telegram: telegram);

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      var signalUri = uri;
      // People paste signal.art links without the scheme too.
      if (!uri.hasScheme && raw.toLowerCase().startsWith("signal.art/")) {
        signalUri = Uri.tryParse("https://$raw") ?? uri;
      }
      final info = _signal.getPackFromUri(signalUri);
      if (info != null) return StickerPackLink._(raw, signal: info);
    }

    if (_looksLikeLink(raw)) return StickerPackLink._(raw);
    return null;
  }

  static bool _looksLikeLink(String text) =>
      text.contains("://") || RegExp(r"^[\w-]+(\.[\w-]+)+/").hasMatch(text);
}

/// Vommet: the links found in the import dialog's text box.
class StickerPackLinkList {
  StickerPackLinkList._(this.links, this.leftOut);

  /// At most this many links are processed per import.
  static const maxLinks = 200;

  /// Unique links in pasted order, at most [maxLinks].
  final List<StickerPackLink> links;

  /// Unique links beyond [maxLinks] that were dropped.
  final int leftOut;

  int get supportedCount => links.where((l) => l.isSupported).length;

  /// Splits [text] on whitespace and commas (one link per line, or a pasted
  /// list in any layout), skips words that aren't links, drops duplicates
  /// and keeps the first [cap].
  static StickerPackLinkList parse(String text, {int cap = maxLinks}) {
    final seen = <String>{};
    final links = <StickerPackLink>[];
    var leftOut = 0;
    for (final token in text.split(RegExp(r"[\s,]+"))) {
      final link = StickerPackLink.parse(token);
      if (link == null || !seen.add(link.key)) continue;
      if (links.length < cap) {
        links.add(link);
      } else {
        leftOut++;
      }
    }
    return StickerPackLinkList._(links, leftOut);
  }
}
