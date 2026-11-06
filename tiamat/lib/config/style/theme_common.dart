import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class ThemeCommon {
  static List<String>? fontFamilyFallback() {
    const fonts = ["EmojiFont"];

    if (kIsWeb) return fonts;

    // Vommet: Apple's text stack draws the COLR v0 Twemoji glyphs blank, so
    // use the system emoji font (Apple Color Emoji) there.
    if (Platform.isIOS || Platform.isMacOS) return null;

    return fonts;
  }
}
