import 'package:commet/client/matrix/forwarding/forward_content.dart';
import 'package:commet/ui/atoms/media_spoiler_cover.dart';
import 'package:commet/utils/media_spoiler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const unstable = "page.codeberg.everypizza.msc4193.spoiler";
  const unstableReason = "page.codeberg.everypizza.msc4193.spoiler.reason";

  group("parse", () {
    test("unstable keys", () {
      final s = MediaSpoiler.parse({
        "msgtype": "m.image",
        unstable: true,
        unstableReason: "Session 14 boss reveal",
      }, key: r"$a");
      expect(s, isNotNull);
      expect(s!.key, r"$a");
      expect(s.reason, "Session 14 boss reveal");
    });

    test("stable keys", () {
      final s = MediaSpoiler.parse(
          {"m.spoiler": true, "m.spoiler.reason": "ending"},
          key: r"$b");
      expect(s?.reason, "ending");
    });

    test("unstable reason wins over stable", () {
      expect(
          MediaSpoiler.reasonOf({
            unstableReason: "first",
            "m.spoiler.reason": "second",
          }),
          "first");
    });

    test("not a spoiler without a true flag", () {
      expect(MediaSpoiler.parse({"msgtype": "m.image"}, key: "x"), isNull);
      expect(MediaSpoiler.parse({unstable: false}, key: "x"), isNull);
      expect(MediaSpoiler.parse({unstable: "true"}, key: "x"), isNull);
      expect(MediaSpoiler.parse({"m.spoiler": 1}, key: "x"), isNull);
      // a reason alone doesn't make it a spoiler
      expect(MediaSpoiler.parse({unstableReason: "why"}, key: "x"), isNull);
    });

    test("blank, non-string and long reasons", () {
      expect(MediaSpoiler.reasonOf({unstableReason: "   "}), isNull);
      expect(MediaSpoiler.reasonOf({unstableReason: 5}), isNull);
      expect(MediaSpoiler.reasonOf({unstableReason: "  two\n lines "}),
          "two lines");
      final long = MediaSpoiler.reasonOf({unstableReason: "a" * 500})!;
      expect(long.length, MediaSpoiler.maxReasonLength + 1);
      expect(long.endsWith("…"), isTrue);
      // a blank unstable reason falls back to the stable one
      expect(
          MediaSpoiler.reasonOf(
              {unstableReason: " ", "m.spoiler.reason": "stable"}),
          "stable");
    });
  });

  group("serialise", () {
    test("sends only the unstable keys", () {
      expect(MediaSpoiler.contentFor(spoiler: true, reason: " Boss "),
          {unstable: true, unstableReason: "Boss"});
      expect(MediaSpoiler.contentFor(spoiler: true), {unstable: true});
      expect(MediaSpoiler.contentFor(spoiler: true, reason: "  "),
          {unstable: true});
      expect(MediaSpoiler.contentFor(spoiler: false, reason: "x"), isEmpty);
    });

    test("round trip", () {
      final content = {
        "msgtype": "m.video",
        ...MediaSpoiler.contentFor(spoiler: true, reason: "Campaign ending"),
      };
      final s = MediaSpoiler.parse(content, key: "k");
      expect(s?.reason, "Campaign ending");
    });

    test("edits keep the keys", () {
      final original = {
        "msgtype": "m.image",
        unstable: true,
        unstableReason: "r",
        "m.spoiler": true,
      };
      final edit = <String, dynamic>{"msgtype": "m.text", "body": "new"};
      MediaSpoiler.copyKeys(original, edit);
      expect(edit[unstable], true);
      expect(edit[unstableReason], "r");
      expect(edit["m.spoiler"], true);
      expect(edit.containsKey("m.spoiler.reason"), isFalse);

      final plain = <String, dynamic>{"body": "x"};
      MediaSpoiler.copyKeys({"msgtype": "m.image", unstableReason: "r"}, plain);
      expect(plain, {"body": "x"});
    });

    test("forwards keep the keys", () {
      final original = {
        "msgtype": "m.image",
        "body": "boss.png",
        "url": "mxc://example.org/abc",
        unstable: true,
        unstableReason: "boss",
      };
      for (final showSender in [false, true]) {
        final forward = ForwardContent.build(original, showSender: showSender);
        expect(MediaSpoiler.isSpoiler(forward), isTrue,
            reason: "showSender: $showSender");
        expect(MediaSpoiler.reasonOf(forward), "boss");
      }
    });
  });

  group("preview text", () {
    test("never the file name", () {
      expect(MediaSpoiler.previewText(isVideo: false), "Image (spoiler)");
      expect(MediaSpoiler.previewText(isVideo: true), "Video (spoiler)");
      expect(MediaSpoiler.previewText(), "Spoiler");
      expect(MediaSpoiler.previewText(isVideo: false, caption: " look "),
          "Image (spoiler): look");
    });

    test("from raw content", () {
      expect(
          MediaSpoiler.previewTextForContent({
            "msgtype": "m.image",
            "body": "boss_lair.png",
            "filename": "boss_lair.png",
            unstable: true,
          }),
          "Image (spoiler)");
      expect(
          MediaSpoiler.previewTextForContent({
            "msgtype": "m.video",
            "body": "trailer",
            "filename": "ending.mp4",
            "m.spoiler": true,
          }),
          "Video (spoiler): trailer");
      expect(
          MediaSpoiler.previewTextForContent({
            "msgtype": "m.file",
            "body": "x.jpg",
            unstable: true,
          }),
          "Spoiler");
      expect(
          MediaSpoiler.previewTextForContent(
              {"msgtype": "m.text", "body": "hi", unstable: true}),
          isNull);
      expect(
          MediaSpoiler.previewTextForContent(
              {"msgtype": "m.image", "body": "a.png"}),
          isNull);
    });
  });

  group("reveal state", () {
    setUp(MediaSpoilerReveal.reset);

    test("per message, hide covers again", () {
      const a = MediaSpoiler(key: r"$a");
      const b = MediaSpoiler(key: r"$b");
      expect(MediaSpoilerReveal.isHidden(a), isTrue);
      expect(MediaSpoilerReveal.isHidden(null), isFalse);

      var notified = 0;
      void listener() => notified++;
      MediaSpoilerReveal.revealed.addListener(listener);

      MediaSpoilerReveal.reveal(a.key);
      expect(MediaSpoilerReveal.isHidden(a), isFalse);
      expect(MediaSpoilerReveal.isHidden(b), isTrue);
      MediaSpoilerReveal.reveal(a.key); // no change, no notification
      expect(notified, 1);

      MediaSpoilerReveal.hide(a.key);
      expect(MediaSpoilerReveal.isHidden(a), isTrue);
      MediaSpoilerReveal.hide(a.key);
      expect(notified, 2);

      MediaSpoilerReveal.revealed.removeListener(listener);
    });

    testWidgets("tap reveals, Hide covers again", (tester) async {
      const spoiler = MediaSpoiler(key: r"$x", reason: "Boss reveal");
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 200,
              child: MediaSpoilerBuilder(
                spoiler: spoiler,
                builder: (context, hidden) => hidden
                    ? const MediaSpoilerCover(spoiler: spoiler)
                    : const Stack(children: [
                        Center(child: Text("MEDIA")),
                        Positioned(
                            right: 8,
                            top: 8,
                            child: MediaSpoilerHideChip(spoiler: spoiler)),
                      ]),
              ),
            ),
          ),
        ),
      ));

      expect(find.text("Spoiler · Tap to reveal"), findsOneWidget);
      expect(find.text("Boss reveal"), findsOneWidget);
      expect(find.text("MEDIA"), findsNothing);

      await tester.tap(find.byType(MediaSpoilerCover));
      await tester.pump();
      expect(find.text("MEDIA"), findsOneWidget);
      expect(MediaSpoilerReveal.isRevealed(spoiler.key), isTrue);

      await tester.tap(find.text("Hide"));
      await tester.pump();
      expect(find.text("MEDIA"), findsNothing);
      expect(find.text("Spoiler · Tap to reveal"), findsOneWidget);
    });

    testWidgets("no spoiler builds the media directly", (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaSpoilerBuilder(
          spoiler: null,
          builder: (context, hidden) => Text(hidden ? "COVER" : "MEDIA"),
        ),
      ));
      expect(find.text("MEDIA"), findsOneWidget);
    });
  });
}
