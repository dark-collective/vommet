// Vommet issue 731: the Library's pack and GIF folder edits.
import 'package:commet/client/matrix/components/emoticon/image_pack_types.dart';
import 'package:commet/utils/library_ops.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> pack(List<String> keys, {String name = "P"}) => {
      "pack": {"display_name": name},
      "images": {
        for (var i = 0; i < keys.length; i++)
          keys[i]: {
            "url": "mxc://s/${keys[i]}",
            ImagePackTypes.order: i,
            ImagePackTypes.unstableOrder: i,
          },
      },
    };

List<String> keysOf(Map<String, dynamic> content) =>
    [for (final e in LibraryOps.orderedImages(content)) e.key];

void expectNumbered(Map<String, dynamic> content) {
  final images = LibraryOps.orderedImages(content);
  for (var i = 0; i < images.length; i++) {
    expect(images[i].value[ImagePackTypes.order], i);
    expect(images[i].value[ImagePackTypes.unstableOrder], i);
  }
}

void main() {
  group("shortcodes", () {
    test("normalize only to the grammar", () {
      expect(LibraryOps.normalizeShortcode("cat"), "cat");
      expect(LibraryOps.normalizeShortcode("happy cat!"), "happy_cat");
      expect(LibraryOps.normalizeShortcode("  ...  "), "image");
      expect(LibraryOps.normalizeShortcode("a" * 150).length, 100);
      expect(LibraryOps.isValidShortcode("ok_-9"), isTrue);
      expect(LibraryOps.isValidShortcode("no way"), isFalse);
    });

    test("a taken shortcode gets the next free number", () {
      expect(LibraryOps.uniqueShortcode("cat", {"dog"}), "cat");
      expect(LibraryOps.uniqueShortcode("cat", {"cat"}), "cat_2");
      expect(LibraryOps.uniqueShortcode("cat", {"cat", "cat_2"}), "cat_3");
      final long = "b" * 100;
      final next = LibraryOps.uniqueShortcode(long, {long});
      expect(next.length, 100);
      expect(next.endsWith("_2"), isTrue);
    });
  });

  group("pack edits", () {
    test("remove renumbers what is left", () {
      final out = LibraryOps.removeImages(pack(["a", "b", "c"]), {"b"});
      expect(keysOf(out), ["a", "c"]);
      expectNumbered(out);
      expect(out["pack"], {"display_name": "P"});
    });

    test("remove of a gone image changes nothing", () {
      final input = pack(["a"]);
      expect(LibraryOps.removeImages(input, {"x"}), same(input));
    });

    test("clone puts copies after the last selected, new shortcodes", () {
      final out = LibraryOps.cloneImages(pack(["a", "b", "c"]), ["a", "b"]);
      expect(keysOf(out), ["a", "b", "a_2", "b_2", "c"]);
      expect(out["images"]["a_2"]["url"], "mxc://s/a");
      expectNumbered(out);
    });

    test("reorder keeps images it doesn't name, after", () {
      final out = LibraryOps.reorder(pack(["a", "b", "c", "d"]), ["c", "a"]);
      expect(keysOf(out), ["c", "a", "b", "d"]);
      expectNumbered(out);
    });

    test("reorder skips names no longer in the pack", () {
      final out = LibraryOps.reorder(pack(["a", "b"]), ["x", "b", "a"]);
      expect(keysOf(out), ["b", "a"]);
    });

    test("nudge moves a block one step", () {
      expect(LibraryOps.nudge(["a", "b", "c", "d"], {"c", "d"}, -1),
          ["a", "c", "d", "b"]);
      expect(LibraryOps.nudge(["a", "b", "c"], {"a"}, 1), ["b", "a", "c"]);
      expect(LibraryOps.nudge(["a", "b"], {"a"}, -1), ["a", "b"]);
      expect(LibraryOps.nudge(["a", "b"], {"b"}, 1), ["a", "b"]);
    });

    test("moveBefore drops a block before a tile", () {
      expect(LibraryOps.moveBefore(["a", "b", "c", "d"], {"d", "b"}, "a"),
          ["b", "d", "a", "c"]);
      expect(
          LibraryOps.moveBefore(["a", "b", "c"], {"a"}, null), ["b", "c", "a"]);
      expect(LibraryOps.moveBefore(["a", "b"], {"a"}, "a"), ["a", "b"]);
    });

    test("an image added by another client keeps its place", () {
      final content = pack(["a", "b"]);
      (content["images"] as Map)["new"] = {"url": "mxc://s/new"};
      final out = LibraryOps.reorder(content, ["b", "a"]);
      expect(keysOf(out).toSet(), {"a", "b", "new"});
      expect(keysOf(out).sublist(0, 2), ["b", "a"]);
    });
  });

  group("transfer", () {
    test("copy reuses the file and renames clashes", () {
      final t = LibraryOps.transfer(
          source: pack(["cat", "dog"]),
          target: pack(["cat"], name: "T"),
          keys: ["cat", "dog"],
          move: false);
      expect(t.source, isNull);
      expect(keysOf(t.target), ["cat", "cat_2", "dog"]);
      expect(t.target["images"]["cat_2"]["url"], "mxc://s/cat");
      expect(t.renamed, {"cat": "cat_2"});
      expect(t.target["pack"], {"display_name": "T"});
      expectNumbered(t.target);
    });

    test("move also removes from the source", () {
      final t = LibraryOps.transfer(
          source: pack(["a", "b", "c"]),
          target: pack([]),
          keys: ["c", "a"],
          move: true);
      // Pack order, not selection order.
      expect(keysOf(t.target), ["a", "c"]);
      expect(keysOf(t.source!), ["b"]);
    });

    test("images gone from the source are skipped", () {
      final t = LibraryOps.transfer(
          source: pack(["a"]), target: pack([]), keys: ["a", "x"], move: true);
      expect(keysOf(t.target), ["a"]);
      expect(keysOf(t.source!), isEmpty);
    });

    test("a target that would be too big is refused", () {
      final big = pack([for (var i = 0; i < 700; i++) "image_number_$i"]);
      final source = {
        "images": {
          "x": {"url": "mxc://s/${"y" * 2000}"}
        }
      };
      expect(
          () => LibraryOps.transfer(
              source: source, target: big, keys: ["x"], move: true),
          throwsA(isA<PackFullException>()));
    });

    test("a new pack keeps the source's usage", () {
      final source = pack(["a", "b"]);
      source["pack"] = {
        "display_name": "S",
        "usage": ["sticker"]
      };
      final out = LibraryOps.newPackFrom("New", source, ["b"]);
      expect(out["pack"], {
        "display_name": "New",
        "usage": ["sticker"]
      });
      expect(keysOf(out), ["b"]);
    });

    test("a deleted pack is an empty images map", () {
      expect(LibraryOps.deletedPack(), {"images": {}});
    });
  });

  group("GIF folders", () {
    Map<String, dynamic> gifs() => {
          "favorites": [
            {"url": "mxc://s/1", "body": "one"},
            {"url": "mxc://s/2", "folder": "Cats"},
            {
              "url": "mxc://s/3",
              "folder": "Dogs",
              "file": {"k": 1}
            },
          ],
          "other": true,
        };

    test("folders and Unsorted", () {
      final c = gifs();
      expect(GifFolders.folders(c), ["Cats", "Dogs"]);
      expect([for (final e in GifFolders.inFolder(c, null)) e["url"]],
          ["mxc://s/1"]);
    });

    test("move keeps everything else in the entry and the content", () {
      final c = GifFolders.moveTo(gifs(), {"mxc://s/3", "mxc://s/1"}, "Cats");
      final list = GifFolders.entries(c);
      expect(list[0], {"url": "mxc://s/1", "body": "one", "folder": "Cats"});
      expect(list[2], {
        "url": "mxc://s/3",
        "folder": "Cats",
        "file": {"k": 1}
      });
      expect(c["other"], true);
    });

    test("move to Unsorted drops the field", () {
      final c = GifFolders.moveTo(gifs(), {"mxc://s/2"}, null);
      expect(GifFolders.entries(c)[1], {"url": "mxc://s/2"});
    });

    test("an empty folder is kept in the folder list", () {
      final c = GifFolders.addFolder(gifs(), "Empty");
      expect(GifFolders.folders(c), ["Cats", "Dogs", "Empty"]);
      expect(GifFolders.inFolder(c, "Empty"), isEmpty);
    });

    test("rename and delete", () {
      var c = GifFolders.rename(gifs(), "Cats", "Kittens");
      expect(GifFolders.folders(c), ["Kittens", "Dogs"]);
      expect(GifFolders.entries(c)[1]["folder"], "Kittens");
      c = GifFolders.delete(c, "Dogs");
      expect(GifFolders.folders(c), ["Kittens"]);
      expect(GifFolders.entries(c)[2].containsKey("folder"), isFalse);
      expect(GifFolders.entries(c).length, 3);
    });

    test("save to a folder adds, or only moves a GIF saved already", () {
      var c = GifFolders.saveTo(gifs(), {"url": "mxc://s/9"}, "New");
      expect(GifFolders.entries(c).last, {"url": "mxc://s/9", "folder": "New"});
      expect(GifFolders.folders(c), contains("New"));
      c = GifFolders.saveTo(c, {"url": "mxc://s/1", "body": "x"}, "Dogs");
      expect(GifFolders.entries(c).length, 4);
      expect(GifFolders.entries(c)[0],
          {"url": "mxc://s/1", "body": "one", "folder": "Dogs"});
    });

    test("remove", () {
      final c = GifFolders.remove(gifs(), {"mxc://s/2"});
      expect([for (final e in GifFolders.entries(c)) e["url"]],
          ["mxc://s/1", "mxc://s/3"]);
    });

    test("folder names are trimmed, empty ones refused", () {
      expect(GifFolders.cleanName("  Fun "), "Fun");
      expect(GifFolders.cleanName("   "), isNull);
    });
  });
}
