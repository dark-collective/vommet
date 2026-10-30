import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:commet/config/telegram_themes.dart';
import 'package:commet/config/theme_draft.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:tiamat/config/style/theme_extensions.dart';

/// Vommet: turns a Telegram theme file into a theme editor draft: a Telegram
/// Desktop `.tdesktop-theme` (alone, or zipped with its background picture)
/// or a Telegram for Android `.attheme`. Only colors are read; nothing from
/// the file is written to disk, so a crafted archive can't place files
/// anywhere (the zip's entries are only looked up by name in memory).
class TelegramThemeImport {
  static const desktopSource = "Telegram Desktop";
  static const androidSource = "Telegram Android";

  static const desktopColorsFile = "colors.tdesktop-theme";

  /// A theme file larger than this is not a theme.
  static const maxSize = 32 * 1024 * 1024;

  static bool isTelegramFile(String name) {
    var ext = path.extension(name).toLowerCase();
    return ext == ".tdesktop-theme" || ext == ".attheme";
  }

  /// A Telegram Desktop theme archive (it holds colors.tdesktop-theme).
  static bool isTelegramZip(Uint8List bytes) =>
      _desktopColorsEntry(_readZip(bytes)) != null;

  /// The draft for a Telegram theme file, or null when it isn't one.
  static ThemeDraft? fromFile(String fileName, Uint8List bytes) {
    if (bytes.length > maxSize) return null;
    var name = _themeName(fileName);
    var ext = path.extension(fileName).toLowerCase();
    if (ext == ".attheme") return fromAndroid(bytes, name);
    if (ext == ".tdesktop-theme") {
      return fromDesktop(
          parseDesktop(utf8.decode(bytes, allowMalformed: true)), name);
    }
    if (ext == ".zip") {
      var archive = _readZip(bytes);
      var colors = _desktopColorsEntry(archive);
      if (colors == null) return null;
      var values = parseDesktop(
          utf8.decode(colors.content as List<int>, allowMalformed: true));
      Color? wallpaper;
      for (var file in archive?.files ?? const <ArchiveFile>[]) {
        if (!file.isFile || file.size > maxSize) continue;
        var base = path.basenameWithoutExtension(file.name).toLowerCase();
        if (base == "background" || base == "tiled") {
          wallpaper = averageColor(file.content as List<int>);
          if (wallpaper != null) break;
        }
      }
      return fromDesktop(values, name, wallpaper: wallpaper);
    }
    return null;
  }

  static String _themeName(String fileName) {
    var name = path.basenameWithoutExtension(fileName).trim();
    name = name.replaceAll(RegExp(r"[_]+"), " ").trim();
    return ThemeDraft.safeName(name.isEmpty ? "Telegram theme" : name);
  }

  static Archive? _readZip(Uint8List bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  static ArchiveFile? _desktopColorsEntry(Archive? archive) {
    if (archive == null) return null;
    for (var file in archive.files) {
      if (file.isFile &&
          path.basename(file.name).toLowerCase() == desktopColorsFile &&
          file.size <= maxSize) {
        return file;
      }
    }
    return null;
  }

  /// The average color of a picture, or null if it can't be read.
  static Color? averageColor(List<int> bytes) {
    try {
      var image = img.decodeImage(Uint8List.fromList(bytes));
      if (image == null) return null;
      var small = img.copyResize(image,
          width: 8, height: 8, interpolation: img.Interpolation.average);
      num r = 0, g = 0, b = 0;
      var n = 0;
      for (var p in small) {
        r += p.r;
        g += p.g;
        b += p.b;
        n++;
      }
      if (n == 0) return null;
      return Color.fromARGB(
          255, (r / n).round(), (g / n).round(), (b / n).round());
    } catch (_) {
      return null;
    }
  }

  // ---- Telegram Desktop ----

  /// `key: #rrggbb[aa] | otherKey;` lines with `//` and `/* */` comments;
  /// aliases resolved. Values are ARGB.
  static Map<String, int> parseDesktop(String text) {
    text = text.replaceAll(RegExp(r"/\*[\s\S]*?\*/"), "");
    var raw = <String, String>{};
    for (var line in const LineSplitter().convert(text)) {
      var comment = line.indexOf("//");
      if (comment >= 0) line = line.substring(0, comment);
      for (var m in RegExp(r"([A-Za-z0-9_]+)\s*:\s*(#?[A-Za-z0-9_]+)\s*;")
          .allMatches(line)) {
        raw[m.group(1)!] = m.group(2)!;
      }
    }
    var values = <String, int>{};
    for (var key in raw.keys) {
      var value = raw[key];
      var seen = <String>{key};
      while (value != null && !value.startsWith("#")) {
        if (!seen.add(value)) {
          value = null;
          break;
        }
        value = raw[value];
      }
      var color = value == null ? null : _desktopHex(value);
      if (color != null) values[key] = color;
    }
    return values;
  }

  /// tdesktop writes alpha last: #rrggbbaa.
  static int? _desktopHex(String value) {
    var hex = value.substring(1);
    if (!RegExp(r"^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$").hasMatch(hex)) {
      return null;
    }
    var rgb = int.parse(hex.substring(0, 6), radix: 16);
    var alpha = hex.length == 8 ? int.parse(hex.substring(6), radix: 16) : 255;
    return (alpha << 24) | rgb;
  }

  /// Vommet slot → the tdesktop keys that decide it, first found wins (the
  /// key, then what Telegram's default palette points it at).
  static const desktopKeys = {
    "primary": ["activeButtonBg", "windowBgActive"],
    "onPrimary": ["activeButtonFg", "windowFgActive"],
    "links": ["historyLinkInFg", "windowActiveTextFg"],
    "surface": ["windowBg"],
    "surfaceContainerLow": ["dialogsBg", "windowBg"],
    "selectedRoom": ["dialogsBgActive"],
    "surfaceContainerLowest": ["menuBg", "windowBg"],
    "foundation": ["sideBarBg"],
    "surfaceContainer": ["windowBgOver"],
    "surfaceContainerHigh": ["windowBgRipple"],
    "ownBubble": ["msgOutBg"],
    "otherBubble": ["msgInBg", "windowBg"],
    "onSurface": ["windowFg"],
    "secondary": ["windowSubTextFg"],
    "tertiary": ["dialogsUnreadBg", "windowBgActive"],
    "error": ["attentionButtonFg"],
    "outline": ["inputBorderFg"],
    "codeHighlight": ["msgInMonoFg"],
  };

  static ThemeDraft fromDesktop(Map<String, int> values, String name,
      {Color? wallpaper}) {
    var surface = values["windowBg"];
    var dark = surface != null && Color(surface).computeLuminance() < 0.3;
    var fallback = dark ? TelegramThemes.tinted : TelegramThemes.classic;
    var colors = <String, Color>{};
    for (var entry in desktopKeys.entries) {
      int? value;
      for (var key in entry.value) {
        value = values[key];
        if (value != null) break;
      }
      value ??= fallback.colors[entry.key];
      if (value != null) colors[entry.key] = Color(value);
    }
    return _draft(name, dark, colors, desktopSource,
        wallpaper: [wallpaper ?? Color(fallback.wallpaper.first)]);
  }

  // ---- Telegram Android ----

  /// `key=<signed ARGB int>` lines; an embedded wallpaper picture follows
  /// a `WPS` line and ends at `WPE`.
  static (Map<String, int>, Uint8List?) parseAndroid(Uint8List bytes) {
    var marker = _indexOf(bytes, const [0x0a, 0x57, 0x50, 0x53, 0x0a]);
    var startsWithMarker = bytes.length >= 4 &&
        bytes[0] == 0x57 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x53 &&
        bytes[3] == 0x0a;
    var textEnd = startsWithMarker ? 0 : (marker < 0 ? bytes.length : marker);
    var text = latin1.decode(bytes.sublist(0, textEnd));
    var values = <String, int>{};
    for (var line in const LineSplitter().convert(text)) {
      var eq = line.indexOf("=");
      if (eq <= 0) continue;
      var key = line.substring(0, eq).trim();
      var raw = line.substring(eq + 1).trim();
      int? value;
      if (raw.startsWith("#")) {
        var hex = raw.substring(1);
        if (hex.length == 6) hex = "ff$hex";
        value = int.tryParse(hex, radix: 16);
      } else {
        value = int.tryParse(raw);
      }
      if (value != null) values[key] = value & 0xffffffff;
    }
    Uint8List? picture;
    if (startsWithMarker || marker >= 0) {
      var start = startsWithMarker ? 4 : marker + 5;
      var end = _indexOf(bytes, const [0x0a, 0x57, 0x50, 0x45], start);
      picture = bytes.sublist(start, end < 0 ? bytes.length : end);
    }
    return (values, picture);
  }

  static int _indexOf(Uint8List bytes, List<int> pattern, [int from = 0]) {
    outer:
    for (var i = from; i <= bytes.length - pattern.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  /// Vommet slot → Android key.
  static const androidKeys = {
    "primary": "chats_actionBackground",
    "onPrimary": "chats_actionIcon",
    "links": "chat_messageLinkIn",
    "surface": "windowBackgroundWhite",
    "surfaceContainerLow": "windowBackgroundWhite",
    "surfaceContainerLowest": "actionBarDefaultSubmenuBackground",
    "foundation": "actionBarDefault",
    "surfaceContainer": "windowBackgroundGray",
    "ownBubble": "chat_outBubble",
    "otherBubble": "chat_inBubble",
    "onSurface": "windowBackgroundWhiteBlackText",
    "secondary": "windowBackgroundWhiteGrayText",
    "tertiary": "chats_unreadCounter",
    "error": "text_RedRegular",
    "outline": "divider",
    "codeHighlight": "chat_messageLinkIn",
  };

  /// Telegram for Android's built-in values for the keys above, used when a
  /// file leaves one out.
  static const androidDefaults = {
    "chats_actionBackground": 0xff65a9e0,
    "chats_actionIcon": 0xffffffff,
    "chat_messageLinkIn": 0xff2678b6,
    "windowBackgroundWhite": 0xffffffff,
    "actionBarDefaultSubmenuBackground": 0xffffffff,
    "actionBarDefault": 0xffffffff,
    "windowBackgroundGray": 0xfff1f1f3,
    "chat_outBubble": 0xffefffde,
    "chat_inBubble": 0xffffffff,
    "windowBackgroundWhiteBlackText": 0xff1a1d21,
    "windowBackgroundWhiteGrayText": 0xff808384,
    "chats_unreadCounter": 0xff229af0,
    "text_RedRegular": 0xffcc2929,
    "divider": 0xffd9d9d9,
  };

  static ThemeDraft? fromAndroid(Uint8List bytes, String name) {
    var (values, picture) = parseAndroid(bytes);
    if (values.isEmpty) return null;
    var surfaceValue = values["windowBackgroundWhite"];
    var dark =
        surfaceValue != null && Color(surfaceValue).computeLuminance() < 0.3;
    var fallback = TelegramThemes.androidNight;
    var colors = <String, Color>{};
    for (var entry in androidKeys.entries) {
      var value = values[entry.value];
      value ??=
          dark ? fallback.colors[entry.key] : androidDefaults[entry.value];
      if (value != null) colors[entry.key] = Color(value);
    }
    var surface = colors["surface"]!;
    // Android keys may be see-through; Vommet's slots are solid.
    for (var key in colors.keys.toList()) {
      if (colors[key]!.a < 1) {
        colors[key] = Color.alphaBlend(colors[key]!, surface);
      }
    }
    colors["selectedRoom"] = colors["primary"]!;

    var wallpaper = <Color>[];
    var embedded = picture == null ? null : averageColor(picture);
    if (embedded != null) {
      wallpaper.add(embedded);
    } else if (values["chat_wallpaper"] case var base?) {
      wallpaper.add(Color(base | 0xff000000));
      for (var key in const [
        "chat_wallpaper_gradient_to1",
        "chat_wallpaper_gradient_to2",
        "chat_wallpaper_gradient_to3"
      ]) {
        if (values[key] case var c? when c != 0) {
          wallpaper.add(Color(c | 0xff000000));
        }
      }
    } else {
      wallpaper.addAll((dark ? fallback : TelegramThemes.blue)
          .wallpaper
          .map((c) => Color(c)));
    }
    return _draft(name, dark, colors, androidSource, wallpaper: wallpaper);
  }

  static ThemeDraft _draft(
      String name, bool dark, Map<String, Color> colors, String source,
      {required List<Color> wallpaper}) {
    var surface = colors["surface"]!;
    var onSurface = colors["onSurface"]!;
    colors["surfaceContainerHigh"] ??=
        Color.alphaBlend(onSurface.withValues(alpha: 0.08), surface);
    colors["surfaceContainerHighest"] ??=
        Color.alphaBlend(onSurface.withValues(alpha: 0.12), surface);
    return ThemeDraft(
      name: name,
      brightness: dark ? Brightness.dark : Brightness.light,
      colors: colors,
      raw: {
        "colorScheme": {
          "primaryContainer": colorToHex(colors["primary"]!),
          "onPrimaryContainer": colorToHex(colors["onPrimary"]!),
        }
      },
      cornerRadius: 0,
      borders: false,
      chatColors: wallpaper,
      chatPattern: ChatStyle.telegramPattern,
      chatPatternStrength: 0.5,
      importedFrom: source,
    );
  }
}
