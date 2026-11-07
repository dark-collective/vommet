import 'package:commet/ui/pages/settings/categories/app/language_settings_panel.dart';
import 'package:commet/ui/pages/settings/categories/app/spellcheck_settings_panel.dart';
import 'package:commet/ui/pages/settings/categories/app/translation_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/voice_transcription_settings.dart';
import 'package:commet/utils/spellcheck/spellcheck.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/voice_transcription.dart';
import 'package:flutter/material.dart';

/// Settings > App > Language (Vommet issue 819): the app language, message
/// translation (where it can run), voice message transcription and
/// spellcheck (desktop), which were on General and their own Translation
/// tab.
class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LanguageSettingsPanel(collapsed: true),
        if (MessageTranslation.instance.available) ...[
          const SizedBox(height: 10),
          const TranslationSettingsPage(),
        ],
        if (VoiceTranscription.supported) ...[
          const SizedBox(height: 10),
          const VoiceTranscriptionSettings(),
        ],
        if (Spellcheck.supported) ...[
          const SizedBox(height: 10),
          const SpellcheckSettingsPanel(),
        ],
      ],
    );
  }
}
