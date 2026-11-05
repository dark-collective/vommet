import 'package:commet/ui/molecules/sticker_pack_sheet.dart';
import 'package:commet/utils/sticker_source_pack.dart';
import 'package:commet/utils/telegram_sticker_link.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 824: a sticker bridged by mautrix-telegram names its set in
// info["fi.mau.bridged_sticker"].
Map<String, dynamic> _content(Object? bridged) => {
      "body": "😀",
      "url": "mxc://example.org/abc",
      "info": {
        "mimetype": "image/webp",
        if (bridged != null) bridgedStickerKey: bridged,
      },
    };

void main() {
  group("bridgedTelegramPack", () {
    test("reads the set from a Telegram sticker's pack_url", () {
      final set = bridgedTelegramPack(_content({
        "network": "telegram",
        "id": "123",
        "emoji": "😀",
        "pack_url": "https://t.me/addstickers/SomeSet_by_x",
      }));
      expect(set?.setName, "SomeSet_by_x");
      expect(set?.isEmojiSet, false);
    });

    test("ignores other networks, missing or odd fields", () {
      expect(
          bridgedTelegramPack(_content({
            "network": "signal",
            "id": "1",
            "pack_url": "https://t.me/addstickers/SomeSet",
          })),
          isNull);
      expect(bridgedTelegramPack(_content(null)), isNull);
      expect(bridgedTelegramPack(_content("nope")), isNull);
      expect(
          bridgedTelegramPack(_content({"network": "telegram", "pack_url": 5})),
          isNull);
      expect(
          bridgedTelegramPack(_content({
            "network": "telegram",
            "pack_url": "https://example.org/addstickers/SomeSet",
          })),
          isNull);
      expect(bridgedTelegramPack({"url": "mxc://example.org/abc"}), isNull);
    });
  });

  test("telegramLink round-trips through the import dialog's parser", () {
    for (final set in const [
      TelegramStickerLink("SomeSet"),
      TelegramStickerLink("Emoji_set", isEmojiSet: true),
    ]) {
      final parsed =
          TelegramStickerLink.parse(StickerPackSheet.telegramLink(set));
      expect(parsed?.setName, set.setName);
      expect(parsed?.isEmojiSet, set.isEmojiSet);
    }
  });
}
