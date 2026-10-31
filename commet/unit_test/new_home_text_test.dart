import 'dart:convert';

import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_text_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet (New Home cards, round 4): the Text card.

void main() {
  group("Buttons", () {
    test("a link must be a web address", () {
      bool ok(String t) =>
          TextButtonTarget("Go", kind: TextButtonTarget.link, target: t).valid;
      expect(ok("https://vommet.app"), isTrue);
      expect(ok("http://example.org/a"), isTrue);
      expect(ok("javascript:alert(1)"), isFalse);
      expect(ok("vommet.app"), isFalse);
      expect(ok(""), isFalse);
    });

    test("a room is an id or an address; a screen is a known one", () {
      expect(
          const TextButtonTarget("Hi",
                  kind: TextButtonTarget.room, target: "#vommet:nether.im")
              .valid,
          isTrue);
      expect(
          const TextButtonTarget("Hi",
                  kind: TextButtonTarget.room, target: "@me:nether.im")
              .valid,
          isFalse);
      expect(
          const TextButtonTarget("Settings",
                  kind: TextButtonTarget.screen, target: "settings")
              .valid,
          isTrue);
      expect(
          const TextButtonTarget("?",
                  kind: TextButtonTarget.screen, target: "planets")
              .valid,
          isFalse);
      expect(
          const TextButtonTarget(" ",
                  kind: TextButtonTarget.screen, target: "settings")
              .valid,
          isFalse);
    });

    test("read: broken ones left out, at most three", () {
      final buttons = readTextButtons([
        {"label": "A", "kind": "link", "target": "https://a.org"},
        {"label": "B", "kind": "teleport", "target": "x"},
        "nope",
        {"label": "C", "kind": "room", "target": "!r:x"},
        {"label": "D", "kind": "screen", "target": "guides"},
        {"label": "E", "kind": "screen", "target": "settings"},
      ]);
      expect(buttons.map((b) => b.label), ["A", "C", "D"]);
      expect(readTextButtons("nope"), isEmpty);
    });
  });

  group("Body", () {
    test("images on a line of their own, with mxc URLs, are images", () {
      final blocks = textBlocks("## Hello\n\nSome text\n"
          "![a cat](mxc://x.org/abc)\n"
          "More ![inline](mxc://x.org/def) text\n"
          "![web](https://x.org/a.png)\n"
          "![](mxc://x.org/ghi)");
      expect(blocks, const [
        TextBlock.text("## Hello\n\nSome text"),
        TextBlock.image("mxc://x.org/abc", alt: "a cat"),
        TextBlock.text(
            "More ![inline](mxc://x.org/def) text\n![web](https://x.org/a.png)"),
        TextBlock.image("mxc://x.org/ghi"),
      ]);
    });

    test("collapses after about 12 lines", () {
      expect(textCollapses(List.filled(12, "line").join("\n")), isFalse);
      expect(textCollapses(List.filled(13, "line").join("\n")), isTrue);
      expect(
          textCollapses("one\n![i](mxc://x/a)\ntwo\n![j](mxc://x/b)"), isTrue);
    });

    test("too long a body is cut at 20,000 characters when read", () {
      expect(readTextBody("a" * 20005)!.length, maxTextBody);
      expect(readTextBody(""), isNull);
      expect(readTextBody(3), isNull);
    });
  });

  group("Toolbar", () {
    test("bold wraps the selection, or puts a pair at the cursor", () {
      expect(wrapSelection("say hi", 4, 6, "**"),
          (text: "say **hi**", start: 6, end: 8));
      expect(
          wrapSelection("say", 3, 3, "_"), (text: "say__", start: 4, end: 4));
    });

    test("headings and lists prefix every line touched", () {
      expect(prefixLines("a\nb\nc", 2, 4, "- "),
          (text: "a\n- b\n- c", start: 2, end: 9));
      expect(prefixLines("x\ny", 0, 3, "", numbered: true).text, "1. x\n2. y");
      expect(prefixLines("", 0, 0, "## ").text, "## ");
    });

    test("an image goes on a line of its own", () {
      final edit = insertSnippet("ab", 1, 1, "![i](mxc://x/a)", ownLine: true);
      expect(edit.text, "a\n![i](mxc://x/a)\nb");
      expect(textBlocks(edit.text)[1].isImage, isTrue);
    });
  });

  group("Stored in the Home layout", () {
    test("round-trip; may be added more than once", () {
      final layout = const HomeLayout([]).add(HomeLayout.textCard);
      expect(HomeLayout.multiTypes, contains(HomeLayout.textCard));
      expect(layout.canAdd(HomeLayout.textCard), isTrue);
      final card = layout.cards.single.copyWith(
          name: "Welcome",
          body: "Hello **there**",
          buttons: const [
            TextButtonTarget("Rules",
                kind: TextButtonTarget.room, target: "#rules:x.org")
          ]);
      expect(card.configurable, isTrue);
      final json = jsonDecode(jsonEncode(card.toJson()));
      expect(HomeCard.fromJson(json), card);
      expect(HomeCard.fromJson(json)!.buttons.single.target, "#rules:x.org");
    });

    test("Vommet's own card keeps its preset, is read-only", () {
      final card = HomeCard.fromJson(
          {"id": "text_ab12", "type": "text", "preset": "contribute"})!;
      expect(card.type, HomeLayout.textCard);
      expect(card.preset, "contribute");
      expect(card.configurable, isFalse);
      expect(cardSummary(card), "From Vommet");
      expect(HomeCard.fromJson(card.toJson()), card);
    });

    test("not on any default page", () {
      expect(HomeLayout.knownTypes.last, HomeLayout.textCard);
      expect(
          HomeLayout.defaults.cards.any((c) => c.type == HomeLayout.textCard),
          isFalse);
    });
  });

  group("Vommet's own Text cards", () {
    test("parsed from the app's asset; broken entries left out", () {
      final presets = parseTextPresets(jsonEncode({
        "cards": {
          "contribute": {
            "title": "Help make Vommet",
            "body": "Translate, test, report.",
            "buttons": [
              {"label": "Guides", "kind": "screen", "target": "guides"}
            ]
          },
          "empty": {"title": "No body"},
          "nameless": {"body": "x"},
        }
      }));
      expect(presets.keys, ["contribute"]);
      expect(presets["contribute"]!.buttons.single.label, "Guides");
      expect(parseTextPresets("{not json"), isEmpty);
      expect(parseTextPresets('{"cards": []}'), isEmpty);
    });
  });
}
