// Vommet: Settings › General › Spellcheck (desktop). Downloaded dictionaries
// with a tick each (every ticked one is checked at once), remove, "Add a
// language…" and the personal dictionary.
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/utils/spellcheck/spellcheck.dart';
import 'package:commet/utils/spellcheck/spellcheck_catalog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SpellcheckSettingsPanel extends StatefulWidget {
  const SpellcheckSettingsPanel({super.key});

  static String get labelSpellcheckTitle => Intl.message("Spellcheck",
      desc: "Header for the spellcheck section in settings",
      name: "labelSpellcheckTitle");

  static String get labelSpellcheckToggle => Intl.message(
      "Check spelling while typing",
      desc: "Title of the toggle that turns spellcheck in the message box on",
      name: "labelSpellcheckToggle");

  static String get labelSpellcheckToggleDescription => Intl.message(
      "Underlines misspelled words in the message box. Checked on this device; nothing you type is sent anywhere.",
      desc: "Description of the spellcheck toggle",
      name: "labelSpellcheckToggleDescription");

  static String get labelSpellcheckLanguages => Intl.message("Languages",
      desc: "Heading above the list of downloaded spellcheck dictionaries",
      name: "labelSpellcheckLanguages");

  static String get labelSpellcheckLanguagesNote =>
      Intl.message("Every ticked language is checked at once.",
          desc: "Note under the spellcheck languages heading",
          name: "labelSpellcheckLanguagesNote");

  static String get labelSpellcheckNoDictionaries => Intl.message(
      "No dictionaries yet. Add a language to start checking.",
      desc: "Shown in spellcheck settings before any dictionary is downloaded",
      name: "labelSpellcheckNoDictionaries");

  static String labelSpellcheckDownloadLanguage(String language, String size) =>
      Intl.message("Download $language ($size)",
          desc:
              "Button in spellcheck settings that downloads the dictionary for the device's language",
          args: [language, size],
          name: "labelSpellcheckDownloadLanguage");

  static String labelSpellcheckDownloaded(String code, String size) =>
      Intl.message("$code · $size downloaded",
          desc:
              "Line under a downloaded spellcheck language: its code and size",
          args: [code, size],
          name: "labelSpellcheckDownloaded");

  static String get labelSpellcheckCouldNotRead =>
      Intl.message("Couldn't read this dictionary",
          desc: "Shown under a spellcheck dictionary that failed to load",
          name: "labelSpellcheckCouldNotRead");

  static String get labelSpellcheckRemove => Intl.message("Remove",
      desc: "Tooltip of the button that deletes a spellcheck dictionary",
      name: "labelSpellcheckRemove");

  static String get labelSpellcheckAddLanguage => Intl.message(
      "Add a language…",
      desc: "Button that opens the list of spellcheck dictionaries to download",
      name: "labelSpellcheckAddLanguage");

  static String labelSpellcheckPersonalDictionary(int count) =>
      Intl.plural(count,
          zero: "Personal dictionary",
          one: "Personal dictionary (1 word)",
          other: "Personal dictionary ($count words)",
          desc: "Button that opens the user's own spellcheck word list",
          args: [count],
          name: "labelSpellcheckPersonalDictionary");

  static String get labelSpellcheckSource => Intl.message(
      "Dictionaries are Hunspell dictionaries from the LibreOffice project, downloaded from GitHub once and kept on this device.",
      desc: "Where spellcheck dictionaries come from",
      name: "labelSpellcheckSource");

  static String labelSpellcheckDownloadFailed(String language) => Intl.message(
      "Couldn't download $language. Check your connection and try again.",
      desc: "Shown when a spellcheck dictionary download fails",
      args: [language],
      name: "labelSpellcheckDownloadFailed");

  @override
  State<SpellcheckSettingsPanel> createState() =>
      _SpellcheckSettingsPanelState();
}

String _size(int bytes) => "${(bytes / 1000000).toStringAsFixed(1)} MB";

class _SpellcheckSettingsPanelState extends State<SpellcheckSettingsPanel> {
  final spellcheck = Spellcheck.instance;
  String? error;

  @override
  void initState() {
    super.initState();
    spellcheck.addListener(onChanged);
    spellcheck.ensureInit();
  }

  @override
  void dispose() {
    spellcheck.removeListener(onChanged);
    super.dispose();
  }

  void onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> download(SpellcheckLanguage language) async {
    setState(() => error = null);
    try {
      await spellcheck.download(language);
    } catch (e, s) {
      Log.onError(e, s,
          content: "Spellcheck: download of ${language.code} failed");
      if (mounted) {
        setState(() => error =
            SpellcheckSettingsPanel.labelSpellcheckDownloadFailed(
                language.name));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = [
      for (final l in SpellcheckCatalog.all)
        if (spellcheck.installed.contains(l.code)) l
    ];
    final downloading = [
      for (final code in spellcheck.downloads.keys)
        if (SpellcheckCatalog.byCode(code) case final l?) l
    ];
    final offer = spellcheck.offer;

    return tiamat.Panel(
      header: SpellcheckSettingsPanel.labelSpellcheckTitle,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BooleanPreferenceToggle(
            preference: spellcheck.enabled,
            title: SpellcheckSettingsPanel.labelSpellcheckToggle,
            description:
                SpellcheckSettingsPanel.labelSpellcheckToggleDescription,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text(SpellcheckSettingsPanel.labelSpellcheckLanguages),
                tiamat.Text.labelLow(
                    SpellcheckSettingsPanel.labelSpellcheckLanguagesNote),
              ],
            ),
          ),
          if (installed.isEmpty && downloading.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: tiamat.Text.labelLow(
                  SpellcheckSettingsPanel.labelSpellcheckNoDictionaries),
            ),
          for (final l in installed) _installedRow(context, l),
          for (final l in downloading)
            _ProgressRow(
                language: l, progress: spellcheck.downloads[l.code] ?? 0),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (installed.isEmpty && downloading.isEmpty && offer != null)
                  tiamat.Button(
                    text:
                        SpellcheckSettingsPanel.labelSpellcheckDownloadLanguage(
                            offer.name, _size(offer.bytes)),
                    onTap: () => download(offer),
                  ),
                tiamat.Button.secondary(
                  text: SpellcheckSettingsPanel.labelSpellcheckAddLanguage,
                  onTap: () => AdaptiveDialog.show(context,
                      title: SpellcheckSettingsPanel.labelSpellcheckAddLanguage,
                      scrollable: false,
                      builder: (_) => _AddLanguageDialog(onDownload: download)),
                ),
                tiamat.Button.secondary(
                  text:
                      SpellcheckSettingsPanel.labelSpellcheckPersonalDictionary(
                          spellcheck.personal.value.length),
                  onTap: () => AdaptiveDialog.show(context,
                      title: SpellcheckSettingsPanel
                          .labelSpellcheckPersonalDictionary(0),
                      scrollable: false,
                      builder: (_) => const _PersonalDictionaryDialog()),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: tiamat.Text.labelLow(
                SpellcheckSettingsPanel.labelSpellcheckSource),
          ),
        ],
      ),
    );
  }

  Widget _installedRow(BuildContext context, SpellcheckLanguage l) {
    final failed = spellcheck.failedToLoad(l.code);
    return Row(
      children: [
        Checkbox(
          value: spellcheck.isTicked(l.code),
          onChanged: (v) => spellcheck.setTicked(l.code, v == true),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text(l.name),
              tiamat.Text.labelLow(failed
                  ? SpellcheckSettingsPanel.labelSpellcheckCouldNotRead
                  : SpellcheckSettingsPanel.labelSpellcheckDownloaded(
                      l.code, _size(l.bytes))),
            ],
          ),
        ),
        IconButton(
          tooltip: SpellcheckSettingsPanel.labelSpellcheckRemove,
          icon: Icon(Icons.delete_outline,
              size: 20, color: Theme.of(context).colorScheme.error),
          onPressed: () => spellcheck.remove(l.code),
        ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.language, required this.progress});
  final SpellcheckLanguage language;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: tiamat.Text(language.name)),
            tiamat.Text.labelLow("${(progress * 100).round()}%"),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress),
        ],
      ),
    );
  }
}

class _AddLanguageDialog extends StatefulWidget {
  const _AddLanguageDialog({required this.onDownload});
  final Future<void> Function(SpellcheckLanguage) onDownload;

  static String get labelSpellcheckSearchLanguages =>
      Intl.message("Search languages",
          desc: "Hint in the search box of the spellcheck language list",
          name: "labelSpellcheckSearchLanguages");

  static String get labelSpellcheckDownload => Intl.message("Download",
      desc: "Button that downloads one spellcheck dictionary",
      name: "labelSpellcheckDownload");

  static String get labelSpellcheckInstalled => Intl.message("Installed",
      desc: "Shown next to a spellcheck language that is already downloaded",
      name: "labelSpellcheckInstalled");

  @override
  State<_AddLanguageDialog> createState() => _AddLanguageDialogState();
}

class _AddLanguageDialogState extends State<_AddLanguageDialog> {
  final spellcheck = Spellcheck.instance;
  String query = "";

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final languages = [
      for (final l in SpellcheckCatalog.all)
        if (q.isEmpty ||
            l.name.toLowerCase().contains(q) ||
            l.code.toLowerCase().startsWith(q))
          l
    ]..sort((a, b) {
        final ai = spellcheck.installed.contains(a.code) ? 1 : 0;
        final bi = spellcheck.installed.contains(b.code) ? 1 : 0;
        return ai - bi;
      });

    return SizedBox(
      width: 440,
      height: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.labelLow(SpellcheckSettingsPanel.labelSpellcheckSource),
          const SizedBox(height: 8),
          TextField(
            autofocus: true,
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _AddLanguageDialog.labelSpellcheckSearchLanguages,
                isDense: true),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListenableBuilder(
              listenable: spellcheck,
              builder: (context, _) => ListView.builder(
                itemCount: languages.length,
                itemBuilder: (context, i) => _row(context, languages[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, SpellcheckLanguage l) {
    final progress = spellcheck.downloads[l.code];
    final installed = spellcheck.installed.contains(l.code);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tiamat.Text(l.name),
                tiamat.Text.labelLow("${l.code} · ${_size(l.bytes)}"),
                if (progress != null) ...[
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: progress),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (installed)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle,
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 4),
              tiamat.Text.labelLow(_AddLanguageDialog.labelSpellcheckInstalled),
            ])
          else if (progress != null)
            tiamat.Text.labelLow("${(progress * 100).round()}%")
          else
            TextButton(
              onPressed: () => widget.onDownload(l),
              child: Text(_AddLanguageDialog.labelSpellcheckDownload),
            ),
        ],
      ),
    );
  }
}

class _PersonalDictionaryDialog extends StatefulWidget {
  const _PersonalDictionaryDialog();

  static String get labelSpellcheckPersonalNote => Intl.message(
      "Words here are never underlined. Add them from the message box's right-click menu, or type one below.",
      desc: "Note at the top of the personal spellcheck dictionary",
      name: "labelSpellcheckPersonalNote");

  static String get labelSpellcheckAddWord => Intl.message("Add a word",
      desc: "Hint in the box that adds a word to the personal dictionary",
      name: "labelSpellcheckAddWord");

  @override
  State<_PersonalDictionaryDialog> createState() =>
      _PersonalDictionaryDialogState();
}

class _PersonalDictionaryDialogState extends State<_PersonalDictionaryDialog> {
  final spellcheck = Spellcheck.instance;
  final input = TextEditingController();

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> add() async {
    final word = input.text.trim();
    if (word.isEmpty || word.contains(RegExp(r"\s"))) return;
    input.clear();
    await spellcheck.addWord(word);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      height: 420,
      child: ListenableBuilder(
        listenable: spellcheck,
        builder: (context, _) {
          final words = spellcheck.personal.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tiamat.Text.labelLow(
                  _PersonalDictionaryDialog.labelSpellcheckPersonalNote),
              const SizedBox(height: 8),
              TextField(
                controller: input,
                decoration: InputDecoration(
                    hintText: _PersonalDictionaryDialog.labelSpellcheckAddWord,
                    isDense: true,
                    suffixIcon: IconButton(
                        icon: const Icon(Icons.add), onPressed: add)),
                onSubmitted: (_) => add(),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (final w in words)
                      Row(children: [
                        Expanded(child: tiamat.Text(w)),
                        IconButton(
                          tooltip:
                              SpellcheckSettingsPanel.labelSpellcheckRemove,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => spellcheck.removeWord(w),
                        ),
                      ]),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
