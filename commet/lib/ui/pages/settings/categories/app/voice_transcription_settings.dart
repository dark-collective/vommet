import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/voice_transcription.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart' show Panel, TileType;

/// Settings for on-device voice message transcription (#70): model,
/// language, downloaded models and saved transcripts.
class VoiceTranscriptionSettings extends StatefulWidget {
  const VoiceTranscriptionSettings({super.key});

  @override
  State<VoiceTranscriptionSettings> createState() =>
      _VoiceTranscriptionSettingsState();
}

class _VoiceTranscriptionSettingsState
    extends State<VoiceTranscriptionSettings> {
  /// Whisper language codes, each named in its own language.
  static const languages = {
    "auto": "Detect automatically",
    "en": "English",
    "de": "Deutsch",
    "fr": "Français",
    "es": "Español",
    "it": "Italiano",
    "pt": "Português",
    "nl": "Nederlands",
    "sv": "Svenska",
    "pl": "Polski",
    "cs": "Čeština",
    "uk": "Українська",
    "ru": "Русский",
    "tr": "Türkçe",
    "ar": "العربية",
    "hi": "हिन्दी",
    "zh": "中文",
    "ja": "日本語",
    "ko": "한국어",
  };

  final transcription = VoiceTranscription.instance;
  Map<TranscriptionModel, int> downloaded = {};

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final models = await transcription.downloadedModels();
    if (mounted) setState(() => downloaded = models);
  }

  Future<void> deleteModel(TranscriptionModel model) async {
    await transcription.deleteModel(model);
    await refresh();
  }

  Future<void> clearTranscripts() async {
    final ok = await AdaptiveDialog.confirmation(context,
        title: "Delete saved transcripts?",
        prompt:
            "Transcripts are kept on this device so they show up again without "
            "transcribing. Voice messages can be transcribed again later.",
        confirmationText: "Delete",
        cancelText: "Cancel",
        dangerous: true);
    if (ok == true) await transcription.clearTranscripts();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final language = VoiceTranscription.languagePreference.value;
    return Panel(
      header: "Voice message transcription",
      mode: TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const tiamat.Text.labelLow(
                "Voice messages are transcribed on this device, so the audio "
                "never leaves it. The speech model is downloaded once from "
                "Hugging Face, the first time you use it."),
            const SizedBox(height: 12),
            const tiamat.Text("Speech model"),
            const tiamat.Text.labelLow(
                "Tiny is the fastest, Small the most accurate. Base suits most "
                "computers."),
            const SizedBox(height: 8),
            tiamat.DropdownSelector<TranscriptionModel>(
              color: scheme.surfaceContainerLow,
              items: TranscriptionModel.values,
              value: transcription.model,
              itemBuilder: (m) => tiamat.Text(
                  "${m.label} (${m.sizeLabel})${downloaded.containsKey(m) ? ", downloaded" : ""}"),
              onItemSelected: (m) async {
                if (m == null) return;
                await VoiceTranscription.modelPreference.set(m.name);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 12),
            const tiamat.Text("Language"),
            const tiamat.Text.labelLow(
                "Setting your language helps with short or quiet messages."),
            const SizedBox(height: 8),
            tiamat.DropdownSelector<String>(
              color: scheme.surfaceContainerLow,
              items: languages.keys.toList(),
              value: languages.containsKey(language) ? language : "auto",
              itemBuilder: (code) => tiamat.Text(languages[code]!),
              onItemSelected: (code) async {
                if (code == null) return;
                await VoiceTranscription.languagePreference.set(code);
                if (mounted) setState(() {});
              },
            ),
            if (downloaded.isNotEmpty) ...[
              const SizedBox(height: 12),
              const tiamat.Text("Downloaded models"),
              for (final entry in downloaded.entries)
                Row(
                  children: [
                    Expanded(
                      child: tiamat.Text.labelLow(
                          "${entry.key.label}, ${(entry.value / 1000000).round()} MB"),
                    ),
                    IconButton(
                      tooltip: "Delete ${entry.key.label} model",
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => deleteModel(entry.key),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: tiamat.Button.secondary(
                text: "Delete saved transcripts",
                onTap: clearTranscripts,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
