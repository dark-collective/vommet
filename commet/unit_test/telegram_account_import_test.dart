import 'package:commet/config/experiment_entries.dart';
import 'package:commet/config/experiment_registry.dart';
import 'package:commet/main.dart';
import 'package:commet/rust/api/telegram_import.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/telegram_account_import_view.dart';
import 'package:commet/utils/sticker_pack_links.dart';
import 'package:commet/utils/telegram_account_import.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

// Vommet issue 801: the packs read from a Telegram account go into the
// normal multi-link import as t.me links.
TelegramPack _pack(String name, {bool emoji = false}) =>
    TelegramPack(shortName: name, title: name, count: 3, emoji: emoji);

void main() {
  test("sticker sets become addstickers links, emoji sets addemoji", () {
    expect(TelegramAccountImport.linkFor(_pack("CozyCats")),
        "https://t.me/addstickers/CozyCats");
    expect(TelegramAccountImport.linkFor(_pack("TinyHearts", emoji: true)),
        "https://t.me/addemoji/TinyHearts");
  });

  test("the importer reads every pack back, emoji sets as emoji", () {
    final packs = [
      _pack("CozyCats"),
      _pack("Pixel_Frogs"),
      _pack("TinyHearts", emoji: true),
    ];
    final text = packs.map(TelegramAccountImport.linkFor).join("\n");
    final links = StickerPackLinkList.parse(text).links;
    expect(links.map((l) => l.telegram?.setName),
        ["CozyCats", "Pixel_Frogs", "TinyHearts"]);
    expect(links.map((l) => l.telegram?.isEmojiSet), [false, false, true]);
  });

  test("the experiment is off until the user turns it on", () {
    expect(experimentTelegramAccountImport.defaultValue, isFalse);
    expect(ExperimentRegistry.defaultOnKeysOf(experimentEntries()),
        isNot(contains(experimentTelegramAccountImport.key)));
  });

  test("not available in a build without a Telegram app id", () {
    // Unit tests build without --dart-define VOMMET_TELEGRAM_API_ID.
    expect(TelegramAccountImport.supported, isFalse);
    expect(TelegramAccountImport.available, isFalse);
  });

  group("before signing in", () {
    setUp(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
    });

    for (final width in [800.0, 360.0]) {
      testWidgets("explains everything without overflowing at $width px",
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var closed = false;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: Scaffold(
            body: TelegramAccountImportView(
                onPacks: (_) {}, onClose: () => closed = true),
          ),
        ));
        await tester.pump();

        expect(find.text(labelTelegramImportReadsPacks), findsOneWidget);
        expect(find.text(labelTelegramImportCantReadChats), findsOneWidget);
        expect(find.text(labelTelegramImportRisk), findsOneWidget);
        expect(find.text(promptTelegramImportShowQr), findsOneWidget);

        await tester.ensureVisible(find.text(promptTelegramImportCancel));
        await tester.pump();
        await tester.tap(find.text(promptTelegramImportCancel));
        expect(closed, isTrue);
      });
    }
  });
}
