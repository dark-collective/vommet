import 'package:commet/ui/molecules/settings_entry_bool.dart';
import 'package:commet/ui/molecules/timeline_events/message_translation_fold.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/translation/composer_translation.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Settings > App > Language > Translation (Vommet issues 680, 819-821): the
/// master switch, the language messages are translated into, the languages
/// you read, the translate buttons, and the downloaded language models with
/// Delete.
class TranslationSettingsPage extends StatefulWidget {
  const TranslationSettingsPage({this.translation, super.key});

  /// Defaults to [MessageTranslation.instance].
  final MessageTranslation? translation;

  static const label = "Translation";

  @override
  State<TranslationSettingsPage> createState() =>
      _TranslationSettingsPageState();
}

class _TranslationSettingsPageState extends State<TranslationSettingsPage> {
  late MessageTranslation translation;
  late Future<Map<TranslationModelSpec, int>> models;

  @override
  void initState() {
    super.initState();
    translation = widget.translation ?? MessageTranslation.instance;
    models = translation.downloadedModels();
    translation.modelsChanged.addListener(reload);
  }

  @override
  void dispose() {
    translation.modelsChanged.removeListener(reload);
    super.dispose();
  }

  void reload() {
    if (!mounted) return;
    setState(() => models = translation.downloadedModels());
  }

  String languageLabel(String code) => code == "auto"
      ? "Automatic: system language "
          "(${translationLanguageName(translation.automaticLanguage)})"
      : translationLanguageName(code);

  Future<void> delete(List<TranslationModelSpec> specs) async {
    final one = specs.length == 1;
    final ok = await AdaptiveDialog.confirmation(context,
        title: one
            ? "Delete ${directionName(specs.single)}?"
            : "Delete all language models?",
        prompt: one
            ? "Translating from ${translationLanguageName(specs.single.from)} "
                "will download it again."
            : "Translating will download them again.",
        confirmationText: "Delete",
        cancelText: "Cancel",
        dangerous: true);
    if (ok != true) return;
    for (final s in specs) {
      await translation.deleteModel(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return tiamat.Panel(
      header: TranslationSettingsPage.label,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Vommet issue 820: off hides every translation offer.
          card(context, [
            SettingsEntryBool(
              MessageTranslation.enabledPreference.value,
              title: "Translation",
              description: MessageTranslation.translationEnabled
                  ? "Translate messages and what you write, on this device."
                  : "Off: no Translate buttons, room suggestions or translated rooms. Rooms you turned “Translate this room” on for resume when you switch it back on.",
              onChanged: (value) async {
                await MessageTranslation.enabledPreference.set(value);
                if (mounted) setState(() {});
              },
            ),
          ]),
          if (MessageTranslation.translationEnabled) ...options(context),
        ],
      ),
    );
  }

  Future<void> addReadLanguages() async {
    final picked = await AdaptiveDialog.show<List<String>>(context,
        title: "Languages I read",
        scrollable: false,
        builder: (_) => ReadLanguagesPicker(
            target: translation.targetLanguage,
            selected: translation.readLanguages));
    if (picked == null) return;
    await translation.setReadLanguages(picked);
    if (mounted) setState(() {});
  }

  Future<void> removeReadLanguage(String code) async {
    await translation.setReadLanguages(
        translation.readLanguages.where((c) => c != code).toList());
    if (mounted) setState(() {});
  }

  /// Vommet issue 821: "Languages I read" chips.
  Widget readLanguages(BuildContext context) {
    final target = translation.targetLanguage;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Chip(
          key: const ValueKey("read-language-target"),
          label: tiamat.Text.labelLow(
              "${translationLanguageName(target)} · always"),
        ),
        for (final code in translation.readLanguages)
          InputChip(
            key: ValueKey("read-language-$code"),
            label: tiamat.Text.labelLow(translationLanguageName(code)),
            onDeleted: () => removeReadLanguage(code),
            deleteButtonTooltipMessage: "Remove",
          ),
        ActionChip(
          key: const ValueKey("read-language-add"),
          avatar: const Icon(Icons.add, size: 16),
          label: const tiamat.Text.labelLow("Add language"),
          onPressed: addReadLanguages,
        ),
      ],
    );
  }

  List<Widget> options(BuildContext context) => [
        const SizedBox(height: 12),
        card(context, [
          const tiamat.Text("Translate messages into"),
          const tiamat.Text.labelLow(
              "Messages in another language get a Translate button."),
          const SizedBox(height: 8),
          tiamat.DropdownSelector<String>(
            color: ColorScheme.of(context).surfaceContainerLow,
            items: ["auto", ...translation.targetLanguages],
            itemBuilder: (code) => tiamat.Text(languageLabel(code)),
            value: MessageTranslation.languagePreference.value,
            onItemSelected: (code) async {
              if (code == null) return;
              await translation.setTargetLanguage(code);
              if (mounted) setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 12),
        card(context, [
          const tiamat.Text("Languages I read"),
          const tiamat.Text.labelLow(
              "Messages and rooms in these languages get no Translate button and no room suggestion. Rooms in them stop translating."),
          const SizedBox(height: 8),
          readLanguages(context),
        ]),
        const SizedBox(height: 12),
        card(context, [
          SettingsEntryBool(
            MessageTranslation.buttonPreference.value,
            title: "Translate button on messages",
            description:
                "A Translate button under other people's messages in another language. Rooms you turned “Translate this room” on for still translate.",
            onChanged: (value) async {
              await MessageTranslation.buttonPreference.set(value);
              if (mounted) setState(() {});
            },
          ),
          // Vommet issue 834.
          SettingsEntryBool(
            ComposerTranslationPrefs.suggestPreference.value,
            title: "Suggest translating rooms",
            description:
                "Above the message box: “This room is mostly in Spanish. Translate it?” in rooms in another language.",
            onChanged: (value) async {
              await ComposerTranslationPrefs.suggestPreference.set(value);
              if (mounted) setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 12),
        card(context, [
          SettingsEntryBool(
            ComposerTranslationPrefs.buttonPreference.value,
            title: "Translate button when writing",
            description:
                "A 文A button in the message box of every room: pick a language per paragraph, and it's translated on this device when you send.",
            onChanged: (value) async {
              await ComposerTranslationPrefs.buttonPreference.set(value);
              if (mounted) setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 12),
        card(context, [
          const tiamat.Text("Downloaded languages"),
          const tiamat.Text.labelLow(
              "Translation runs on this device. Message text never leaves it."),
          const SizedBox(height: 4),
          FutureBuilder<Map<TranslationModelSpec, int>>(
            future: models,
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (data == null) return const SizedBox(height: 40);
              return modelList(context, data);
            },
          ),
        ]),
      ];

  Widget modelList(BuildContext context, Map<TranslationModelSpec, int> data) {
    final divider =
        Divider(height: 1, color: ColorScheme.of(context).outlineVariant);
    if (data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: tiamat.Text.labelLow(
            "None yet. A language downloads the first time you translate a message in it."),
      );
    }
    final specs = data.keys.toList()
      ..sort((a, b) => directionName(a).compareTo(directionName(b)));
    final total = data.values.fold(0, (sum, b) => sum + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in specs) ...[
          divider,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(child: tiamat.Text(directionName(s))),
                tiamat.Text.labelLow(formatModelSize(data[s]!)),
                const SizedBox(width: 12),
                tiamat.Button.secondary(
                    text: "Delete", onTap: () => delete([s])),
              ],
            ),
          ),
        ],
        divider,
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                  child: tiamat.Text.labelLow(
                      "${formatModelSize(total)} in total")),
              tiamat.Button.secondary(
                  text: "Delete all", onTap: () => delete(specs)),
            ],
          ),
        ),
      ],
    );
  }

  Widget card(BuildContext context, List<Widget> children) => Container(
        decoration: BoxDecoration(
            color: ColorScheme.of(context).surfaceContainer.withAlpha(100),
            border: BoxBorder.all(
                color: ColorScheme.of(context).secondary.withAlpha(20)),
            borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children),
        ),
      );
}

String directionName(TranslationModelSpec s) =>
    "${translationLanguageName(s.from)} → ${translationLanguageName(s.to)}";

/// "Languages I read" › Add language: search plus checkboxes; Done returns
/// the checked languages (Vommet issue 821).
class ReadLanguagesPicker extends StatefulWidget {
  const ReadLanguagesPicker(
      {required this.target, required this.selected, super.key});

  /// Your translation language: always read, so not listed.
  final String target;
  final List<String> selected;

  @override
  State<ReadLanguagesPicker> createState() => _ReadLanguagesPickerState();
}

class _ReadLanguagesPickerState extends State<ReadLanguagesPicker> {
  late final Set<String> checked = widget.selected.toSet();
  String query = "";

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final languages = translationLanguageNames.keys
        .where((c) => c != widget.target)
        .where((c) =>
            q.isEmpty || translationLanguageName(c).toLowerCase().contains(q))
        .toList()
      ..sort((a, b) =>
          translationLanguageName(a).compareTo(translationLanguageName(b)));
    return SizedBox(
      width: 440,
      height: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Search languages",
                isDense: true),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                for (final code in languages)
                  CheckboxListTile(
                    key: ValueKey("read-language-option-$code"),
                    dense: true,
                    value: checked.contains(code),
                    title: tiamat.Text(translationLanguageName(code)),
                    onChanged: (v) => setState(() =>
                        v == true ? checked.add(code) : checked.remove(code)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              tiamat.Button.secondary(
                  text: "Cancel", onTap: () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
              tiamat.Button(
                  text: "Done",
                  onTap: () => Navigator.of(context).pop([
                        for (final c in translationLanguageNames.keys)
                          if (checked.contains(c)) c
                      ])),
            ],
          ),
        ],
      ),
    );
  }
}
