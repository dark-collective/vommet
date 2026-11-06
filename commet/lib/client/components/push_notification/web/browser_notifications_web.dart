import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS("Notification")
external JSAny? get _notificationApi;

bool get _supported => _notificationApi != null;

/// The notifications shown by this tab, by tag, so reading a chat can close
/// them.
final Map<String, web.Notification> _shown = {};

String browserNotificationPermission() {
  if (!_supported) return "unsupported";
  return web.Notification.permission;
}

Future<String> requestBrowserNotificationPermission() async {
  if (!_supported) return "unsupported";
  final result = await web.Notification.requestPermission().toDart;
  return result.toDart;
}

bool showBrowserNotification(
    {required String title,
    required String body,
    required String tag,
    String? icon,
    void Function()? onClick}) {
  if (browserNotificationPermission() != "granted") return false;
  try {
    // Chrome on Android only allows notifications from a service worker;
    // the constructor throws there.
    final notification = web.Notification(
        title,
        web.NotificationOptions(
            body: body, tag: tag, icon: icon ?? "icons/Icon-192.png"));
    _shown[tag] = notification;
    notification.onclick = ((web.Event event) {
      event.preventDefault();
      web.window.focus();
      notification.close();
      onClick?.call();
    }).toJS;
    notification.onclose = ((web.Event _) {
      if (identical(_shown[tag], notification)) _shown.remove(tag);
    }).toJS;
    return true;
  } catch (_) {
    return false;
  }
}

void closeBrowserNotifications(String tagPrefix) {
  for (final tag in _shown.keys.toList()) {
    if (!tag.startsWith(tagPrefix)) continue;
    _shown.remove(tag)?.close();
  }
}

void focusBrowserTab() => web.window.focus();
