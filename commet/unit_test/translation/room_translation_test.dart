// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/molecules/composer_translation.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translation_fakes.dart';

// Vommet issue 680 phase 2: "Translate this room".
void main() {
  late Directory dir;
  late FakeEngine engine;
  late Map<String, List<int>> blobs;
  late List<TranslationModelSpec> specs;

  MessageTranslation service() => MessageTranslation(
        engine: engine,
        baseDirectory: () async => dir,
        specs: specs,
        android: false,
        systemLanguage: () => "en",
        httpClient: () => MockClient((request) async {
          final data = blobs[request.url.pathSegments.last];
          return data == null
              ? http.Response("missing", 404)
              : http.Response.bytes(data, 200);
        }),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    SentTranslations.instance.reload();
    dir = Directory.systemTemp.createTempSync("vommet-room-translation-test");
    engine = FakeEngine();
    blobs = {};
    specs = [
      spec("es", "en", blobs),
      spec("en", "es", blobs),
      spec("de", "en", blobs),
      spec("en", "de", blobs),
    ];
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group("per-room settings", () {
    test("off by default; writing is translated by default once on", () {
      final s = RoomTranslationSettings.fromJson(null);
      expect((s.on, s.from, s.translateWriting), (false, null, true));
      final back = RoomTranslationSettings.fromJson(
          const RoomTranslationSettings(on: true, from: "es").toJson());
      expect((back.on, back.from, back.translateWriting), (true, "es", true));
      expect(RoomTranslationSettings.fromJson({"on": true, "from": "xx"}).from,
          isNull);
    });

    test("kept per room, and survive a restart", () async {
      final rooms = RoomTranslation(translation: service());
      await rooms.setOn("!a", true);
      await rooms.setFrom("!a", "es");
      await rooms.setTranslateWriting("!b", false);

      final again = RoomTranslation(translation: service());
      expect(again.isOn("!a"), isTrue);
      expect(again.translatesWriting("!a"), isTrue);
      expect(again.settingsFor("!a").from, "es");
      expect(again.isOn("!b"), isFalse);
      expect(again.settingsFor("!b").translateWriting, isFalse);

      await again.setOn("!a", false);
      expect(again.translatesWriting("!a"), isFalse);
      expect(again.settingsFor("!a").from, "es", reason: "kept for next time");
    });

    test("translating what I write works without the room translated",
        () async {
      final rooms = RoomTranslation(translation: service());
      expect(rooms.translatesWriting("!c"), isFalse);
      await rooms.setTranslateWriting("!c", true);
      expect((rooms.isOn("!c"), rooms.translatesWriting("!c")), (false, true));

      // Reading on and off again leaves an explicit choice alone.
      await rooms.setOn("!c", true);
      await rooms.setOn("!c", false);
      final again = RoomTranslation(translation: service());
      expect(again.translatesWriting("!c"), isTrue);

      await again.setTranslateWriting("!c", false);
      await again.setOn("!c", true);
      expect(again.translatesWriting("!c"), isFalse);
    });

    test("saved before writing was its own switch: follows the room", () {
      final legacy =
          RoomTranslationSettings.fromJson({"on": true, "write": true});
      expect((legacy.writing, legacy.writesTranslated), (null, true));
      expect(
          RoomTranslationSettings.fromJson({"on": false, "write": true})
              .writesTranslated,
          isFalse);
    });

    test("the picked language wins over the detected one", () async {
      final rooms = RoomTranslation(translation: service());
      expect(rooms.roomLanguage("!a", () => "de"), "de");
      await rooms.setFrom("!a", "es");
      expect(rooms.roomLanguage("!a", () => "de"), "es");
      await rooms.setFrom("!a", null);
      expect(rooms.roomLanguage("!a", () => null), isNull);
    });
  });

  group("reading", () {
    test("asks once per room and language pair", () async {
      final rooms = RoomTranslation(translation: service());
      var asked = 0;
      Future<bool?> confirm(
          String from, String to, List<TranslationModelSpec> m) async {
        asked++;
        return true;
      }

      await rooms.setOn("!a", true);
      final results = await Future.wait([
        rooms.ensureModels("!a", "es", "en", confirm),
        rooms.ensureModels("!a", "es", "en", confirm),
      ]);
      expect(results, [true, true]);
      expect(asked, 1);
      expect(rooms.downloading, isEmpty);

      // Downloaded now: another room doesn't ask either.
      expect(await rooms.ensureModels("!b", "es", "en", confirm), isTrue);
      expect(asked, 1);
    });

    test("no means no for the session; switching off and on asks again",
        () async {
      final rooms = RoomTranslation(translation: service());
      var asked = 0;
      Future<bool?> no(String f, String t, List<TranslationModelSpec> m) async {
        asked++;
        return false;
      }

      await rooms.setOn("!a", true);
      expect(await rooms.ensureModels("!a", "de", "en", no), isFalse);
      expect(await rooms.ensureModels("!a", "de", "en", no), isFalse);
      expect(asked, 1);

      await rooms.setOn("!a", false);
      await rooms.setOn("!a", true);
      expect(await rooms.ensureModels("!a", "de", "en", no), isFalse);
      expect(asked, 2);
    });

    test("a message that couldn't ask leaves the question to the next",
        () async {
      final rooms = RoomTranslation(translation: service());
      Future<bool?> gone(String f, String t, List<TranslationModelSpec> m) =>
          Future.value(null);
      var asked = 0;
      Future<bool?> yes(String f, String t, List<TranslationModelSpec> m) {
        asked++;
        return Future.value(true);
      }

      expect(await rooms.ensureModels("!a", "es", "en", gone), isFalse);
      expect(await rooms.ensureModels("!a", "es", "en", yes), isTrue);
      expect(asked, 1);
    });

    test("translates queued messages one by one, skipping gone ones", () async {
      final t = service();
      final rooms = RoomTranslation(translation: t);
      await rooms.setOn("!a", true);
      Future<bool?> yes(String f, String to, List<TranslationModelSpec> m) =>
          Future.value(true);

      final done = await Future.wait([
        rooms.autoTranslate("!a", "k1", "[es] hola", "es",
            wanted: () => true, confirm: yes),
        rooms.autoTranslate("!a", "k2", "[es] adiós", "es",
            wanted: () => false, confirm: yes),
        rooms.autoTranslate("!a", "k3", "[de] hallo", "de",
            wanted: () => true, confirm: yes),
      ]);

      expect(done, [true, true, true]);
      expect(
          (t.stateFor("k1").value as TranslationDone).text, "es-en: [es] hola");
      expect(t.stateFor("k2").value, isA<TranslationIdle>());
      expect((t.stateFor("k3").value as TranslationDone).text,
          "de-en: [de] hallo");
      expect(rooms.wasAutoTranslated("k1"), isTrue);
      expect(rooms.wasAutoTranslated("k2"), isFalse);
    });

    test("nothing runs once the room mode is off", () async {
      final t = service();
      final rooms = RoomTranslation(translation: t);
      await t.downloadRoute(t.route("es", "en")!);
      Future<bool?> yes(String f, String to, List<TranslationModelSpec> m) =>
          Future.value(true);
      await rooms.autoTranslate("!off", "k", "[es] hola", "es",
          wanted: () => true, confirm: yes);
      expect(t.stateFor("k").value, isA<TranslationIdle>());
      expect(engine.calls, isEmpty);
    });
  });

  group("your messages sent translated", () {
    test("remembered per room by the text sent, and kept small", () async {
      final store = SentTranslations.instance;
      await store.remember("!a",
          sent: "hola", original: "hello", language: "es");
      expect(store.lookup("!a", "hola ")?.original, "hello");
      expect(store.lookup("!a", "hola")?.language, "es");
      expect(store.lookup("!b", "hola"), isNull);

      for (var i = 0; i < SentTranslations.maxEntries + 5; i++) {
        await store.remember("!a",
            sent: "mensaje $i", original: "message $i", language: "es");
      }
      expect(store.length, SentTranslations.maxEntries);
      expect(store.lookup("!a", "hola"), isNull, reason: "oldest goes first");
      expect(store.lookup("!a", "mensaje 0"), isNull);
      expect(store.lookup("!a", "mensaje 104")?.original, "message 104");

      store.reload();
      expect(store.length, SentTranslations.maxEntries,
          reason: "kept on the device");
      expect(store.lookup("!a", "mensaje 5")?.original, "message 5");
    });

    test("a damaged store reads as empty", () async {
      await Preference.preferences!
          .setString("message_translation_sent", "[[1, 2]]");
      SentTranslations.instance.reload();
      expect(SentTranslations.instance.length, 0);
    });
  });

  group("sending in a translated room", () {
    late MessageTranslation t;
    late RoomTranslation rooms;

    ComposerTranslation makeComposer() => ComposerTranslation(
        roomId: "!a",
        translation: t,
        rooms: rooms,
        recentTextsFromOthers: () => ["[es] hola", "[es] qué tal"],
        confirmDownload: (context, title, prompt) async => true);

    setUp(() {
      t = service();
      rooms = RoomTranslation(translation: t);
    });

    Future<BuildContext> context(WidgetTester tester) async {
      late BuildContext captured;
      await tester.pumpWidget(Builder(builder: (c) {
        captured = c;
        return const SizedBox();
      }));
      return captured;
    }

    testWidgets("sends the translation and remembers what you wrote",
        (tester) async {
      final c = await context(tester);
      await tester.runAsync(() async {
        await rooms.setOn("!a", true);
        final composer = makeComposer();
        expect(composer.writeMode, isTrue);
        expect(composer.target, "es");
        final out = await composer.prepareSend(c, "hello");
        expect(out, "en-es: hello");
        composer.onSent(out!);
        expect(SentTranslations.instance.lookup("!a", "en-es: hello")?.original,
            "hello");
      });
    });

    testWidgets("blocked: keeps the draft and says why", (tester) async {
      final c = await context(tester);
      await tester.runAsync(() async {
        await rooms.setOn("!a", true);
        await rooms.setFrom("!a", "ja"); // no model reaches Japanese
        final composer = makeComposer();
        expect(await composer.prepareSend(c, "hello"), isNull);
        expect(composer.error, startsWith("Not sent."));
      });
    });

    testWidgets("as written: room mode off, commands, already in the language",
        (tester) async {
      final c = await context(tester);
      await tester.runAsync(() async {
        final composer = makeComposer();
        expect(await composer.prepareSend(c, "hello"), "hello");
        await rooms.setOn("!a", true);
        expect(await composer.prepareSend(c, "/me waves"), "/me waves");
        expect(await composer.prepareSend(c, "[es] hola"), "[es] hola");
        expect(engine.calls, isEmpty);
      });
    });

    testWidgets("per paragraph, each in its own language", (tester) async {
      final c = await context(tester);
      await tester.runAsync(() async {
        final composer = makeComposer();
        const draft = "hello\nthere\nbye";
        composer.onDraftChanged(draft);
        composer.setParagraphTarget(0, "es");
        composer.setParagraphTarget(1, "de");
        final out = await composer.prepareSend(c, draft);
        expect(out, "en-es: hello\nen-de: there\nbye");
        composer.onSent(out!);
        final note = SentTranslations.instance.lookup("!a", out);
        expect(note?.original, draft);
        expect(note?.language, "es+de");
        expect(languageNames(note!.language), "Spanish + German");
      });
    });

    testWidgets("a paragraph that can't be translated blocks the send",
        (tester) async {
      final c = await context(tester);
      await tester.runAsync(() async {
        final composer = makeComposer();
        const draft = "hello\n\nthere";
        composer.onDraftChanged(draft);
        composer.setParagraphTarget(0, "es");
        composer.setParagraphTarget(2, "ja"); // no model reaches Japanese
        expect(await composer.prepareSend(c, draft), isNull);
        expect(composer.error, startsWith("Not sent. Paragraph 2 (Japanese)"));
      });
    });
  });
}
