// Vommet: makes intl's date and number formatting work for the app language
// (see config/app_language.dart). Without this a translation intl has no
// formatting data for (Esperanto) makes every DateFormat throw once it is
// Intl.defaultLocale.
import 'package:commet/config/app_language.dart';
import 'package:intl/date_symbol_data_custom.dart';
import 'package:intl/date_symbols.dart';
import 'package:intl/date_time_patterns.dart';
import 'package:intl/intl.dart';
import 'package:intl/number_symbols_data.dart';

class AppLanguageSetup {
  /// When intl has no date formatting data for [locale] (an app language
  /// id), registers [locale] with the data of [formatLocale] if given and
  /// known, else of intl's own fallback for it, else English; the same for
  /// number formats when intl has nothing for it at all. Returns the locale
  /// whose date formats [locale] now uses. Call after
  /// initializeDateFormatting().
  static String ensureFormattingLocale(String locale, String? formatLocale) {
    String? fallback(String? l) => l == null
        ? null
        : Intl.verifiedLocale(l, DateFormat.localeExists,
            onFailure: (_) => null);

    var dateSource = locale;
    if (!DateFormat.localeExists(locale)) {
      // Prefer the language's own format locale over intl's guess (which
      // would be the bare language: zh_Hant → zh, Simplified).
      final source =
          fallback(formatLocale) ?? fallback(locale) ?? AppLanguages.english;
      dateSource = source;
      final symbols = DateFormat.yMd(source).dateSymbols;
      final patterns = dateTimePatternMap()[source] ??
          dateTimePatternMap()[AppLanguages.english]!;
      initializeDateFormattingCustom(
        locale: locale,
        symbols: DateSymbols.deserializeFromMap(
            {...symbols.serializeToMap(), "NAME": locale}),
        patterns: patterns,
      );
    }

    if (Intl.verifiedLocale(locale, NumberFormat.localeExists,
            onFailure: (_) => null) ==
        null) {
      final source = Intl.verifiedLocale(
              formatLocale ?? AppLanguages.english, NumberFormat.localeExists,
              onFailure: (_) => null) ??
          AppLanguages.english;
      numberFormatSymbols[locale] = numberFormatSymbols[source]!;
      final compact = compactNumberSymbols[source];
      if (compact != null) compactNumberSymbols[locale] = compact;
    }

    return dateSource;
  }
}
