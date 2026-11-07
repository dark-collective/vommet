// Vommet: switches the app language while the app runs (Settings › General ›
// Language), so a new language shows at once instead of after a restart.
import 'package:commet/config/app_language.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/generated/intl/messages_all.dart';
import 'package:commet/utils/app_language_setup.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

class AppLanguageSwitch {
  /// Loads [language]'s messages and formats, makes it the app language and
  /// rebuilds every widget, keeping their state (open rooms, calls, scroll).
  /// Text a widget keeps from before (a string stored in its state) updates
  /// when that screen is next opened. Returns false if the language could
  /// not be loaded; the old one stays and a restart applies the new one.
  static Future<bool> apply(AppLanguage language) async {
    if (language.id == AppLanguages.current.id) return true;

    try {
      final loaded = await Future.value(initializeMessages(language.id));
      if (!loaded) return false;
      await initializeDateFormatting(language.id);
      AppLanguageSetup.ensureFormattingLocale(
          language.id, language.formatLocale);
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to switch app language");
      return false;
    }

    Intl.defaultLocale = language.id;
    AppLanguages.current = language;
    rebuildAll();
    return true;
  }

  /// Marks every element for a rebuild. Unlike a new key on the app, this
  /// keeps all state; MaterialApp picks up the new locale (Flutter's own
  /// texts, text direction) on the same pass.
  static void rebuildAll() {
    void mark(Element element) {
      element.markNeedsBuild();
      element.visitChildren(mark);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(mark);
  }
}
