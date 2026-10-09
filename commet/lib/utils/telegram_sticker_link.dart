/// A Telegram sticker or custom-emoji set referenced by a share link.
class TelegramStickerLink {
  /// The set's short name, as used by the Bot API (`getStickerSet`).
  final String setName;

  /// True for custom-emoji sets (`t.me/addemoji/...`), false for sticker sets.
  final bool isEmojiSet;

  const TelegramStickerLink(this.setName, {this.isEmojiSet = false});

  static final RegExp _validName = RegExp(r"^[A-Za-z0-9_]{1,64}$");
  static const _hosts = {"t.me", "telegram.me", "telegram.dog"};

  /// Parses the forms people paste:
  ///   https://t.me/addstickers/<name>   (also telegram.me, telegram.dog, http,
  ///   or no scheme at all)
  ///   https://t.me/addemoji/<name>
  ///   tg://addstickers?set=<name>       tg://addemoji?set=<name>
  /// Returns null for anything else.
  static TelegramStickerLink? parse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;

    final lower = text.toLowerCase();
    if (_hosts.any((h) => lower.startsWith("$h/"))) {
      text = "https://$text";
    }

    final Uri uri;
    try {
      uri = Uri.parse(text);
    } catch (_) {
      return null;
    }

    String? kind;
    String? name;

    if (uri.scheme == "tg") {
      kind = uri.host;
      name = uri.queryParameters["set"];
    } else if ((uri.scheme == "https" || uri.scheme == "http") &&
        _hosts.contains(uri.host.toLowerCase())) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length == 2) {
        kind = segments[0];
        name = segments[1];
      }
    }

    if (name == null || !_validName.hasMatch(name)) return null;
    if (kind == "addstickers") return TelegramStickerLink(name);
    if (kind == "addemoji") return TelegramStickerLink(name, isEmojiSet: true);
    return null;
  }
}
