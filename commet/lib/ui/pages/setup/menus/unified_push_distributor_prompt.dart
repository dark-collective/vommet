import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/setup/menus/unified_push_setup.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:unifiedpush/unifiedpush.dart';

/// Vommet (Vommet issue 168): with UnifiedPush on and several distributor
/// apps installed but none chosen (or the chosen one uninstalled), no
/// notifications arrive and nothing said so. The startup check
/// ([UnifiedPushNotifier.ensureRegistered]) handles the cases it can decide
/// alone; this asks the user for the rest, once per start until they choose.
class UnifiedPushDistributorPrompt {
  static String get title => Intl.message("Choose a push distributor",
      name: "unifiedPushChooseDistributorTitle",
      desc:
          "Title of the prompt shown at startup when UnifiedPush is on but no distributor app is chosen");

  static String get prompt => Intl.message(
      "Notifications are on, but no UnifiedPush distributor is chosen, so "
      "none will arrive. Choose one of the apps on this device. You can "
      "change it later in Settings › Notifications.",
      name: "unifiedPushChooseDistributorPrompt",
      desc:
          "Explains that notifications won't arrive until a UnifiedPush distributor app is chosen");

  static String get later => Intl.message("Later",
      name: "unifiedPushChooseDistributorLater",
      desc:
          "Closes the UnifiedPush distributor prompt; it asks again next start");

  static Future<void> run(BuildContext context) async {
    final notifier = NotificationManager.notifier;
    if (notifier is! UnifiedPushNotifier || !notifier.enabled) return;

    try {
      await NotificationManager.notifierLoading;
      await notifier.startupCheck;

      final choice = notifier.distributorChoice;
      if (choice == null || !context.mounted) return;

      final pick = await AdaptiveDialog.show<String>(context,
          title: title, builder: (context) => _PromptView(choice));
      if (pick == null) return;

      await UnifiedPush.saveDistributor(pick);
      await UnifiedPush.registerApp(notifier.instance);
      notifier.distributorChoice = null;
      Log.i("UnifiedPush distributor chosen at startup: $pick");
    } catch (e, s) {
      Log.onError(e, s, content: "UnifiedPush distributor prompt failed");
    }
  }
}

class _PromptView extends StatelessWidget {
  const _PromptView(this.distributors);
  final List<String> distributors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            tiamat.Text.label(UnifiedPushDistributorPrompt.prompt),
            const SizedBox(height: 12),
            for (final d in distributors)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  height: 40,
                  child: tiamat.Button(
                    text: UnifiedPushSetupViewState.distributorName(d),
                    onTap: () => Navigator.pop(context, d),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            tiamat.Button.secondary(
              text: UnifiedPushDistributorPrompt.later,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
