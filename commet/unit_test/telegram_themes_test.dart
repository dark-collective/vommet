import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:commet/config/telegram_theme_import.dart';
import 'package:commet/config/telegram_themes.dart';
import 'package:commet/config/theme_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';

ArchiveFile file(String name, String text) {
  var bytes = utf8.encode(text);
  return ArchiveFile(name, bytes.length, bytes);
}

void main() {
  group('Telegram theme ids', () {
    test('plain, accent and custom ids parse back', () {
      for (var t in TelegramThemes.all) {
        expect(TelegramThemes.parse(t.id)?.theme, t);
        expect(TelegramThemes.parse(t.id)?.accent, isNull);
        if (t.accents.isNotEmpty) {
          var pick = TelegramPick(t, accent: t.accents.length - 1);
          expect(TelegramThemes.parse(pick.id)?.accent, t.accents.length - 1);
        }
        var custom = TelegramPick(t, custom: const Color(0xff0a7bff));
        expect(custom.id, "${t.id}:#0a7bff");
        expect(
            TelegramThemes.parse(custom.id)?.custom, const Color(0xff0a7bff));
      }
    });

    test('slugs are unique and unknown ids are not Telegram themes', () {
      var slugs = TelegramThemes.all.map((t) => t.slug).toSet();
      expect(slugs.length, TelegramThemes.all.length);
      expect(TelegramThemes.parse("telegram-nope"), isNull);
      expect(TelegramThemes.parse("dark"), isNull);
      // An out-of-range accent falls back to the theme's own colors.
      var pick = TelegramThemes.parse("telegram-classic:99");
      expect(pick?.theme, TelegramThemes.classic);
      expect(pick?.accent, isNull);
    });

    test('every theme builds, with its backdrop and brightness', () {
      for (var t in TelegramThemes.all) {
        var theme = TelegramThemes.theme(TelegramPick(t));
        expect(theme.brightness, t.brightness, reason: t.slug);
        var chat = theme.extension<ChatStyle>();
        expect(chat?.pattern, ChatStyle.telegramPattern, reason: t.slug);
        expect(chat?.colors, isNotEmpty, reason: t.slug);
      }
    });

    test('an accent recolors primary', () {
      var t = TelegramThemes.classic;
      var theme = TelegramThemes.theme(TelegramPick(t, accent: 0));
      expect(theme.colorScheme.primary, Color(t.accents[0].color));
    });
  });

  group('Telegram Desktop import', () {
    test('aliases, alpha-last hex and comments', () {
      var values = TelegramThemeImport.parseDesktop('''
// a comment: #ffffff;
windowBg: #17212b; /* block
  comment: #000000; */
windowBgActive: #5288c1;
activeButtonBg: windowBgActive;
loop1: loop2;
loop2: loop1;
msgInBg: #18253780;
''');
      expect(values["windowBg"], 0xff17212b);
      expect(values["activeButtonBg"], 0xff5288c1);
      expect(values["msgInBg"], 0x80182537);
      expect(values.containsKey("loop1"), isFalse);
      expect(values.containsKey("comment"), isFalse);
    });

    test('maps to a dark draft with Telegram defaults filling gaps', () {
      var draft = TelegramThemeImport.fromDesktop(
          {"windowBg": 0xff17212b, "activeButtonBg": 0xff5288c1}, "Mine");
      expect(draft.brightness, Brightness.dark);
      expect(draft.colors["surface"], const Color(0xff17212b));
      expect(draft.colors["primary"], const Color(0xff5288c1));
      expect(draft.colors["onSurface"],
          Color(TelegramThemes.tinted.colors["onSurface"]!));
      expect(draft.importedFrom, TelegramThemeImport.desktopSource);
      expect(draft.chatPattern, ChatStyle.telegramPattern);
    });

    test('a .zip with colors.tdesktop-theme imports; others do not', () {
      var archive = Archive()
        ..addFile(file("Theme/colors.tdesktop-theme",
            "windowBg: #ffffff;\nactiveButtonBg: #40a7e3;"));
      var zip = Uint8List.fromList(ZipEncoder().encode(archive)!);
      expect(TelegramThemeImport.isTelegramZip(zip), isTrue);
      var draft = TelegramThemeImport.fromFile("My_Theme.zip", zip);
      expect(draft?.name, "My Theme");
      expect(draft?.brightness, Brightness.light);
      expect(draft?.colors["primary"], const Color(0xff40a7e3));

      var other = Archive()..addFile(file("theme.json", "{}"));
      var otherZip = Uint8List.fromList(ZipEncoder().encode(other)!);
      expect(TelegramThemeImport.isTelegramZip(otherZip), isFalse);
      expect(TelegramThemeImport.fromFile("x.zip", otherZip), isNull);
    });
  });

  group('Telegram Android import', () {
    test('signed ints and hex; text stops at the wallpaper', () {
      var bytes = Uint8List.fromList([
        ...latin1.encode("windowBackgroundWhite=-15460831\n"
            "chats_actionBackground=#5ea4e0\n"
            "chat_outBubble=-13286060\n"
            "WPS\n"),
        1,
        2,
        3,
        4,
        ...latin1.encode("\nWPE\n"),
      ]);
      var (values, picture) = TelegramThemeImport.parseAndroid(bytes);
      expect(values["windowBackgroundWhite"], 0xff141621);
      expect(values["chats_actionBackground"], 0xff5ea4e0);
      expect(values["chat_outBubble"], (-13286060) & 0xffffffff);
      expect(picture, [1, 2, 3, 4]);
    });

    test('maps to a draft, light defaults fill gaps', () {
      var bytes = Uint8List.fromList(
          latin1.encode("windowBackgroundWhite=-1\nchat_wallpaper=-6697729\n"));
      var draft = TelegramThemeImport.fromAndroid(bytes, "Light one");
      expect(draft, isNotNull);
      expect(draft!.brightness, Brightness.light);
      expect(draft.colors["primary"], const Color(0xff65a9e0));
      expect(draft.colors["selectedRoom"], draft.colors["primary"]);
      expect(draft.chatColors, [const Color(0xff99ccff)]);
      expect(draft.importedFrom, TelegramThemeImport.androidSource);
    });

    test('a file without values is not a theme', () {
      expect(
          TelegramThemeImport.fromFile(
              "x.attheme", Uint8List.fromList(utf8.encode("hello"))),
          isNull);
    });
  });

  group('chat backdrop in theme.json', () {
    test('round-trips through ThemeDraft', () async {
      var draft = ThemeDraft.fromTheme(
          TelegramThemes.theme(TelegramPick(TelegramThemes.night)), "t");
      draft.chatColors = [const Color(0xff112233), const Color(0xff445566)];
      draft.chatPatternStrength = 0.7;
      draft.bubbleRadius = 4;
      var json = draft.toJson();
      expect(json["chat"], isNotNull);

      var built = await ThemeJsonConverter.fromJson(json, null);
      var chat = built!.extension<ChatStyle>();
      expect(chat?.colors, draft.chatColors);
      expect(chat?.pattern, ChatStyle.telegramPattern);
      expect(chat?.patternStrength, closeTo(0.7, 0.001));
      expect(chat?.bubbleRadius, 4);
    });

    test('a theme without one writes no chat block', () {
      var draft = ThemeDraft.fromTheme(ThemeData.dark(), "t");
      expect(draft.toJson().containsKey("chat"), isFalse);
    });

    test('unknown patterns and wild values are refused or clamped', () {
      var chat = ThemeJsonConverter.loadChatStyle({
        "pattern": "https://example.com/x.svg",
        "patternStrength": 9,
        "bubbleRadius": -3,
      });
      expect(chat?.pattern, isNull);
      expect(chat?.patternStrength, 1);
      expect(chat?.bubbleRadius, 0);
    });
  });
}
