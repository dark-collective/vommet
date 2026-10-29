// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/molecules/composer_translation.dart';
import 'package:commet/utils/translation/composer_translation.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/paragraph_translation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translation_fakes.dart';

// Vommet issue 680 phase 2: translating what you write.
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
    dir = Directory.systemTemp.createTempSync("vommet-compose-test");
    engine = FakeEngine();
    blobs = {};
    specs = [
      spec("es", "en", blobs),
      spec("en", "es", blobs),
      spec("de", "en", blobs),
      spec("en", "de", blobs),
      spec("en", "fr", blobs),
    ];
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group("target language from recent messages", () {
    String? detect(String text) => service().detectLanguage(text);

    test("the language most recent messages are in", () {
      expect(
          dominantLanguage(
              ["[es] hola", "[de] hallo", "[es] qué tal", "[es] bien"], detect),
          "es");
    });

    test("a tie goes to the newest", () {
      expect(dominantLanguage(["[de] hallo", "[es] hola"], detect), "de");
    });

    test("unreliable guesses, blanks and untagged text don't count", () {
      expect(
          dominantLanguage(
              ["[es] unsure hola", "  ", "no tag", "[de] hallo"], detect),
          "de");
      expect(dominantLanguage(["[es] unsure hola", "no tag"], detect), isNull);
      expect(dominantLanguage(const [], detect), isNull);
    });

    test("only the newest few count", () {
      final texts = [
        for (var i = 0; i < 10; i++) "[de] hallo $i",
        for (var i = 0; i < 20; i++) "[es] hola $i",
      ];
      expect(dominantLanguage(texts, detect), "de");
      expect(dominantLanguage(texts, detect, limit: 30), "es");
    });
  });

  group("per-room language", () {
    test("a pick is remembered per room, newest pick first", () async {
      final prefs = ComposerTranslationPrefs.instance;
      expect(prefs.targetFor("!a"), isNull);

      await prefs.setTarget("!a", "es");
      await prefs.setTarget("!b", "de");
      await prefs.setTarget("!a", "fr");

      expect(prefs.targetFor("!a"), "fr");
      expect(prefs.targetFor("!b"), "de");
      expect(prefs.recentLanguages, ["fr", "de", "es"]);
    });

    test("recent languages are bounded", () async {
      final prefs = ComposerTranslationPrefs.instance;
      const codes = ["es", "de", "fr", "it", "pt", "nl", "pl", "sv", "fi"];
      for (final c in codes) {
        await prefs.setTarget("!room", c);
      }
      expect(prefs.recentLanguages.length, ComposerTranslationPrefs.maxRecent);
      expect(prefs.recentLanguages.first, "fi");
      expect(prefs.recentLanguages, isNot(contains("es")));
    });

    test("a damaged preference reads as empty", () async {
      await Preference.preferences!
          .setString("message_translation_compose", "not json");
      expect(ComposerTranslationPrefs.instance.targetFor("!a"), isNull);
      expect(ComposerTranslationPrefs.instance.recentLanguages, isEmpty);
    });

    test("a pick wins over the detected language", () async {
      final t = ComposerTranslation(
          roomId: "!dm",
          translation: service(),
          recentTextsFromOthers: () => ["[de] hallo", "[de] wie geht's"]);
      expect(t.target, "de");
      await ComposerTranslationPrefs.instance.setTarget("!dm", "es");
      expect(t.target, "es");
    });

    test("the button in every room, only with a draft, and only when on",
        () async {
      ComposerTranslation make(String room) => ComposerTranslation(
          roomId: room,
          translation: service(),
          recentTextsFromOthers: () => const []);
      // Off until turned on in Settings (phone composer round 2).
      expect(ComposerTranslationPrefs.buttonPreference.value, isFalse);
      expect(make("!dm").showChip("hello"), isFalse);
      await ComposerTranslationPrefs.buttonPreference.set(true);
      expect(make("!dm").showChip("hello"), isTrue);
      expect(make("!group").showChip("hello"), isTrue);
      expect(make("!dm").showChip("  "), isFalse);
    });
  });

  group("paragraph targets", () {
    ComposerTranslation make() => ComposerTranslation(
        roomId: "!p",
        translation: service(),
        recentTextsFromOthers: () => const []);

    test("a new paragraph inherits the target of the one above", () {
      final t = make();
      t.onDraftChanged("hello");
      t.setParagraphTarget(0, "es");
      t.onDraftChanged("hello\n");
      t.onDraftChanged("hello\nthere");
      expect(t.resolved, ["es", "es"]);
      expect(t.translatedRuns, [(first: 0, last: 1, to: "es")]);
      t.setParagraphTarget(1, "de");
      expect(t.resolved, ["es", "de"]);
      expect(t.translatedRuns,
          [(first: 0, last: 0, to: "es"), (first: 1, last: 1, to: "de")]);
    });

    test("Don't translate, whole message, commands", () {
      final t = make();
      t.onDraftChanged("one\ntwo");
      t.useForWholeMessage("fr");
      expect(t.resolved, ["fr", "fr"]);
      t.setParagraphTarget(1, keepAsWritten);
      expect(t.resolved, ["fr", null]);
      expect(t.targetOf(1), keepAsWritten);
      t.onDraftChanged("/me one\ntwo");
      expect(t.resolved, [null, null], reason: "commands go out as typed");
    });

    test("without room translation nothing is translated by default", () {
      final t = make();
      t.onDraftChanged("hello\nthere");
      expect(t.defaultTarget, isNull);
      expect(t.resolved, [null, null]);
      expect(t.translatedRuns, isEmpty);
    });
  });

  test("the menu lists reachable languages, used ones first", () {
    final t = service();
    expect(menuLanguages(t, "en", const []), ["fr", "de", "es"]);
    expect(menuLanguages(t, "en", const ["es", "it"]), ["es", "fr", "de"]);
    // Spanish reaches English directly, German and French through it.
    expect(menuLanguages(t, "es", const []), ["en", "fr", "de"]);
  });

  group("translating a draft", () {
    Future<bool?> yes(String from, String to, List<TranslationModelSpec> m) =>
        Future.value(true);

    test("translates, after asking to download", () async {
      final asked = <String>[];
      final result = await translateDraft(service(),
          draft: "hello\nthere", to: "es", confirmDownload: (from, to, m) {
        asked.add("$from-$to ${m.length}");
        return Future.value(true);
      });
      expect(result, isA<DraftTranslated>());
      result as DraftTranslated;
      expect(result.text, "en-es: hello\nen-es: there");
      expect((result.from, result.to), ("en", "es"));
      expect(asked, ["en-es 1"]);
    });

    test("already in the language: send as written", () async {
      expect(
          await translateDraft(service(),
              draft: "[es] hola", to: "es", confirmDownload: yes),
          isA<DraftUnchanged>());
    });

    test("the live preview's translation is used as is", () async {
      final result = await translateDraft(service(),
          draft: "hello", to: "es", confirmDownload: yes, ready: "hola");
      expect((result as DraftTranslated).text, "hola");
      expect(engine.calls, isEmpty);
    });

    test("blocked: no language, no model, download declined", () async {
      expect(
          await translateDraft(service(),
              draft: "hello", to: null, confirmDownload: yes),
          isA<DraftBlocked>());
      final none = await translateDraft(service(),
          draft: "[de] hallo", to: "ja", confirmDownload: yes);
      expect((none as DraftBlocked).message, contains("Can't translate"));
      final declined = await translateDraft(service(),
          draft: "hello",
          to: "es",
          confirmDownload: (from, to, missing) => Future.value(false));
      expect(declined, isA<DraftBlocked>());
      expect(engine.calls, isEmpty, reason: "nothing ran");
    });

    test("a failed download blocks instead of sending", () async {
      final t = service();
      blobs.clear();
      final result = await translateDraft(t,
          draft: "hello", to: "es", confirmDownload: yes);
      expect(result, isA<DraftBlocked>());
    });
  });

  test("short codes for the chip", () {
    expect(shortLanguageCode("es"), "ES");
    expect(shortLanguageCode("zh-Hant"), "ZH");
    expect(downloadTitle("en", "es"), "Download the Spanish language model?");
    expect(downloadTitle("de", "en"), "Download the German language model?");
  });
}
