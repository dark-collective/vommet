import 'package:commet/utils/telegram_sticker_link.dart';
import 'package:test/test.dart';

void main() {
  void accepts(String input, String name, {bool emoji = false}) {
    test("accepts $input", () {
      final link = TelegramStickerLink.parse(input);
      expect(link, isNotNull);
      expect(link!.setName, name);
      expect(link.isEmojiSet, emoji);
    });
  }

  void rejects(String input) {
    test("rejects '$input'", () {
      expect(TelegramStickerLink.parse(input), isNull);
    });
  }

  accepts("https://t.me/addstickers/HotCherry", "HotCherry");
  accepts("  http://t.me/addstickers/Hot_Cherry2 ", "Hot_Cherry2");
  accepts("t.me/addstickers/HotCherry", "HotCherry");
  accepts("https://telegram.me/addstickers/HotCherry", "HotCherry");
  accepts("https://T.ME/addstickers/HotCherry", "HotCherry");
  accepts("https://t.me/addstickers/HotCherry/", "HotCherry");
  accepts("tg://addstickers?set=HotCherry", "HotCherry");
  accepts("https://t.me/addemoji/FoxEmoji", "FoxEmoji", emoji: true);
  accepts("tg://addemoji?set=FoxEmoji", "FoxEmoji", emoji: true);

  rejects("");
  rejects("HotCherry");
  rejects("https://t.me/HotCherry");
  rejects("https://t.me/addstickers/");
  rejects("https://t.me/addstickers/bad-name");
  rejects("https://example.org/addstickers/HotCherry");
  rejects("https://signal.art/addstickers/#pack_id=abc&pack_key=def");
  rejects("tg://resolve?domain=someone");
  rejects("https://t.me/addstickers/${"a" * 65}");
}
