// Vommet: localization delegates for the app's MaterialApps. Flutter's own
// Material / Cupertino / Widgets texts exist for most of our languages; for
// one they lack (Esperanto) the fallback delegates below give English ones
// instead of failing, while Vommet's own strings still use that language.
import 'package:commet/config/app_language.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class AppLocalizations {
  static const List<LocalizationsDelegate<dynamic>> delegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    EnglishFallbackLocalizationsDelegate<MaterialLocalizations>(
        GlobalMaterialLocalizations.delegate),
    EnglishFallbackLocalizationsDelegate<WidgetsLocalizations>(
        GlobalWidgetsLocalizations.delegate),
    EnglishFallbackLocalizationsDelegate<CupertinoLocalizations>(
        GlobalCupertinoLocalizations.delegate),
  ];

  /// The app's locale (the language picked at startup).
  static Locale get locale => AppLanguages.current.locale;

  static List<Locale> get supportedLocales => AppLanguages.supportedLocales;
}

/// Loads [inner]'s English localizations for a locale [inner] doesn't
/// support. Listed after [inner], so it only ever takes over those locales.
class EnglishFallbackLocalizationsDelegate<T> extends LocalizationsDelegate<T> {
  const EnglishFallbackLocalizationsDelegate(this.inner);

  final LocalizationsDelegate<T> inner;

  static const Locale english = Locale("en");

  @override
  bool isSupported(Locale locale) => !inner.isSupported(locale);

  @override
  Future<T> load(Locale locale) => inner.load(english);

  @override
  bool shouldReload(EnglishFallbackLocalizationsDelegate<T> old) => false;
}
