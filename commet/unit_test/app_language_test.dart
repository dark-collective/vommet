import 'dart:io';
import 'dart:ui';

import 'package:commet/config/app_language.dart';
import 'package:commet/config/translation_progress.dart';
import 'package:commet/utils/app_language_setup.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:test/test.dart';

String resolve(String preference, List<Locale> locales) =>
    AppLanguages.resolve(preference, locales).id;

void main() {
  group("resolve", () {
    test("a chosen language wins over the device", () {
      expect(resolve("de", const [Locale("fr", "FR")]), "de");
      expect(resolve("eo", const [Locale("en", "US")]), "eo");
    });

    test("an unknown preference falls back to the device", () {
      expect(resolve("xx", const [Locale("fr", "CA")]), "fr");
    });

    test("system default: exact language + country", () {
      expect(resolve("", const [Locale("pt", "BR")]), "pt_BR");
      expect(resolve("", const [Locale("pt", "PT")]), "pt");
    });

    test("system default: Traditional Chinese by script or country", () {
      expect(
          resolve("", const [
            Locale.fromSubtags(
                languageCode: "zh", scriptCode: "Hant", countryCode: "TW")
          ]),
          "zh_Hant");
      expect(resolve("", const [Locale("zh", "TW")]), "zh_Hant");
      expect(resolve("", const [Locale("zh", "HK")]), "zh_Hant");
      expect(resolve("", const [Locale("zh", "MO")]), "zh_Hant");
    });

    test("system default: Simplified Chinese ships as zh", () {
      expect(resolve("", const [Locale("zh", "CN")]), "zh");
      expect(resolve("", const [Locale("zh")]), "zh");
      expect(
          resolve("", const [
            Locale.fromSubtags(
                languageCode: "zh", scriptCode: "Hans", countryCode: "SG")
          ]),
          "zh");
    });

    test("system default: language alone", () {
      expect(resolve("", const [Locale("de", "AT")]), "de");
      expect(resolve("", const [Locale("en", "GB")]), "en");
      expect(resolve("", const [Locale("eo")]), "eo");
    });

    test("system default: Norwegian maps to Bokmål", () {
      expect(resolve("", const [Locale("no", "NO")]), "nb");
      expect(resolve("", const [Locale("nb", "NO")]), "nb");
    });

    test("system default: Spanish by region", () {
      expect(resolve("", const [Locale("es", "MX")]), "es_419");
      expect(resolve("", const [Locale("es", "AR")]), "es_419");
      expect(resolve("", const [Locale("es", "US")]), "es_419");
      expect(resolve("", const [Locale("es", "419")]), "es_419");
      expect(resolve("", const [Locale("es", "ES")]), "es_ES");
      expect(resolve("", const [Locale("es")]), "es_ES");
      expect(resolve("", const [Locale("es", "GQ")]), "es_ES");
    });

    test("a saved plain Spanish choice moves to a regional variant", () {
      expect(AppLanguages.migratePreference("es", const [Locale("es", "CO")]),
          "es_419");
      expect(
          AppLanguages.migratePreference(
              "es", const [Locale("en", "US"), Locale("es", "MX")]),
          "es_419");
      expect(
          AppLanguages.migratePreference("es", const [Locale("es")]), "es_ES");
      expect(AppLanguages.migratePreference("es", const [Locale("de", "DE")]),
          "es_ES");
      expect(AppLanguages.migratePreference("de", const [Locale("es", "MX")]),
          "de");
      expect(resolve("es", const [Locale("en", "US")]), "es_ES");
    });

    test("device locales are tried in order", () {
      expect(resolve("", const [Locale("xx"), Locale("de", "DE")]), "de");
      expect(resolve("", const [Locale("ja", "JP"), Locale("de")]), "ja");
      // A later exact match doesn't beat an earlier language-only one.
      expect(resolve("", const [Locale("pt", "AO"), Locale("pt", "BR")]), "pt");
    });

    test("nothing matching falls back to English", () {
      expect(resolve("", const [Locale("xx", "YY")]), "en");
      expect(resolve("", const []), "en");
    });
  });

  test("Flutter locales of the translations", () {
    expect(AppLanguages.byId("zh_Hant")!.locale,
        const Locale.fromSubtags(languageCode: "zh", scriptCode: "Hant"));
    expect(AppLanguages.byId("pt_BR")!.locale, const Locale("pt", "BR"));
    expect(AppLanguages.byId("eo")!.locale, const Locale("eo"));
    expect(AppLanguages.byId("es_419")!.locale, const Locale("es", "419"));
    expect(AppLanguages.byId("es_ES")!.locale, const Locale("es", "ES"));
  });

  test("every arb file has a language entry, and the other way round", () {
    final files = Directory("assets/l10n")
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.startsWith("intl_") && n.endsWith(".arb"))
        .map((n) => n.substring(5, n.length - 4))
        .toSet();
    expect(AppLanguages.all.map((l) => l.messages).toSet(), files);
    expect(AppLanguages.byId("es_419")!.messages, "es");
    expect(AppLanguages.byId("es_ES")!.messages, "es");
  });

  test("translation percentages count non-empty keys of the English arb", () {
    final result = TranslationProgress.percentages({
      "en": '{"a": "A", "@a": {}, "b": "B", "c": "C", "d": "D"}',
      "de": '{"a": "Ä", "b": "", "extra": "X"}',
      "eo": '{"@@locale": "eo"}',
      "fr": '{"a": "A", "b": "B", "c": "C", "d": "D"}',
      "broken": "{not json",
    });
    expect(result["en"], 100);
    expect(result["de"], 25);
    expect(result["eo"], 0);
    expect(result["fr"], 100);
    expect(result["broken"], 0);
  });

  test("a little translation never shows as 0%", () {
    final en = {for (var i = 0; i < 300; i++) '"k$i"': '"v"'}
        .entries
        .map((e) => "${e.key}: ${e.value}")
        .join(",");
    final result =
        TranslationProgress.percentages({"en": "{$en}", "fa": '{"k1": "x"}'});
    expect(result["fa"], 1);
  });

  group("formatting", () {
    setUpAll(() async {
      await initializeDateFormatting();
    });

    tearDown(() => Intl.defaultLocale = null);

    test("Esperanto gets English date and number formats", () {
      expect(AppLanguageSetup.ensureFormattingLocale("eo", null), "en");
      Intl.defaultLocale = "eo";
      expect(DateFormat.yMMMd().format(DateTime(2026, 10, 13)), "Oct 13, 2026");
      expect(NumberFormat.decimalPattern().format(1234.5), "1,234.5");
    });

    test("Traditional Chinese uses zh_TW dates, not Simplified", () {
      expect(
          AppLanguageSetup.ensureFormattingLocale("zh_Hant", "zh_TW"), "zh_TW");
      expect(DateFormat.MMMMEEEEd("zh_Hant").format(DateTime(2026, 10, 13)),
          DateFormat.MMMMEEEEd("zh_TW").format(DateTime(2026, 10, 13)));
    });

    test("a locale intl knows is left alone", () {
      expect(AppLanguageSetup.ensureFormattingLocale("de", null), "de");
    });
  });
}
