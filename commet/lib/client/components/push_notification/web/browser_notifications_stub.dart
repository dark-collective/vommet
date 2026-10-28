/// "granted", "denied", "default", or "unsupported" when the browser has no
/// Notification API (always, off the web).
String browserNotificationPermission() => "unsupported";

/// Asks the browser for notification permission and returns the answer.
/// Call it from a user action: browsers ignore requests made without one.
Future<String> requestBrowserNotificationPermission() async => "unsupported";

/// Shows a notification; false if the browser refused. A notification with
/// the same [tag] replaces the earlier one.
bool showBrowserNotification(
        {required String title,
        required String body,
        required String tag,
        String? icon,
        void Function()? onClick}) =>
    false;

/// Closes the notifications shown here whose tag starts with [tagPrefix].
void closeBrowserNotifications(String tagPrefix) {}

/// Brings the app's tab to the front.
void focusBrowserTab() {}
