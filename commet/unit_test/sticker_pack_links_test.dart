import 'package:commet/utils/sticker_pack_links.dart';
import 'package:test/test.dart';

void main() {
  const signal =
      "https://signal.art/addstickers/#pack_id=0a1b2c3d4e5f60718293a4b5c6d7e8f9&pack_key=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";

  test("one link per line, mixed Telegram, Signal and garbage", () {
    final list = StickerPackLinkList.parse("""
Here are my packs:
t.me/addstickers/GrumpyToads
https://t.me/addemoji/SpaceOtters
$signal
https://example.org/not-a-pack
just some words
""");

    expect(list.links.map((l) => l.raw), [
      "t.me/addstickers/GrumpyToads",
      "https://t.me/addemoji/SpaceOtters",
      signal,
      "https://example.org/not-a-pack",
    ]);
    expect(list.links[0].telegram!.setName, "GrumpyToads");
    expect(list.links[1].telegram!.isEmojiSet, isTrue);
    expect(list.links[2].signal!.packId, "0a1b2c3d4e5f60718293a4b5c6d7e8f9");
    expect(list.links[3].isSupported, isFalse);
    expect(list.supportedCount, 3);
    expect(list.leftOut, 0);
  });

  test("a pasted list on one line, separated by spaces or commas", () {
    final list = StickerPackLinkList.parse(
        "t.me/addstickers/PixelFoxes, t.me/addstickers/OfficeCats t.me/addstickers/MochiBunnies");
    expect(list.links.map((l) => l.telegram!.setName),
        ["PixelFoxes", "OfficeCats", "MochiBunnies"]);
  });

  test("duplicates are dropped, whatever their spelling", () {
    final list = StickerPackLinkList.parse("""
https://t.me/addstickers/GrumpyToads
t.me/addstickers/grumpytoads
tg://addstickers?set=GrumpyToads
$signal
$signal
""");
    expect(list.links.length, 2);
    expect(list.links.first.raw, "https://t.me/addstickers/GrumpyToads");
  });

  test("signal.art links without a scheme work", () {
    final list = StickerPackLinkList.parse(signal.substring(8));
    expect(list.links.single.signal, isNotNull);
  });

  test("more than the cap: the first ones are kept, the rest counted", () {
    final text = [
      for (var i = 0; i < 205; i++) "t.me/addstickers/Pack$i",
      "t.me/addstickers/Pack3", // a duplicate isn't counted as left out
    ].join("\n");
    final list = StickerPackLinkList.parse(text);
    expect(list.links.length, StickerPackLinkList.maxLinks);
    expect(list.links.last.telegram!.setName, "Pack199");
    expect(list.leftOut, 5);
  });

  test("empty or link-free text gives no links", () {
    expect(StickerPackLinkList.parse("").links, isEmpty);
    expect(StickerPackLinkList.parse("  \n hello there \n").links, isEmpty);
  });
  test("importable links are pulled out of shared text", () {
    expect(
        StickerPackLinkList.importableLinks(
            "Look at this pack! https://t.me/addstickers/GrumpyToads\n"
            "and https://example.com/not-a-pack $signal"),
        "https://t.me/addstickers/GrumpyToads\n$signal");
    expect(
        StickerPackLinkList.importableLinks("https://example.com/x"), isNull);
    expect(StickerPackLinkList.importableLinks("just words"), isNull);
    expect(StickerPackLinkList.importableLinks(null), isNull);
  });
}
