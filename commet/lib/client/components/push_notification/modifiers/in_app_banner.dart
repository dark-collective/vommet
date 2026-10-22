import 'dart:async';

import 'package:commet/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// While the app is in the foreground, shows message notifications as an
/// in-app banner (Discord-style) instead of a system notification.
///
/// Runs after the suppression modifiers, so the open room and muted rooms
/// are already filtered out. A notification quieted because you're active on
/// another device stays a quiet system notification rather than popping up.
class NotificationModifierInAppBanner implements NotificationModifier {
  /// The banner host listens here; with no listener (no main page yet, e.g.
  /// still on the login screen) notifications go to the system as before.
  static final StreamController<MessageNotificationContent> banners =
      StreamController.broadcast();

  final Future<bool> Function() isEnabled;
  final Future<bool> Function() isForeground;

  NotificationModifierInAppBanner(
      {Future<bool> Function()? isEnabled,
      Future<bool> Function()? isForeground})
      : isEnabled = isEnabled ??
            (() async => preferences.inAppNotificationBanners.value),
        isForeground = isForeground ?? _appIsInForeground;

  static Future<bool> _appIsInForeground() async {
    if (PlatformUtils.isLinux || PlatformUtils.isWindows) {
      return windowManager.isFocused();
    }
    return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  Future<NotificationContent?> process(NotificationContent content,
      {Function(String reason)? onNotificationRejected}) async {
    if (content is! MessageNotificationContent) return content;
    if (content.priority == NotificationPriority.low) return content;
    if (!banners.hasListener) return content;
    if (!await isEnabled()) return content;
    if (!await isForeground()) return content;

    banners.add(content);
    onNotificationRejected?.call(
        "Shown as an in-app banner because the app is open. Turn off 'In-app notification banners' to get system notifications instead.");
    return null;
  }
}
