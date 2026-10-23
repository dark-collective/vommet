// Vommet: the app font (Settings › Appearance › Text). One of the bundled
// fonts, the device's own font, or a .ttf / .otf file the user picked.
import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tiamat/config/style/theme_common.dart';

class AppFontChoice {
  const AppFontChoice(this.id, this.name, this.family);

  /// The stored preference value.
  final String id;

  /// The font's own name, shown in the list (not translated).
  final String name;

  /// The family to draw with; null keeps the theme's own fonts.
  final String? family;
}

class AppFont {
  static const String defaultId = "";
  static const String system = "system";
  static const String file = "file";

  static const List<AppFontChoice> bundled = [
    AppFontChoice("atkinson", "Atkinson Hyperlegible", "AtkinsonHyperlegible"),
    AppFontChoice("lexend", "Lexend", "Lexend"),
    AppFontChoice("opendyslexic", "OpenDyslexic", "OpenDyslexic"),
    AppFontChoice("inter", "Inter", "Inter"),
  ];

  /// A family name no bundled font has, so the engine falls back to the
  /// platform's default sans-serif font (fontconfig's on Linux, the OEM
  /// font on Android, Segoe UI on Windows).
  static String get systemFamily {
    if (!kIsWeb && (Platform.isMacOS || Platform.isIOS)) {
      return ".AppleSystemUIFont";
    }
    return "sans-serif";
  }

  /// Family the picked font file was registered under; a new name per load,
  /// because the engine keeps the first font registered for a family.
  static String? _userFamily;
  static String? _userFamilyPath;
  static int _userFamilyCount = 0;

  static AppFontChoice? bundledById(String id) {
    for (final f in bundled) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// The family for a preference value, or null for the theme's fonts.
  static String? familyFor(String id, {String? filePath}) {
    if (id == system) return systemFamily;
    if (id == file) {
      if (filePath == null || filePath.isEmpty) return null;
      return _userFamilyFor(filePath);
    }
    return bundledById(id)?.family;
  }

  static String? get currentFamily => familyFor(preferences.appFont.value,
      filePath: preferences.appFontFile.value);

  /// [theme] with every text style in the chosen font. Emoji keep their own
  /// font through the fallback list; code keeps its own family because
  /// those widgets set it on their style.
  static ThemeData apply(ThemeData theme) {
    final family = currentFamily;
    if (family == null) return theme;
    final fallback = ThemeCommon.fontFamilyFallback();
    return theme.copyWith(
      textTheme: theme.textTheme
          .apply(fontFamily: family, fontFamilyFallback: fallback),
      primaryTextTheme: theme.primaryTextTheme
          .apply(fontFamily: family, fontFamilyFallback: fallback),
    );
  }

  static String? _userFamilyFor(String path) {
    if (_userFamilyPath == path && _userFamily != null) return _userFamily;
    if (PlatformUtils.isWeb) return null;
    // Register now; text drawn before the font has loaded relays out once
    // it is ready (the engine notifies about new fonts).
    final family = "VommetUserFont${_userFamilyCount++}";
    _userFamily = family;
    _userFamilyPath = path;
    _load(family, path);
    return family;
  }

  static Future<void> _load(String family, String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to load the app font file");
    }
  }

  /// True if [bytes] start like a TrueType / OpenType font or collection.
  static bool looksLikeFont(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final tag = String.fromCharCodes(bytes.sublist(0, 4));
    return (bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 0 && bytes[3] == 0) ||
        tag == "OTTO" ||
        tag == "true" ||
        tag == "ttcf";
  }

  /// Copies a picked font file into the app's own folder (the original may
  /// be moved or deleted) and returns the copy's path, or null if it isn't
  /// a font.
  static Future<String?> importFile(String path) async {
    final bytes = await File(path).readAsBytes();
    if (!looksLikeFont(bytes)) return null;

    final dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, "fonts"));
    await dir.create(recursive: true);
    for (final old in dir.listSync().whereType<File>()) {
      if (p.basename(old.path).startsWith("app_font")) {
        try {
          await old.delete();
        } catch (_) {}
      }
    }

    // A new name each time, so a font picked twice in a row still loads.
    final ext = p.extension(path).toLowerCase();
    final copy = File(p.join(
        dir.path, "app_font_${DateTime.now().millisecondsSinceEpoch}$ext"));
    await copy.writeAsBytes(bytes, flush: true);
    return copy.path;
  }
}
