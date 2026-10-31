import 'dart:convert';
import 'dart:io';

import 'package:commet/ui/molecules/timeline_events/message_translation_fold.dart';
import 'package:commet/ui/pages/settings/categories/app/translation_settings_page.dart';
import 'package:commet/ui/pages/settings/settings_tab.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'translation_fakes.dart';

void main() {
  late Directory dir;
  late FakeEngine engine;
  late Map<String, List<int>> blobs;
  late List<TranslationModelSpec> specs;
  late int requests;

  MessageTranslation service({String system = "en", bool android = false}) =>
      MessageTranslation(
        engine: engine,
        baseDirectory: () async => dir,
        specs: specs,
        android: android,
        systemLanguage: () => system,
        httpClient: () => MockClient((request) async {
          requests++;
          final data = blobs[request.url.pathSegments.last];
          return data == null
              ? http.Response("missing", 404)
              : http.Response.bytes(data, 200);
        }),
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync("vommet-translation-test");
    engine = FakeEngine();
    blobs = {};
    requests = 0;
    specs = [
      spec("es", "en", blobs),
      spec("en", "es", blobs),
      spec("de", "en", blobs),
      spec("en", "de", blobs),
      spec("ja", "en", blobs, platforms: ModelPlatforms.desktop),
    ];
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group("languages", () {
    test("CLD2 and locale codes map onto the catalog", () {
      expect(MessageTranslation.normalizeLanguage("iw"), "he");
      expect(MessageTranslation.normalizeLanguage("no"), "nb");
      expect(MessageTranslation.normalizeLanguage("zh"), "zh-Hans");
      expect(MessageTranslation.normalizeLanguage("zh-Hant"), "zh-Hant");
      expect(
          MessageTranslation.normalizeLanguage("zh", country: "TW"), "zh-Hant");
      expect(MessageTranslation.normalizeLanguage("ES"), "es");
      expect(MessageTranslation.normalizeLanguage("un"), isNull);
      expect(MessageTranslation.normalizeLanguage("xx"), isNull);
    });

    test("every catalog language has a name", () {
      for (final s in translationModelSpecs) {
        expect(translationLanguageNames.containsKey(s.from), isTrue,
            reason: s.from);
        expect(translationLanguageNames.containsKey(s.to), isTrue,
            reason: s.to);
      }
    });

    test("target follows the setting, else the system language, else English",
        () {
      expect(service(system: "de").targetLanguage, "de");
      expect(service(system: "xx").targetLanguage, "en");
    });
  });

  group("catalog", () {
    test("every model has pinned hashes and an int8 config", () {
      expect(translationModelSpecs.length, greaterThan(100));
      for (final s in translationModelSpecs) {
        expect(s.from == "en" || s.to == "en", isTrue, reason: s.key);
        for (final f in s.files) {
          expect(f.sha256, matches(RegExp(r"^[0-9a-f]{64}$")), reason: f.name);
          expect(f.url.host, "firefox-settings-attachments.cdn.mozilla.net");
        }
        final config = s.config("/models/${s.directory}");
        expect(config, contains("gemm-precision: int8shiftAlphaAll"));
        expect(config, contains("/models/${s.directory}/"));
        expect(s.file(ModelFileType.model), isNotNull, reason: s.key);
        expect(s.file(ModelFileType.lex), isNotNull, reason: s.key);
      }
    });

    test("one model per direction and platform", () {
      final seen = <String>{};
      for (final s in translationModelSpecs) {
        final platforms = s.platforms == ModelPlatforms.all
            ? ["desktop", "android"]
            : [s.platforms.name];
        for (final p in platforms) {
          expect(seen.add("${s.key} $p"), isTrue, reason: "${s.key} $p");
        }
      }
    });
  });

  group("routes", () {
    test("direct, through English, none", () {
      final t = service();
      expect(t.route("es", "en")!.map((s) => s.key), ["es-en"]);
      expect(t.route("es", "de")!.map((s) => s.key), ["es-en", "en-de"]);
      expect(t.route("es", "es"), isNull);
      expect(t.route("es", "fr"), isNull);
    });

    test("platform-specific models only where they belong", () {
      expect(service().route("ja", "en"), isNotNull);
      expect(service(android: true).route("ja", "en"), isNull);
    });

    test("only reliable guesses in another, reachable language", () {
      final t = service();
      expect(t.translatableLanguage("a", "[es] hola"), "es");
      expect(t.translatableLanguage("b", "[es] unsure hola"), isNull);
      expect(t.translatableLanguage("c", "[en] hello"), isNull);
      expect(t.translatableLanguage("d", "[fr] bonjour"), isNull);
      expect(t.translatableLanguage("e", "no tag"), isNull);
    });
  });

  group("translate", () {
    test("downloads, checks, loads and keeps line breaks", () async {
      final t = service();
      final es = t.route("es", "en")!.single;
      expect(await t.isDownloaded(es), isFalse);

      await t.translate("ev", "[es] hola\n\nadiós", "es");

      expect(t.stateFor("ev").value, isA<TranslationDone>());
      final done = t.stateFor("ev").value as TranslationDone;
      expect(done.text, "es-en: [es] hola\n\nes-en: adiós");
      expect((done.from, done.to), ("es", "en"));
      expect(await t.isDownloaded(es), isTrue);
      expect(
          engine.loaded["es-en"], contains((await t.modelDirectory(es)).path));
      expect(requests, 3);

      await t.translate("ev2", "[es] otra vez", "es");
      expect(requests, 3, reason: "the model is downloaded once");
    });

    test("goes through English with two models", () async {
      final t = service(system: "de");
      await t.translate("ev", "[es] hola", "es");
      expect(engine.calls.single, ["es-en", "en-de"]);
      expect((t.stateFor("ev").value as TranslationDone).to, "de");
    });

    test("a damaged download fails and leaves nothing behind", () async {
      final t = service();
      final es = t.route("es", "en")!.single;
      blobs[es.files.first.blob] = utf8.encode("tampered");

      await t.translate("ev", "[es] hola", "es");

      final state = t.stateFor("ev").value;
      expect(state, isA<TranslationFailed>());
      expect((state as TranslationFailed).message, contains("damaged"));
      expect(await t.isDownloaded(es), isFalse);
      final left = (await t.modelDirectory(es)).listSync();
      expect(left.where((f) => f.path.endsWith(".part")), isEmpty);
      expect(left.where((f) => f.path.endsWith(".bin")), isEmpty);
    });

    test("delete removes the model and unloads the engine", () async {
      final t = service();
      await t.translate("ev", "[es] hola", "es");
      final es = t.route("es", "en")!.single;
      expect((await t.downloadedModels()).keys.map((s) => s.key), ["es-en"]);

      await t.deleteModel(es);

      expect(await t.isDownloaded(es), isFalse);
      expect(engine.loaded, isEmpty);
      expect(await t.downloadedModels(), isEmpty);
    });
  });

  group("fold", () {
    final asked = <String>[];
    Widget app(MessageTranslation t, String text) => MaterialApp(
          home: Scaffold(
            body: MessageTranslationFold.wrap(
                eventId: "ev",
                text: text,
                translation: t,
                confirmDownload: (context, title, prompt) async {
                  asked.add(title);
                  return true;
                },
                child: Text(text)),
          ),
        );

    testWidgets("no pill for text in the target language", (tester) async {
      await tester.pumpWidget(app(service(), "[en] hello"));
      expect(find.text("Translate"), findsNothing);
    });

    testWidgets("asks before the first download, then shows the translation",
        (tester) async {
      final t = service();
      await tester.pumpWidget(app(t, "[es] hola"));
      expect(find.text("Translate"), findsOneWidget);

      // Real file and (mock) network I/O: run it outside the fake clock.
      await tester.runAsync(() async {
        await tester.tap(find.text("Translate"));
        for (var i = 0;
            i < 100 && t.stateFor(_key("[es] hola")).value is! TranslationDone;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();

      expect(asked, ["Download the Spanish language model?"]);
      expect(find.text("es-en: [es] hola"), findsOneWidget);
      expect(find.text("Spanish → English · translated on this device"),
          findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pumpAndSettle();
      expect(find.text("es-en: [es] hola"), findsNothing);
      expect(find.text("Show translation"), findsOneWidget);
    });
  });

  group("settings", () {
    SettingsTab tab(String label) =>
        SettingsTab(label: label, pageBuilder: (_) => const SizedBox());

    test("the tab goes before Advanced, only where translation runs", () {
      final tabs = [tab("General"), tab("Notifications"), tab("Advanced")];
      expect(
          TranslationSettingsPage.withTab(tabs,
                  advancedLabel: "Advanced", supported: true)
              .map((t) => t.label),
          ["General", "Notifications", "Translation", "Advanced"]);
      expect(
          TranslationSettingsPage.withTab(tabs,
                  advancedLabel: "Advanced", supported: false)
              .map((t) => t.label),
          ["General", "Notifications", "Advanced"]);
    });

    test("targets are the languages a model translates into", () {
      final t = service(system: "es");
      expect(
          t.targetLanguages,
          ["en", "de", "es"]..sort((a, b) => translationLanguageName(a)
              .compareTo(translationLanguageName(b))));
      expect(t.automaticLanguage, "es");
      expect(service(system: "ja").automaticLanguage, "en",
          reason: "nothing translates into Japanese here");
    });

    // The model list is real file I/O, one await after another: let each
    // step run outside the fake clock, then rebuild, until the list is in.
    Future<void> loaded(WidgetTester tester) async {
      final list = find.byWidgetPredicate((w) =>
          w is Text &&
          (w.data?.startsWith("None yet.") == true ||
              w.data?.endsWith("in total") == true));
      for (var i = 0; i < 50 && list.evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    Widget page(MessageTranslation t) => MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TranslationSettingsPage(translation: t))));

    testWidgets("lists downloaded models with sizes", (tester) async {
      final t = service();
      await tester.runAsync(() => t.translate("ev", "[es] hola", "es"));
      await tester.pumpWidget(page(t));
      await loaded(tester);

      expect(find.text("Spanish → English"), findsOneWidget);
      expect(find.text("Delete"), findsOneWidget);
      expect(find.text("Delete all"), findsOneWidget);
      expect(find.textContaining("in total"), findsOneWidget);
    });

    testWidgets("says how languages arrive when none are downloaded",
        (tester) async {
      await tester.pumpWidget(page(service()));
      await loaded(tester);

      expect(find.textContaining("None yet."), findsOneWidget);
      expect(find.textContaining("Automatic: system language (English)"),
          findsOneWidget);
    });
  });

  test("dialog text names the size and the route", () {
    final one = spec("es", "en", {});
    final two = [one, spec("en", "de", {})];
    expect(downloadPrompt("es", "en", [one]), contains("a language model ("));
    expect(downloadPrompt("es", "de", two),
        contains("2 language models (")); // through English
    expect(formatModelSize(37014089), "37 MB");
    expect(formatModelSize(4636248), "4.6 MB");
  });
}

String _key(String text) => "ev\u0000${text.hashCode}";
