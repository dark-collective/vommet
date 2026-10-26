// Vommet: Settings › General › Language. Every shipped language with its
// own name, its English name and how much of it is translated; a change
// applies at once (a restart only if the language can't be loaded live).
// In Settings the list sits behind one row that opens it in a picker
// (Vommet issue 751); onboarding still shows it inline.
import 'package:commet/config/app_language.dart';
import 'package:commet/config/experiment_registry.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/translation_progress.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/app_language_switch.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class LanguageSettingsPanel extends StatefulWidget {
  const LanguageSettingsPanel({super.key, this.collapsed = false});

  /// Show only the current language; tapping it opens the full list in a
  /// picker. Off for onboarding, where picking a language is the page.
  final bool collapsed;

  @override
  State<LanguageSettingsPanel> createState() => _LanguageSettingsPanelState();
}

class _LanguageSettingsPanelState extends State<LanguageSettingsPanel> {
  static String get labelLanguageSettingsTitle => Intl.message("Language",
      desc: "Header for the app language section in settings",
      name: "labelLanguageSettingsTitle");

  static String get labelLanguageSettingsNoteUntranslated =>
      Intl.message("Untranslated text shows in English.",
          desc: "Note above the list of app languages in settings",
          name: "labelLanguageSettingsNoteUntranslated");

  static String get labelLanguageSystemDefault => Intl.message("System default",
      desc: "Option in the app language list to use the device's language",
      name: "labelLanguageSystemDefault");

  static String labelLanguageSystemDefaultDescription(String language) =>
      Intl.message("$language, from your device",
          desc:
              "Shown under 'System default' in the app language list: the language the device's settings pick",
          args: [language],
          name: "labelLanguageSystemDefaultDescription");

  static String labelLanguageTranslatedPercent(int percent) => Intl.message(
      "$percent% translated",
      desc:
          "How much of a language is translated, shown in the app language list",
      args: [percent],
      name: "labelLanguageTranslatedPercent");

  static String get labelLanguageNotTranslated => Intl.message(
      "Not translated yet",
      desc:
          "Shown in the app language list for a language with no translations",
      name: "labelLanguageNotTranslated");

  static String labelLanguageRestartPrompt(String language) => Intl.message(
      "Restart Vommet to switch to $language.",
      desc:
          "Shown after picking another app language; the change applies after a restart",
      args: [language],
      name: "labelLanguageRestartPrompt");

  static String get labelLanguageRestartNow => Intl.message("Restart now",
      desc: "Button that restarts the app to apply a new app language",
      name: "labelLanguageRestartNow");

  static String get labelLanguageSearch => Intl.message("Search languages",
      desc: "Hint in the search box of the app language picker",
      name: "labelLanguageSearch");

  static String get labelLanguageCloseApp => Intl.message("Close Vommet",
      desc:
          "Button that closes the app to apply a new app language, where it can't restart itself",
      name: "labelLanguageCloseApp");

  Map<String, int>? progress;
  late String preference;

  @override
  void initState() {
    super.initState();
    preference = preferences.appLanguage.value;
    TranslationProgress.load().then((value) {
      if (mounted) setState(() => progress = value);
    });
  }

  List<Locale> get deviceLocales =>
      WidgetsBinding.instance.platformDispatcher.locales;

  Future<void> select(String id) async {
    setState(() => preference = id);
    await preferences.appLanguage.set(id);
    // Debug translations replace the message lookup; those need a restart.
    if (preferences.debugTranslations.value) return;
    await AppLanguageSwitch.apply(AppLanguages.resolve(id, deviceLocales));
    if (mounted) setState(() {});
  }

  bool get systemSelected =>
      preference == AppLanguages.systemDefault ||
      AppLanguages.byId(preference) == null;

  static List<AppLanguage> get sortedLanguages =>
      [...AppLanguages.all]..sort((a, b) {
          if (a.id == AppLanguages.english) return -1;
          if (b.id == AppLanguages.english) return 1;
          return LanguageNames.english(a.id)
              .toLowerCase()
              .compareTo(LanguageNames.english(b.id).toLowerCase());
        });

  Future<void> openPicker() async {
    final id = await AdaptiveDialog.show<String>(context,
        title: labelLanguageSettingsTitle,
        scrollable: false,
        builder: (_) => _LanguagePickerDialog(
            preference:
                systemSelected ? AppLanguages.systemDefault : preference,
            progress: progress));
    if (id != null && id != preference && mounted) await select(id);
  }

  @override
  Widget build(BuildContext context) {
    final system =
        AppLanguages.resolve(AppLanguages.systemDefault, deviceLocales);
    final pending = AppLanguages.resolve(preference, deviceLocales);
    final languages = sortedLanguages;

    return tiamat.Panel(
      header: labelLanguageSettingsTitle,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: tiamat.Text.labelLow(labelLanguageSettingsNoteUntranslated),
          ),
          // Above the list, so it is in view after tapping a language.
          if (pending.id != AppLanguages.current.id)
            _restartNote(context, pending),
          if (widget.collapsed)
            _currentLanguageRow(system)
          else ...[
            _LanguageRow(
              title: labelLanguageSystemDefault,
              subtitle:
                  labelLanguageSystemDefaultDescription(system.nativeName),
              subtitleLocale: system.locale,
              selected: systemSelected,
              onTap: () => select(AppLanguages.systemDefault),
            ),
            for (final l in languages)
              _LanguageRow(
                title: l.nativeName,
                titleLocale: l.locale,
                subtitle: LanguageNames.english(l.id),
                percent: progress?[l.id],
                selected: preference == l.id,
                onTap: () => select(l.id),
              ),
          ],
        ],
      ),
    );
  }

  /// The one row Settings shows: the chosen language, opening the picker.
  Widget _currentLanguageRow(AppLanguage system) {
    final language = systemSelected ? null : AppLanguages.byId(preference);
    return _LanguageRow(
      key: const ValueKey("language-settings-current"),
      title: language?.nativeName ?? labelLanguageSystemDefault,
      titleLocale: language?.locale,
      subtitle: language != null
          ? LanguageNames.english(language.id)
          : labelLanguageSystemDefaultDescription(system.nativeName),
      subtitleLocale: language == null ? system.locale : null,
      percent: language == null ? null : (progress?[language.id]),
      selected: false,
      opensPicker: true,
      onTap: openPicker,
    );
  }

  Widget _restartNote(BuildContext context, AppLanguage language) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: scheme.primaryContainer.withAlpha(90),
          borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(Icons.restart_alt, size: 18, color: scheme.onSurface),
        const SizedBox(width: 8),
        Expanded(
            child: tiamat.Text.label(
                labelLanguageRestartPrompt(language.nativeName))),
        if (!PlatformUtils.isWeb) ...[
          const SizedBox(width: 8),
          tiamat.Button(
            text: ExperimentRegistry.canRelaunch
                ? labelLanguageRestartNow
                : labelLanguageCloseApp,
            onTap: () => ExperimentRegistry.restart(),
          ),
        ],
      ]),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.titleLocale,
    this.subtitleLocale,
    this.percent,
    this.opensPicker = false,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// Locale of the text, so CJK names get their own glyph forms whatever
  /// the app language is.
  final Locale? titleLocale;
  final Locale? subtitleLocale;

  /// Percent translated; null shows nothing (System default, or while the
  /// numbers load).
  final int? percent;

  /// The Settings row: no radio, a chevron that says it opens the list.
  final bool opensPicker;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.bodyMedium!;
    final dim = scheme.secondary;

    return Semantics(
      selected: opensPicker ? null : selected,
      inMutuallyExclusiveGroup: !opensPicker,
      button: true,
      child: Material(
        color: selected ? scheme.primary.withAlpha(35) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              if (!opensPicker) ...[
                Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? scheme.primary : dim),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        locale: titleLocale,
                        style: text.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface)),
                    Text(subtitle,
                        locale: subtitleLocale,
                        style: text.copyWith(fontSize: 12.5, color: dim)),
                  ],
                ),
              ),
              if (percent != null) ...[
                const SizedBox(width: 12),
                Text(
                    percent == 0
                        ? _LanguageSettingsPanelState.labelLanguageNotTranslated
                        : _LanguageSettingsPanelState
                            .labelLanguageTranslatedPercent(percent!),
                    style: text.copyWith(
                        fontSize: 12.5,
                        color: percent! >= 90 ? scheme.primary : dim)),
              ],
              if (opensPicker) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 20, color: dim),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The full language list behind the Settings row, with a search box like
/// the spellcheck "Add language" picker. Pops the picked id.
class _LanguagePickerDialog extends StatefulWidget {
  const _LanguagePickerDialog({required this.preference, this.progress});

  final String preference;
  final Map<String, int>? progress;

  @override
  State<_LanguagePickerDialog> createState() => _LanguagePickerDialogState();
}

class _LanguagePickerDialogState extends State<_LanguagePickerDialog> {
  String query = "";
  late Map<String, int>? progress = widget.progress;

  @override
  void initState() {
    super.initState();
    if (progress == null) {
      TranslationProgress.load().then((value) {
        if (mounted) setState(() => progress = value);
      });
    }
  }

  static bool matches(AppLanguage l, String q) =>
      l.nativeName.toLowerCase().contains(q) ||
      LanguageNames.english(l.id).toLowerCase().contains(q) ||
      l.id.toLowerCase().startsWith(q);

  @override
  Widget build(BuildContext context) {
    final system = AppLanguages.resolve(AppLanguages.systemDefault,
        WidgetsBinding.instance.platformDispatcher.locales);
    final q = query.trim().toLowerCase();
    final languages = [
      for (final l in _LanguageSettingsPanelState.sortedLanguages)
        if (q.isEmpty || matches(l, q)) l
    ];
    final showSystem = q.isEmpty ||
        _LanguageSettingsPanelState.labelLanguageSystemDefault
            .toLowerCase()
            .contains(q);
    void pick(String id) => Navigator.of(context).pop(id);

    return SizedBox(
      width: 440,
      height: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.labelLow(_LanguageSettingsPanelState
              .labelLanguageSettingsNoteUntranslated),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _LanguageSettingsPanelState.labelLanguageSearch,
                isDense: true),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                if (showSystem)
                  _LanguageRow(
                    title:
                        _LanguageSettingsPanelState.labelLanguageSystemDefault,
                    subtitle: _LanguageSettingsPanelState
                        .labelLanguageSystemDefaultDescription(
                            system.nativeName),
                    subtitleLocale: system.locale,
                    selected: widget.preference == AppLanguages.systemDefault,
                    onTap: () => pick(AppLanguages.systemDefault),
                  ),
                for (final l in languages)
                  _LanguageRow(
                    title: l.nativeName,
                    titleLocale: l.locale,
                    subtitle: LanguageNames.english(l.id),
                    percent: progress?[l.id],
                    selected: widget.preference == l.id,
                    onTap: () => pick(l.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// English names of the shipped languages (translatable, so a German
/// interface can say "Spanisch" under "Español").
class LanguageNames {
  static String english(String id) => switch (id) {
        "ar" => languageNameArabic,
        "be" => languageNameBelarusian,
        "cs" => languageNameCzech,
        "da" => languageNameDanish,
        "de" => languageNameGerman,
        "en" => languageNameEnglish,
        "eo" => languageNameEsperanto,
        "es" => languageNameSpanish,
        "et" => languageNameEstonian,
        "eu" => languageNameBasque,
        "fa" => languageNamePersian,
        "fi" => languageNameFinnish,
        "fr" => languageNameFrench,
        "hu" => languageNameHungarian,
        "it" => languageNameItalian,
        "ja" => languageNameJapanese,
        "ko" => languageNameKorean,
        "nb" => languageNameNorwegianBokmal,
        "pl" => languageNamePolish,
        "pt" => languageNamePortuguese,
        "pt_BR" => languageNamePortugueseBrazil,
        "ro" => languageNameRomanian,
        "ru" => languageNameRussian,
        "sv" => languageNameSwedish,
        "ta" => languageNameTamil,
        "tr" => languageNameTurkish,
        "uk" => languageNameUkrainian,
        "zh" => languageNameChineseSimplified,
        "zh_Hant" => languageNameChineseTraditional,
        _ => AppLanguages.byId(id)?.nativeName ?? id,
      };

  static String get languageNameArabic => Intl.message("Arabic",
      desc: "Name of the Arabic language", name: "languageNameArabic");

  static String get languageNameBelarusian => Intl.message("Belarusian",
      desc: "Name of the Belarusian language", name: "languageNameBelarusian");

  static String get languageNameCzech => Intl.message("Czech",
      desc: "Name of the Czech language", name: "languageNameCzech");

  static String get languageNameDanish => Intl.message("Danish",
      desc: "Name of the Danish language", name: "languageNameDanish");

  static String get languageNameGerman => Intl.message("German",
      desc: "Name of the German language", name: "languageNameGerman");

  static String get languageNameEnglish => Intl.message("English",
      desc: "Name of the English language", name: "languageNameEnglish");

  static String get languageNameEsperanto => Intl.message("Esperanto",
      desc: "Name of the Esperanto language", name: "languageNameEsperanto");

  static String get languageNameSpanish => Intl.message("Spanish",
      desc: "Name of the Spanish language", name: "languageNameSpanish");

  static String get languageNameEstonian => Intl.message("Estonian",
      desc: "Name of the Estonian language", name: "languageNameEstonian");

  static String get languageNameBasque => Intl.message("Basque",
      desc: "Name of the Basque language", name: "languageNameBasque");

  static String get languageNamePersian => Intl.message("Persian",
      desc: "Name of the Persian (Farsi) language",
      name: "languageNamePersian");

  static String get languageNameFinnish => Intl.message("Finnish",
      desc: "Name of the Finnish language", name: "languageNameFinnish");

  static String get languageNameFrench => Intl.message("French",
      desc: "Name of the French language", name: "languageNameFrench");

  static String get languageNameHungarian => Intl.message("Hungarian",
      desc: "Name of the Hungarian language", name: "languageNameHungarian");

  static String get languageNameItalian => Intl.message("Italian",
      desc: "Name of the Italian language", name: "languageNameItalian");

  static String get languageNameJapanese => Intl.message("Japanese",
      desc: "Name of the Japanese language", name: "languageNameJapanese");

  static String get languageNameKorean => Intl.message("Korean",
      desc: "Name of the Korean language", name: "languageNameKorean");

  static String get languageNameNorwegianBokmal =>
      Intl.message("Norwegian Bokmål",
          desc: "Name of the Norwegian Bokmål language",
          name: "languageNameNorwegianBokmal");

  static String get languageNamePolish => Intl.message("Polish",
      desc: "Name of the Polish language", name: "languageNamePolish");

  static String get languageNamePortuguese => Intl.message("Portuguese",
      desc: "Name of the Portuguese language (as spoken in Portugal)",
      name: "languageNamePortuguese");

  static String get languageNamePortugueseBrazil =>
      Intl.message("Portuguese (Brazil)",
          desc: "Name of Brazilian Portuguese",
          name: "languageNamePortugueseBrazil");

  static String get languageNameRomanian => Intl.message("Romanian",
      desc: "Name of the Romanian language", name: "languageNameRomanian");

  static String get languageNameRussian => Intl.message("Russian",
      desc: "Name of the Russian language", name: "languageNameRussian");

  static String get languageNameSwedish => Intl.message("Swedish",
      desc: "Name of the Swedish language", name: "languageNameSwedish");

  static String get languageNameTamil => Intl.message("Tamil",
      desc: "Name of the Tamil language", name: "languageNameTamil");

  static String get languageNameTurkish => Intl.message("Turkish",
      desc: "Name of the Turkish language", name: "languageNameTurkish");

  static String get languageNameUkrainian => Intl.message("Ukrainian",
      desc: "Name of the Ukrainian language", name: "languageNameUkrainian");

  static String get languageNameChineseSimplified =>
      Intl.message("Chinese (Simplified)",
          desc: "Name of Chinese written in Simplified characters",
          name: "languageNameChineseSimplified");

  static String get languageNameChineseTraditional =>
      Intl.message("Chinese (Traditional)",
          desc: "Name of Chinese written in Traditional characters",
          name: "languageNameChineseTraditional");
}
