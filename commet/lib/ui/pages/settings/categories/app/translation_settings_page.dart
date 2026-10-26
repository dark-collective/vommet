import 'package:commet/ui/molecules/settings_entry_bool.dart';
import 'package:commet/ui/molecules/timeline_events/message_translation_fold.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/settings_tab.dart';
import 'package:commet/utils/translation/composer_translation.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Settings > App > Translation (Vommet issue 680): the language messages are
/// translated into, the composer's translate button, and the downloaded
/// language models with Delete.
class TranslationSettingsPage extends StatefulWidget {
  const TranslationSettingsPage({this.translation, super.key});

  /// Defaults to [MessageTranslation.instance].
  final MessageTranslation? translation;

  static const label = "Translation";

  /// [tabs] with a Translation tab before Advanced (or at the end), where
  /// translation can run.
  static List<SettingsTab> withTab(List<SettingsTab> tabs,
      {required String advancedLabel, bool? supported}) {
    if (!(supported ?? MessageTranslation.instance.supported)) return tabs;
    final tab = SettingsTab(
        label: label,
        icon: Icons.translate,
        pageBuilder: (context) => const TranslationSettingsPage());
    final i = tabs.indexWhere((t) => t.label == advancedLabel);
    return [...tabs]..insert(i < 0 ? tabs.length : i, tab);
  }

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
        ],
      ),
    );
  }

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
