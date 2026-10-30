import 'package:commet/client/matrix/components/sticker_shelf/matrix_sticker_shelf_component.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 890: the sticker picker's Favorites (max 10) and Recent
// (max 25) rows, kept in account data newest first.
ShelfSticker _s(int i) =>
    ShelfSticker(url: "mxc://example.org/$i", shortcode: "s$i");

List<String> _urls(List<ShelfSticker> list) => list.map((i) => i.url).toList();

void main() {
  test("push puts a new sticker first", () {
    final r = ShelfSticker.push([_s(1), _s(2)], _s(3), 10);
    expect(_urls(r.list), _urls([_s(3), _s(1), _s(2)]));
    expect(r.dropped, isFalse);
  });

  test("push moves a sticker already on the shelf to the front", () {
    final r = ShelfSticker.push([_s(1), _s(2), _s(3)], _s(3), 10);
    expect(_urls(r.list), _urls([_s(3), _s(1), _s(2)]));
    expect(r.dropped, isFalse);
  });

  test("push past the cap drops the oldest", () {
    final full = [for (var i = 0; i < 10; i++) _s(i)];
    final r = ShelfSticker.push(full, _s(99), 10);
    expect(r.list.length, 10);
    expect(r.list.first.url, _s(99).url);
    expect(_urls(r.list).contains(_s(9).url), isFalse);
    expect(r.dropped, isTrue);
  });

  test("content round-trips and keeps the pack", () {
    final list = [
      const ShelfSticker(
          url: "mxc://example.org/a", shortcode: "cat", packKey: "pack1"),
      _s(2),
    ];
    final back = ShelfSticker.listFromContent(ShelfSticker.listToContent(list));
    expect(_urls(back), _urls(list));
    expect(back.first.packKey, "pack1");
    expect(back.first.shortcode, "cat");
    expect(back.last.packKey, isNull);
  });

  test("bad and duplicate entries are skipped", () {
    final back = ShelfSticker.listFromContent({
      "stickers": [
        {"url": "mxc://example.org/a", "shortcode": "a"},
        {"url": "https://example.org/b"},
        "junk",
        {"url": "mxc://example.org/a", "shortcode": "again"},
        {"url": "mxc://example.org/c"},
      ]
    });
    expect(_urls(back), ["mxc://example.org/a", "mxc://example.org/c"]);
    expect(back.last.shortcode, "sticker");
    expect(ShelfSticker.listFromContent(null), isEmpty);
    expect(ShelfSticker.listFromContent({"stickers": "x"}), isEmpty);
  });
}
