import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/setup/onboarding/onboarding_setup.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: Settings › General › First-run setup, to go through the
/// onboarding pages again (Vommet issue 524).
class OnboardingRerunPanel extends StatelessWidget {
  const OnboardingRerunPanel({super.key});

  static const searchId = "vommet_onboarding_rerun";

  @override
  Widget build(BuildContext context) {
    return SettingsSearchTarget(
      ids: const [searchId],
      child: tiamat.Panel(
        header: onboardingRerunHeader,
        mode: tiamat.TileType.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              tiamat.Text.labelLow(onboardingRerunDescription),
              tiamat.Button(
                text: onboardingRerunButton,
                onTap: () => OnboardingSetup.open(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String get onboardingRerunHeader => Intl.message("First-run setup",
    name: "onboardingRerunHeader",
    desc:
        "Header of the Settings section that runs the onboarding pages again");

String get onboardingRerunDescription => Intl.message(
    "Pick your language, layout, theme, message spacing and whether new rooms are encrypted, as on the first start.",
    name: "onboardingRerunDescription",
    desc: "Describes the button that runs the onboarding pages again");

String get onboardingRerunButton => Intl.message("Run setup again",
    name: "onboardingRerunButton",
    desc: "Button in Settings that runs the onboarding pages again");
