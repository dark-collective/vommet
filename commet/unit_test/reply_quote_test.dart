import 'package:commet/main.dart';
import 'package:commet/ui/atoms/reply_quote.dart';
import 'package:commet/ui/pages/settings/categories/app/reply_style_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _long = "If we take the river route we skip the toll bridge, but it adds "
    "about a day, and the horses still need shoeing before we leave town, "
    "so somebody has to find a smith who is open on a Sunday morning.";

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 360, child: child)),
    );

void main() {
  test("style parses; unknown values fall back to quote", () {
    expect(ReplyStyle.parse("compact"), ReplyStyle.compact);
    expect(ReplyStyle.parse("quote"), ReplyStyle.quote);
    expect(ReplyStyle.parse("card"), ReplyStyle.card);
    expect(ReplyStyle.parse("bogus"), ReplyStyle.quote);
  });

  test("new installs get the Element-style quote", () {
    expect(preferences.replyStyle.defaultValue, "quote");
    expect(ReplyStyle.parse(preferences.replyStyle.defaultValue),
        ReplyStyle.quote);
  });

  test("only compact stays above the message", () {
    expect(ReplyStyle.compact.inline, isFalse);
    expect(ReplyStyle.quote.inline, isTrue);
    expect(ReplyStyle.card.inline, isTrue);
  });

  for (final style in [ReplyStyle.quote, ReplyStyle.card]) {
    testWidgets("${style.name} shows the name and text, tap jumps",
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(ReplyQuote(
          style: style,
          senderName: "Rowan",
          senderColor: Colors.green,
          body: _long,
          onTap: () => taps++)));
      expect(find.byKey(ValueKey("reply-quote-${style.name}")), findsOneWidget);
      expect(find.text("Rowan"), findsOneWidget);
      final body = tester.widget<Text>(find.text(_long));
      expect(body.maxLines, style == ReplyStyle.card ? 1 : 2);
      await tester.tap(find.text("Rowan"));
      expect(taps, 1);
    });
  }

  testWidgets("a picture shows its kind, not its file name", (tester) async {
    await tester.pumpWidget(_wrap(const ReplyQuote(
        style: ReplyStyle.card,
        senderName: "Rowan",
        body: "IMG_2041.jpg",
        media: ReplyQuoteMedia.image)));
    expect(find.text("Photo"), findsOneWidget);
    expect(find.text("IMG_2041.jpg"), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets("loading, then a message without text", (tester) async {
    await tester.pumpWidget(_wrap(const ReplyQuote(
        style: ReplyStyle.quote, senderName: null, body: null)));
    expect(find.text("Loading"), findsOneWidget);
    expect(find.text("Message not found"), findsNothing);
    await tester.pumpWidget(_wrap(const ReplyQuote(
        style: ReplyStyle.quote, senderName: "Rowan", body: null)));
    expect(find.text("Message not found"), findsOneWidget);
  });

  for (final style in ReplyStyle.values) {
    testWidgets("settings preview renders ${style.name}", (tester) async {
      await tester.pumpWidget(_wrap(ReplyStylePreview(style: style)));
      expect(find.byKey(const ValueKey("reply-style-preview")), findsOneWidget);
      expect(find.byKey(ValueKey("reply-quote-${style.name}")),
          style.inline ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
