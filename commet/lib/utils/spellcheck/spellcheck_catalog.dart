// Vommet: Hunspell dictionaries offered for spellcheck, from the LibreOffice
// dictionaries repository at a fixed commit (generated from its file list; the
// sizes are exact and checked after download). Each dictionary keeps its own
// licence (see the repository); none ship inside the app.

class SpellcheckLanguage {
  /// Our id, also the file name on disk.
  final String code;

  /// The language's own name.
  final String name;

  /// Path in the repository, without .aff/.dic.
  final String path;
  final int affBytes;
  final int dicBytes;

  const SpellcheckLanguage(
      this.code, this.name, this.path, this.affBytes, this.dicBytes);

  int get bytes => affBytes + dicBytes;

  Uri get affUrl => Uri.parse("${SpellcheckCatalog.base}$path.aff");
  Uri get dicUrl => Uri.parse("${SpellcheckCatalog.base}$path.dic");
}

class SpellcheckCatalog {
  static const String base =
      "https://raw.githubusercontent.com/LibreOffice/dictionaries/67032ee957631908098a72edf48dc81cac27e369/";

  /// The first entry of a language is its default (e.g. en_US for English).
  static const List<SpellcheckLanguage> all = [
    SpellcheckLanguage(
        "en_US", "English (United States)", "en/en_US", 3205, 551762),
    SpellcheckLanguage(
        "en_GB", "English (United Kingdom)", "en/en_GB", 44158, 1230571),
    SpellcheckLanguage("en_CA", "English (Canada)", "en/en_CA", 3205, 551583),
    SpellcheckLanguage(
        "en_AU", "English (Australia)", "en/en_AU", 3205, 554336),
    SpellcheckLanguage(
        "en_ZA", "English (South Africa)", "en/en_ZA", 43842, 998279),
    SpellcheckLanguage(
        "de_DE", "Deutsch (Deutschland)", "de/de_DE_frami", 19067, 4356903),
    SpellcheckLanguage(
        "de_AT", "Deutsch (Österreich)", "de/de_AT_frami", 19068, 4359309),
    SpellcheckLanguage(
        "de_CH", "Deutsch (Schweiz)", "de/de_CH_frami", 19068, 4358308),
    SpellcheckLanguage(
        "fr", "Français", "fr_FR/dictionaries/fr", 199870, 1236490),
    SpellcheckLanguage("es_ES", "Español (España)", "es/es_ES", 169202, 715989),
    SpellcheckLanguage("es_MX", "Español (México)", "es/es_MX", 160081, 723507),
    SpellcheckLanguage(
        "es_AR", "Español (Argentina)", "es/es_AR", 171527, 707817),
    SpellcheckLanguage(
        "es_CO", "Español (Colombia)", "es/es_CO", 160081, 751422),
    SpellcheckLanguage("es_CL", "Español (Chile)", "es/es_CL", 162395, 705568),
    SpellcheckLanguage("es_PE", "Español (Perú)", "es/es_PE", 160081, 715404),
    SpellcheckLanguage(
        "es_VE", "Español (Venezuela)", "es/es_VE", 160081, 704472),
    SpellcheckLanguage(
        "es_US", "Español (Estados Unidos)", "es/es_US", 171524, 696235),
    SpellcheckLanguage(
        "pt_BR", "Português (Brasil)", "pt_BR/pt_BR", 979792, 4477695),
    SpellcheckLanguage(
        "pt_PT", "Português (Portugal)", "pt_PT/pt_PT", 95089, 1485977),
    SpellcheckLanguage("it_IT", "Italiano", "it_IT/it_IT", 70054, 1295083),
    SpellcheckLanguage("nl_NL", "Nederlands", "nl_NL/nl_NL", 46557, 2488246),
    SpellcheckLanguage("pl_PL", "Polski", "pl_PL/pl_PL", 257542, 5252096),
    SpellcheckLanguage("ru_RU", "Русский", "ru_RU/ru_RU", 71236, 3473191),
    SpellcheckLanguage("uk_UA", "Українська", "uk_UA/uk_UA", 211759, 8919324),
    SpellcheckLanguage(
        "be_BY", "Беларуская", "be_BY/be-official", 184150, 10607006),
    SpellcheckLanguage("cs_CZ", "Čeština", "cs_CZ/cs_CZ", 111575, 3656362),
    SpellcheckLanguage("sk_SK", "Slovenčina", "sk_SK/sk_SK", 225271, 3362212),
    SpellcheckLanguage("sl_SI", "Slovenščina", "sl_SI/sl_SI", 14730, 2967766),
    SpellcheckLanguage("hr_HR", "Hrvatski", "hr_HR/hr_HR", 95802, 731819),
    SpellcheckLanguage("bs_BA", "Bosanski", "bs_BA/bs_BA", 17468, 339863),
    SpellcheckLanguage("sr", "Српски", "sr/sr", 901060, 5878745),
    SpellcheckLanguage(
        "sr_Latn", "Srpski (latinica)", "sr/sr-Latn", 684540, 3817505),
    SpellcheckLanguage("bg_BG", "Български", "bg_BG/bg_BG", 58189, 1566331),
    SpellcheckLanguage("ro_RO", "Română", "ro/ro_RO", 55195, 2202394),
    SpellcheckLanguage("hu_HU", "Magyar", "hu_HU/hu_HU", 2316267, 1786144),
    SpellcheckLanguage("da_DK", "Dansk", "da_DK/da_DK", 82864, 3894244),
    SpellcheckLanguage(
        "sv_SE", "Svenska", "sv_SE/dictionaries/sv_SE", 18583, 2344202),
    SpellcheckLanguage("sv_FI", "Svenska (Finland)", "sv_SE/dictionaries/sv_FI",
        18583, 2339367),
    SpellcheckLanguage("nb_NO", "Norsk bokmål", "no/nb_NO", 17382, 9336265),
    SpellcheckLanguage("nn_NO", "Norsk nynorsk", "no/nn_NO", 13616, 6467674),
    SpellcheckLanguage("is", "Íslenska", "is/is", 309734, 2454138),
    SpellcheckLanguage("et_EE", "Eesti", "et_EE/et_EE", 236336, 4383841),
    SpellcheckLanguage("lv_LV", "Latviešu", "lv_LV/lv_LV", 130475, 1844831),
    SpellcheckLanguage("lt_LT", "Lietuvių", "lt_LT/lt", 99714, 1181184),
    SpellcheckLanguage("el_GR", "Ελληνικά", "el_GR/el_GR", 15647, 10125390),
    SpellcheckLanguage("tr_TR", "Türkçe", "tr_TR/tr_TR", 2283891, 36136702),
    SpellcheckLanguage("ca", "Català", "ca/dictionaries/ca", 52471, 3086130),
    SpellcheckLanguage("ca_valencia", "Català (valencià)",
        "ca/dictionaries/ca-valencia", 52680, 3091032),
    SpellcheckLanguage("gl_ES", "Galego", "gl/gl_ES", 1163541, 8325262),
    SpellcheckLanguage("an_ES", "Aragonés", "an_ES/an_ES", 34137, 246615),
    SpellcheckLanguage("oc_FR", "Occitan", "oc_FR/oc_FR", 21385, 2766428),
    SpellcheckLanguage("br_FR", "Brezhoneg", "br_FR/br_FR", 13544, 3968237),
    SpellcheckLanguage("gd_GB", "Gàidhlig", "gd_GB/gd_GB", 8228, 4806682),
    SpellcheckLanguage("lij_IT", "Ligure", "lij_IT/lij_IT", 29638, 535959),
    SpellcheckLanguage("sq_AL", "Shqip", "sq_AL/sq_AL", 7764, 2726785),
    SpellcheckLanguage("eo", "Esperanto", "eo/eo", 19129, 377989),
    SpellcheckLanguage("af_ZA", "Afrikaans", "af_ZA/af_ZA", 4969, 1214886),
    SpellcheckLanguage("sw_TZ", "Kiswahili", "sw_TZ/sw_TZ", 974, 630844),
    SpellcheckLanguage("id_ID", "Bahasa Indonesia", "id/id_ID", 15274, 453700),
    SpellcheckLanguage("he_IL", "עברית", "he_IL/he_IL", 78883, 7796259),
    SpellcheckLanguage("ar", "العربية", "ar/ar", 86949, 7217161),
    SpellcheckLanguage("fa_IR", "فارسی", "fa_IR/fa-IR", 5439, 2575990),
    SpellcheckLanguage("ckb", "کوردی", "ckb/dictionaries/ckb", 125024, 713467),
    SpellcheckLanguage("hi_IN", "हिन्दी", "hi_IN/hi_IN", 12671, 5004835),
    SpellcheckLanguage("mr_IN", "मराठी", "mr_IN/mr_IN", 30158, 1036511),
    SpellcheckLanguage("ne_NP", "नेपाली", "ne_NP/ne_NP", 14162, 874372),
    SpellcheckLanguage("bn_BD", "বাংলা", "bn_BD/bn_BD", 125422, 2237684),
    SpellcheckLanguage("as_IN", "অসমীয়া", "as_IN/as_IN", 271, 1912331),
    SpellcheckLanguage("gu_IN", "ગુજરાતી", "gu_IN/gu_IN", 174, 3792870),
    SpellcheckLanguage("ta_IN", "தமிழ்", "ta_IN/ta_IN", 12114, 2422307),
    SpellcheckLanguage("te_IN", "తెలుగు", "te_IN/te_IN", 160, 3402272),
    SpellcheckLanguage("si_LK", "සිංහල", "si_LK/si_LK", 197175, 851377),
    SpellcheckLanguage("lo_LA", "ລາວ", "lo_LA/lo_LA", 10, 671495),
    SpellcheckLanguage("ko_KR", "한국어", "ko_KR/ko_KR", 11094418, 2864524),
    SpellcheckLanguage("mn_MN", "Монгол", "mn_MN/mn_MN", 519162, 18075185),
  ];

  static SpellcheckLanguage? byCode(String code) {
    for (final l in all) {
      if (l.code == code) return l;
    }
    return null;
  }

  /// The best dictionary for a locale such as "de_AT", "de-AT.UTF-8" or "de".
  static SpellcheckLanguage? forLocale(String locale) {
    final parts = locale.split(RegExp(r"[_.@-]"));
    if (parts.isEmpty || parts.first.isEmpty) return null;
    final language = parts.first.toLowerCase();
    final region = parts.length > 1 ? parts[1].toUpperCase() : null;
    if (region != null) {
      final exact = byCode("${language}_$region");
      if (exact != null) return exact;
    }
    for (final l in all) {
      if (l.code == language || l.code.startsWith("${language}_")) return l;
    }
    return null;
  }
}
