import 'package:commet/ui/pages/secure_setup/secure_setup_widgets.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Optional guidance only: opening help never creates keys or saves a secret.
class SecureSetupStorageHelp extends StatelessWidget {
  const SecureSetupStorageHelp({super.key});

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: SetupPage(
          onBack: () => Navigator.of(context).pop(),
          children: [
            SetupTitle(secureSetupNoManagerTitle),
            const SizedBox(height: 16),
            SetupBody(secureSetupNoManagerBody, align: TextAlign.start),
            const SizedBox(height: 16),
            SetupCallout(
                Icons.checklist_outlined,
                Theme.of(context).colorScheme.primary,
                secureSetupStorageBeforeTitle,
                secureSetupStorageBeforeBody),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.all(12)),
                onPressed: () => LinkUtils.open(
                    Uri.parse('https://bitwarden.com/download/')),
                icon: const Icon(Icons.open_in_new),
                label: Text(secureSetupStorageBitwarden,
                    textAlign: TextAlign.center)),
            const SizedBox(height: 8),
            SetupBody(secureSetupStorageExternal, align: TextAlign.start),
            const SizedBox(height: 16),
            SetupBody(secureSetupStorageAlternatives, align: TextAlign.start),
            const SizedBox(height: 16),
            SetupCallout(Icons.lock_outline, setupWarn,
                secureSetupStoragePaperTitle, secureSetupStoragePaperBody),
            const SizedBox(height: 16),
          ],
          bottom: [
            SetupPrimaryButton(secureSetupStorageBack,
                onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      );
}

String get secureSetupStorageBeforeTitle =>
    Intl.message('Before you save your key',
        name: 'secureSetupStorageBeforeTitle',
        desc: 'Heading for password manager storage instructions');

String get secureSetupStorageBeforeBody => Intl.message(
    '1. Set up or open your password manager.\n2. Create a separate Vommet recovery entry.\n3. Save the whole key, then return here to check it.',
    name: 'secureSetupStorageBeforeBody',
    desc: 'Steps to manually store recovery access, with line breaks');

String get secureSetupStorageBitwarden => Intl.message('Bitwarden downloads',
    name: 'secureSetupStorageBitwarden',
    desc: 'External link to the existing Bitwarden download page');

String get secureSetupStorageExternal => Intl.message(
    'Opens an external website. You save the key yourself; opening the link does not send it.',
    name: 'secureSetupStorageExternal',
    desc: 'Explains the external password manager link');

String get secureSetupStorageAlternatives => Intl.message(
    'A six-word phrase and a self-chosen recovery password are other setup options. Both still need a safe copy.',
    name: 'secureSetupStorageAlternatives',
    desc: 'Nonjudgmental guidance about the existing recovery alternatives');

String get secureSetupStoragePaperTitle => Intl.message('Keeping a paper copy?',
    name: 'secureSetupStoragePaperTitle',
    desc: 'Heading about keeping a physical copy of recovery access');

String get secureSetupStoragePaperBody => Intl.message(
    'Paper is not encrypted. Keep it locked away. Avoid screenshots that may sync to cloud photos.',
    name: 'secureSetupStoragePaperBody',
    desc: 'Guidance for keeping a physical recovery copy');

String get secureSetupStorageBack => Intl.message('Back to setup',
    name: 'secureSetupStorageBack',
    desc: 'Close optional recovery storage help');

String get secureSetupNoManagerTitle => Intl.message("No password manager yet?",
    name: "secureSetupNoManagerTitle",
    desc: "Title of the card recommending a password manager");

String get secureSetupNoManagerBody => Intl.message(
    "Use an encrypted password manager you can open from another device. Make sure you know how to recover access to it.",
    name: "secureSetupNoManagerBody",
    desc: "Body of the card recommending Bitwarden");
