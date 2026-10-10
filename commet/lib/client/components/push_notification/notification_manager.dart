import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/push_notification/android/android_notifier.dart';
import 'package:commet/client/components/push_notification/android/firebase_push_notifier.dart';
import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:commet/client/components/push_notification/linux/linux_notifier.dart';
import 'package:commet/client/components/push_notification/modifiers/do_not_disturb.dart';
import 'package:commet/client/components/push_notification/modifiers/linux_notification_formatting.dart';
import 'package:commet/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:commet/client/components/push_notification/modifiers/suppress_active_room.dart';
import 'package:commet/client/components/push_notification/modifiers/suppress_other_device_active.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notifier.dart';
import 'package:commet/client/components/push_notification/windows/windows_notifier.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/notify_counts.dart';
import 'package:media_kit/media_kit.dart';

class NotificationManager {
  static Notifier? _notifier;

  static Notifier? get notifier => _notifier;

  static final List<NotificationModifier> _modifiers =
      List.empty(growable: true);

  static Future<void>? notifierLoading;

  static Player? _player;

  static Player getSoundPlayer() {
    _player ??= Player(configuration: PlayerConfiguration());
    _player!.setVolume(preferences.notificationsVolume.value);

    return _player!;
  }

  static Future<void> init({bool isBackgroundService = false}) async {
    Log.i("Initializing NotificationManager");
    Log.i("Existing notifier: $_notifier");
    _notifier ??= _getNotifier(isBackgroundService: isBackgroundService);

    _modifiers.clear();
    addModifier(NotificationModifierSuppressActiveRoom());
    if (BuildConfig.ANDROID) {
      addModifier(NotificationModifierSuppressOtherActiveDevice());
    }

    if (PlatformUtils.isLinux) {
      addModifier(NotificationModifierLinuxFormatting());
    }

    notifierLoading = _notifier?.init();
  }

  static Notifier? _getNotifier({bool isBackgroundService = false}) {
    if (PlatformUtils.isLinux) {
      return LinuxNotifier();
    }

    if (PlatformUtils.isWindows) {
      return WindowsNotifier();
    }

    if (PlatformUtils.isAndroid) {
      // We dont want the background service to actually listen for incoming notifications
      // The main isolate will listen and pass messages to the service
      if (isBackgroundService) {
        return AndroidNotifier();
      } else {
        if (BuildConfig.ENABLE_GOOGLE_SERVICES) {
          return FirebasePushNotifier();
        }

        return UnifiedPushNotifier();
      }
    }

    return null;
  }

  static void addModifier(NotificationModifier modifier) {
    _modifiers.add(modifier);
  }

  static void removeModifier(NotificationModifier modifier) {
    _modifiers.remove(modifier);
  }

  static Future<void> clearNotifications(Room room) async {
    await notifier?.clearNotifications(room);
  }

  static Future<void> notify(NotificationContent notification,
      {bool forceShow = false,
      Function(String reason)? onNotificationRejected}) async {
    // Vommet: count what happened to each notification (opt-in diagnostics).
    final watch = Stopwatch()..start();
    var outcome = NotifyOutcome.failed;
    try {
      outcome = await _notify(notification,
          forceShow: forceShow, onNotificationRejected: onNotificationRejected);
    } finally {
      unawaited(NotifyCounts.add(outcome, watch.elapsedMilliseconds));
    }
  }

  static Future<NotifyOutcome> _notify(NotificationContent notification,
      {bool forceShow = false,
      Function(String reason)? onNotificationRejected}) async {
    if (_notifier == null) {
      Log.e("Failed to show notification, notifier has not been initialzied");
      onNotificationRejected?.call("Notifier has not been initialized");
      return NotifyOutcome.failed;
    }

    NotificationContent? content = notification;

    if (preferences.enableNotifications.value == false) {
      return NotifyOutcome.droppedOff;
    }

    NotifyOutcome? quieted;
    for (var modifier in _modifiers) {
      Log.d("Processing modifier: $modifier");
      if (forceShow) {
        if (modifier is NotificationModifierSuppressActiveRoom) continue;
        if (modifier is NotificationModifierSuppressOtherActiveDevice) continue;
      }

      final priority = content!.priority;
      content = await modifier.process(content,
          onNotificationRejected: onNotificationRejected);
      if (content == null) {
        Log.d("Modifier returned null notification, returning");

        onNotificationRejected?.call(
            "Notification modifier '${modifier}' rejected the notification");
        return switch (modifier) {
          NotificationModifierSuppressActiveRoom _ =>
            NotifyOutcome.droppedActiveRoom,
          NotificationModifierDoNotDisturb _ => NotifyOutcome.droppedDnd,
          _ => NotifyOutcome.droppedOther,
        };
      }
      // NotificationPriority runs normal, low: a higher index is quieter.
      if (content.priority.index > priority.index) {
        quieted ??= modifier is NotificationModifierSuppressOtherActiveDevice
            ? NotifyOutcome.quietedOtherDevice
            : NotifyOutcome.quietedOther;
      }
    }

    Log.i("Displaying notification content: $content");
    await _notifier!.notify(content!);
    if (content is ErrorNotificationContent) return NotifyOutcome.errorNotice;
    return quieted ?? NotifyOutcome.shown;
  }
}
