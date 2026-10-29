import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/push_notification/web/browser_notifications.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 767: the web app's browser notification permission. Browsers
/// only show their permission prompt after a user action, so the app asks
/// first (once, Yes / No) and Settings › Notifications has an Enable button.
class WebNotificationPermission {
  static String get promptTitle => Intl.message("Turn on notifications?",
      name: "webNotificationsPromptTitle",
      desc:
          "Title of the web app's one-time question about browser notifications");

  static String get prompt => Intl.message(
      "Vommet can show a notification for new messages, invites and calls "
      "while this tab is open in the background. Your browser will ask you "
      "to allow it. You can change this later in Settings › Notifications.",
      name: "webNotificationsPrompt",
      desc:
          "Body of the web app's one-time question about browser notifications");

  static String get rowTitle => Intl.message("Browser notifications",
      name: "webNotificationsRowTitle",
      desc: "Title of the web app's browser notification permission row");

  static String get statusOn =>
      Intl.message("On. Notifications show while this tab is open.",
          name: "webNotificationsStatusOn",
          desc: "Browser notifications are allowed");

  static String get statusOff => Intl.message(
      "Off. Enable them to get notifications while this tab is open.",
      name: "webNotificationsStatusOff",
      desc: "Browser notifications are not allowed yet");

  static String get statusBlocked => Intl.message(
      "Blocked by the browser. Allow notifications for this site in the "
      "browser's site settings, then reload the page.",
      name: "webNotificationsStatusBlocked",
      desc:
          "Browser notifications were denied; the browser won't ask again, the user must allow them in site settings");

  static String get statusUnsupported =>
      Intl.message("This browser can't show notifications from a web page.",
          name: "webNotificationsStatusUnsupported",
          desc: "The browser has no notification support");

  static String get enable => Intl.message("Enable",
      name: "webNotificationsEnable",
      desc: "Button that asks the browser for notification permission");

  /// Whether to ask at startup: only on the web, once, while the browser
  /// hasn't been asked yet and notifications are on in the app.
  static bool shouldAsk(
      {required bool isWeb,
      required String permission,
      required bool alreadyAsked,
      required bool notificationsEnabled}) {
    return isWeb &&
        permission == "default" &&
        !alreadyAsked &&
        notificationsEnabled;
  }

  static Future<bool> request() async {
    final granted =
        await NotificationManager.notifier?.requestPermission() ?? false;
    Log.i("Browser notification permission: "
        "${browserNotificationPermission()}");
    return granted;
  }

  /// The one-time question, after the main page is up.
  static Future<void> run(BuildContext context) async {
    if (!shouldAsk(
        isWeb: PlatformUtils.isWeb,
        permission: browserNotificationPermission(),
        alreadyAsked: preferences.webNotificationsAsked.value,
        notificationsEnabled: preferences.enableNotifications.value)) {
      return;
    }

    try {
      final yes = await AdaptiveDialog.confirmation(context,
          title: promptTitle, prompt: prompt);
      // Dismissed without an answer: ask again next time.
      if (yes == null) return;
      await preferences.webNotificationsAsked.set(true);
      // The Yes tap is the user action the browser needs.
      if (yes) await request();
    } catch (e, s) {
      Log.onError(e, s, content: "Browser notification prompt failed");
    }
  }
}

/// The row at the top of Settings › Notifications on the web.
class WebNotificationPermissionRow extends StatefulWidget {
  const WebNotificationPermissionRow({super.key});

  @override
  State<WebNotificationPermissionRow> createState() =>
      _WebNotificationPermissionRowState();
}

class _WebNotificationPermissionRowState
    extends State<WebNotificationPermissionRow> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final permission = browserNotificationPermission();
    final status = switch (permission) {
      "granted" => WebNotificationPermission.statusOn,
      "denied" => WebNotificationPermission.statusBlocked,
      "unsupported" => WebNotificationPermission.statusUnsupported,
      _ => WebNotificationPermission.statusOff,
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(
          permission == "granted"
              ? Icons.notifications_active
              : Icons.notifications_off,
          color: Theme.of(context).colorScheme.primary),
      title: tiamat.Text.label(status),
      trailing: permission == "default"
          ? tiamat.Button(
              text: WebNotificationPermission.enable,
              isLoading: busy,
              onTap: () async {
                setState(() => busy = true);
                await preferences.webNotificationsAsked.set(true);
                await WebNotificationPermission.request();
                if (mounted) setState(() => busy = false);
              })
          : null,
    );
  }
}
