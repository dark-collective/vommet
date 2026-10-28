// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/atoms/reply_quote.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/reply_quote_translation.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translation_fakes.dart';

// Vommet issue 680 follow-up: in a room with "Translate this room" on, the
// message a reply quotes is translated too.
void main() {
  late Directory dir;
  late FakeEngine engine;
  late Map<String, List<int>> blobs;
  late List<TranslationModelSpec> specs;
  late int requests;
  late MessageTranslation t;
  late RoomTranslation rooms;
  late ReplyQuoteTranslation quote;

  MessageTranslation service() => MessageTranslation(
        engine: engine,
        baseDirectory: () async => dir,
        specs: specs,
        android: false,
        systemLanguage: () => "en",
        httpClient: () => MockClient((request) async {
          requests++;
          final data = blobs[request.url.pathSegments.last];
          return data == null
              ? http.Response("missing", 404)
              : http.Response.bytes(data, 200);
        }),
      );

  /// Lets the queued translation (file checks, engine) run.
  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    dir = Directory.systemTemp.createTempSync("vommet-reply-quote-test");
    engine = FakeEngine();
    blobs = {};
    requests = 0;
    specs = [spec("es", "en", blobs), spec("en", "es", blobs)];
    t = service();
    rooms = RoomTranslation(translation: t);
    quote = ReplyQuoteTranslation(translation: t, rooms: rooms);
  });

  tearDown(() {
    quote.dispose();
    dir.deleteSync(recursive: true);
  });

  test("shows the translation already made for the message", () async {
    await t.downloadRoute(t.route("es", "en")!);
    await rooms.setOn("!a", true);
    const text = "[es] nos vemos a las 5";
    final key = ReplyQuoteTranslation.keyFor("\$m", text);
    await t.translate(key, text, "es");
    final calls = engine.calls.length;

    quote.show(roomId: "!a", eventId: "\$m", text: text);
    expect(quote.translated, "es-en: $text");
    await settle();
    expect(engine.calls.length, calls, reason: "not translated twice");
  });

  test("translates through the room queue when the models are there", () async {
    await t.downloadRoute(t.route("es", "en")!);
    await rooms.setOn("!a", true);
    var changes = 0;
    quote.addListener(() => changes++);

    quote.show(roomId: "!a", eventId: "\$m", text: "[es] hola");
    expect(quote.translated, isNull, reason: "the original until it's done");
    await settle();
    expect(quote.translated, "es-en: [es] hola");
    expect(changes, greaterThan(0));
    expect(
        rooms.wasAutoTranslated(
            ReplyQuoteTranslation.keyFor("\$m", "[es] hola")),
        isTrue,
        reason: "same key as the message itself");
  });

  test("never asks to download: missing models leave the original", () async {
    await rooms.setOn("!a", true);
    quote.show(roomId: "!a", eventId: "\$m", text: "[es] hola");
    await settle();
    expect(quote.translated, isNull);
    expect(requests, 0);
    expect(engine.calls, isEmpty);

    // The message itself got the models: the quote follows.
    await t.downloadRoute(t.route("es", "en")!);
    await settle();
    expect(quote.translated, "es-en: [es] hola");
  });

  test("back to the original when the room mode is off", () async {
    await t.downloadRoute(t.route("es", "en")!);
    await rooms.setOn("!a", true);
    quote.show(roomId: "!a", eventId: "\$m", text: "[es] hola");
    await settle();
    expect(quote.translated, isNotNull);

    await rooms.setOn("!a", false);
    expect(quote.translated, isNull);
    await rooms.setOn("!a", true);
    expect(quote.translated, "es-en: [es] hola");
  });

  test("nothing while the room mode is off", () async {
    await t.downloadRoute(t.route("es", "en")!);
    quote.show(roomId: "!b", eventId: "\$m", text: "[es] hola");
    await settle();
    expect(quote.translated, isNull);
    expect(engine.calls, isEmpty);
  });

  test("messages already in your language stay as they are", () async {
    await t.downloadRoute(t.route("es", "en")!);
    await rooms.setOn("!a", true);
    quote.show(roomId: "!a", eventId: "\$m", text: "[en] see you at 5");
    await settle();
    expect(quote.translated, isNull);
    expect(engine.calls, isEmpty);
  });

  test("an edit is translated anew; clear drops it", () async {
    await t.downloadRoute(t.route("es", "en")!);
    await rooms.setOn("!a", true);
    quote.show(roomId: "!a", eventId: "\$m", text: "[es] a las 5");
    await settle();
    quote.show(roomId: "!a", eventId: "\$m", text: "[es] a las 6");
    await settle();
    expect(quote.translated, "es-en: [es] a las 6");

    quote.clear();
    expect(quote.translated, isNull);
  });

  group("the 文A mark", () {
    Widget wrap(Widget child) =>
        MaterialApp(home: Scaffold(body: SizedBox(width: 360, child: child)));

    for (final style in [ReplyStyle.quote, ReplyStyle.card]) {
      testWidgets("${style.name}: after the name only when translated",
          (tester) async {
        await tester.pumpWidget(wrap(ReplyQuote(
            style: style,
            senderName: "Rowan",
            body: "see you at 5",
            translated: true)));
        expect(find.text("Rowan"), findsOneWidget);
        expect(find.text("see you at 5"), findsOneWidget);
        expect(find.byKey(const ValueKey("reply-quote-translated")),
            findsOneWidget);

        await tester.pumpWidget(wrap(ReplyQuote(
            style: style, senderName: "Rowan", body: "nos vemos a las 5")));
        expect(
            find.byKey(const ValueKey("reply-quote-translated")), findsNothing);
      });
    }

    testWidgets("a long name still ellipsizes beside the mark", (tester) async {
      await tester.pumpWidget(wrap(ReplyQuote(
          style: ReplyStyle.card,
          senderName: "R" * 200,
          body: "hola",
          translated: true)));
      expect(tester.takeException(), isNull);
      expect(
          find.byKey(const ValueKey("reply-quote-translated")), findsOneWidget);
    });
  });
}
