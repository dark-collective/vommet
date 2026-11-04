// Vommet: the app language (Settings › General › Language) and how it is
// picked. Kept free of Flutter widgets and intl state so it can be unit
// tested; see utils/app_language_setup.dart for applying it at startup.
import 'dart:ui' show Locale;

/// A language Vommet ships a translation for (assets/l10n/intl_<id>.arb).
class AppLanguage {
  const AppLanguage(this.id, this.nativeName,
      {this.formatLocale, String? messages})
      : _messages = messages;

  /// The intl locale and (unless [messages] says otherwise) the arb file
  /// suffix: "de", "pt_BR", "zh_Hant".
  final String id;

  final String? _messages;

  /// The arb file (assets/l10n/intl_<messages>.arb) holding this language's
  /// translations. Regional variants that don't differ yet share one: both
  /// Spanish variants use intl_es.arb, which intl falls back to for es_419
  /// and es_ES.
  String get messages => _messages ?? id;

  /// The language's name in itself, shown in bold in the language list.
  final String nativeName;

  /// The intl locale whose date and number formats to use when there is no
  /// exact formatting data for [id] (zh_Hant would otherwise fall back to
  /// Simplified Chinese dates).
  final String? formatLocale;

  List<String> get _parts => id.split("_");

  String get languageCode => _parts.first;

  String? get scriptCode =>
      _parts.length > 1 && _parts[1].length == 4 ? _parts[1] : null;

  String? get countryCode {
    final rest = _parts.skip(1).where((p) => p.length != 4);
    return rest.isEmpty ? null : rest.first;
  }

  /// The Flutter locale for this translation (zh_Hant → zh-Hant).
  Locale get locale => Locale.fromSubtags(
      languageCode: languageCode,
      scriptCode: scriptCode,
      countryCode: countryCode);
}

class AppLanguages {
  /// Value of the language preference that follows the device.
  static const String systemDefault = "";

  static const String english = "en";

  /// Every language with an arb file in assets/l10n (see
  /// [AppLanguage.messages]).
  static const List<AppLanguage> all = [
    AppLanguage("ar", "العربية"),
    AppLanguage("be", "Беларуская"),
    AppLanguage("cs", "Čeština"),
    AppLanguage("da", "Dansk"),
    AppLanguage("de", "Deutsch"),
    AppLanguage("en", "English"),
    AppLanguage("eo", "Esperanto"),
    AppLanguage("es_419", "Español (Latinoamérica)", messages: "es"),
    AppLanguage("es_ES", "Español (España)", messages: "es"),
    AppLanguage("et", "Eesti"),
    AppLanguage("eu", "Euskara"),
    AppLanguage("fa", "فارسی"),
    AppLanguage("fi", "Suomi"),
    AppLanguage("fr", "Français"),
    AppLanguage("hu", "Magyar"),
    AppLanguage("it", "Italiano"),
    AppLanguage("ja", "日本語"),
    AppLanguage("ko", "한국어"),
    AppLanguage("nb", "Norsk bokmål"),
    AppLanguage("pl", "Polski"),
    AppLanguage("pt", "Português"),
    AppLanguage("pt_BR", "Português (Brasil)"),
    AppLanguage("ro", "Română"),
    AppLanguage("ru", "Русский"),
    AppLanguage("sv", "Svenska"),
    AppLanguage("ta", "தமிழ்"),
    AppLanguage("tr", "Türkçe"),
    AppLanguage("uk", "Українська"),
    AppLanguage("zh", "简体中文"),
    AppLanguage("zh_Hant", "繁體中文", formatLocale: "zh_TW"),
  ];

  /// Language codes a device may report for a language we ship under
  /// another code.
  static const Map<String, String> _languageAliases = {
    "no": "nb", // Norwegian → Norwegian Bokmål
    "nn": "nb", // no Nynorsk translation; Bokmål is closer than English
  };

  /// Countries whose Spanish is the Latin American variant (CLDR's es_419
  /// regions, including es-US); "419" is the region itself. Spanish from
  /// anywhere else, or with no country, gets Spain's.
  static const Set<String> _latinAmericanSpanishCountries = {
    "419",
    "AR",
    "BO",
    "BR",
    "BZ",
    "CL",
    "CO",
    "CR",
    "CU",
    "DO",
    "EC",
    "GT",
    "HN",
    "MX",
    "NI",
    "PA",
    "PE",
    "PR",
    "PY",
    "SV",
    "US",
    "UY",
    "VE"
  };

  /// The translation a language without its own plain entry falls back to.
  static const Map<String, String> _languageDefaults = {"es": "es_ES"};

  /// Countries whose Chinese is written in Traditional characters when the
  /// device gives no script.
  static const Set<String> _traditionalChineseCountries = {"TW", "HK", "MO"};

  /// The language picked at startup (what the app is showing now).
  static AppLanguage current = byId(english)!;

  /// The preference value read at startup, to tell whether a change still
  /// needs a restart.
  static String startupPreference = systemDefault;

  static AppLanguage? byId(String id) {
    for (final l in all) {
      if (l.id == id) return l;
    }
    return null;
  }

  static List<Locale> get supportedLocales =>
      all.map((l) => l.locale).toList(growable: false);

  /// Picks the translation to use: the chosen one if [preference] names a
  /// shipped language, else the best match for the device's [platformLocales]
  /// (in the device's order of preference), else English.
  ///
  /// For each device locale: the exact translation (language + script or
  /// country: zh-Hant-TW, zh-TW, zh-HK → zh_Hant; pt-BR → pt_BR), then the
  /// language alone (de-AT → de), before trying the next device locale.
  static AppLanguage resolve(String preference, List<Locale> platformLocales) {
    preference = migratePreference(preference, platformLocales);
    if (preference != systemDefault) {
      final chosen = byId(preference);
      if (chosen != null) return chosen;
    }

    for (final locale in platformLocales) {
      final match = matchLocale(locale);
      if (match != null) return match;
    }

    return byId(english)!;
  }

  /// A saved [preference] for a language that was split into regional
  /// variants, mapped to one of them: plain Spanish ("es", before es_419 and
  /// es_ES) becomes the device's Spanish variant, else Spain's. Anything else
  /// is returned as is.
  static String migratePreference(
      String preference, List<Locale> platformLocales) {
    if (preference != "es") return preference;
    for (final locale in platformLocales) {
      final match = matchLocale(locale);
      if (match != null && match.languageCode == "es") return match.id;
    }
    return _languageDefaults["es"]!;
  }

  /// The shipped translation for one device locale, or null.
  static AppLanguage? matchLocale(Locale locale) {
    var language = locale.languageCode.toLowerCase();
    language = _languageAliases[language] ?? language;
    var script = locale.scriptCode;
    if (script != null && script.isNotEmpty) {
      script = script[0].toUpperCase() + script.substring(1).toLowerCase();
    } else {
      script = null;
    }

    var country = locale.countryCode?.toUpperCase();
    if (language == "es" && _latinAmericanSpanishCountries.contains(country)) {
      country = "419";
    }

    if (language == "zh" && script == null) {
      script = _traditionalChineseCountries.contains(country) ? "Hant" : "Hans";
    }

    final candidates = [
      if (script != null && country != null) "${language}_${script}_$country",
      if (script != null) "${language}_$script",
      if (country != null) "${language}_$country",
    ];
    for (final id in candidates) {
      final l = byId(id);
      if (l != null) return l;
    }

    // Language alone. Simplified Chinese ships as plain "zh" (and is still
    // closer than English for a Traditional device if zh_Hant were missing).
    // Spanish has no plain entry: es → es_ES.
    return byId(language) ?? byId(_languageDefaults[language] ?? language);
  }
}
