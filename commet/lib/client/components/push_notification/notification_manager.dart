import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/push_notification/android/android_notifier.dart';
import 'package:commet/client/components/push_notification/android/firebase_push_notifier.dart';
import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:commet/client/components/push_notification/darwin/darwin_notifier.dart';
import 'package:commet/client/components/push_notification/linux/linux_notifier.dart';
import 'package:commet/client/components/push_notification/modifiers/do_not_disturb.dart';
import 'package:commet/client/components/push_notification/modifiers/linux_notification_formatting.dart';
import 'package:commet/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:commet/client/components/push_notification/modifiers/redacted_mode.dart';
import 'package:commet/client/components/push_notification/modifiers/suppress_active_room.dart';
import 'package:commet/client/components/push_notification/modifiers/suppress_other_device_active.dart';
import 'package:commet/client/components/push_notification/modifiers/in_app_banner.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notifier.dart';
import 'package:commet/client/components/push_notification/web/web_notifier.dart';
import 'package:commet/client/components/push_notification/windows/windows_notifier.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/build_config.dart';
import 'package:flutter/widgets.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/main_spans.dart';
import 'package:commet/telemetry/notify_counts.dart';
import 'package:media_kit/media_kit.dart';

class NotificationManager {
  static Notifier? _notifier;

  static Notifier? get notifier => _notifier;

  /// The Android notifier, also when push wraps it.
  static AndroidNotifier? get androidNotifier => switch (_notifier) {
        AndroidNotifier n => n,
        UnifiedPushNotifier n => n.notifier,
        FirebasePushNotifier n => n.notifier,
        _ => null,
      };

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

    if (!isBackgroundService) {
      addModifier(NotificationModifierInAppBanner());
    }

    // Vommet issue 473: after the banner, before any formatting.
    addModifier(NotificationModifierRedacted());

    if (PlatformUtils.isLinux) {
      addModifier(NotificationModifierLinuxFormatting());
    }

    notifierLoading = _notifier?.init();

    if (!isBackgroundService) _watchReadRooms();
  }

  static Notifier? _getNotifier({bool isBackgroundService = false}) {
    // Vommet issue 767: browser notifications while the tab is open.
    if (PlatformUtils.isWeb) {
      return WebNotifier();
    }

    if (PlatformUtils.isLinux) {
      return LinuxNotifier();
    }

    if (PlatformUtils.isWindows) {
      return WindowsNotifier();
    }

    // Vommet issue 531: macOS and iOS (local notifications, no push yet).
    if (DarwinNotifier.isSupported) {
      return DarwinNotifier();
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

  /// Vommet issue 508: rooms that may still have a system notification on
  /// screen. Once sync has counted such a room unread and later counts it
  /// read (here or on another device), its notifications are closed.
  static final Map<(String, String), _NotifiedRoom> _notifiedRooms = {};

  /// Vommet issue 693: when each [_NotifiedRoom.quiet] room was last
  /// notified, to tell whether it has been read (on any device) since.
  static final Map<(String, String), DateTime> _quietSince = {};

  static StreamSubscription? _onSync;
  static AppLifecycleListener? _onResume;

  /// Called by the notifiers when they show a room's message notification.
  static void noteRoomNotified(String clientId, String roomId) {
    final room = clientManager?.getClient(clientId)?.getRoom(roomId);
    final key = (clientId, roomId);
    if (_notifiedRooms[key] == _NotifiedRoom.unread) return;
    if ((room?.notificationCount ?? 0) > 0) {
      _notifiedRooms[key] = _NotifiedRoom.unread;
      _quietSince.remove(key);
    } else {
      // Often a push that beat the sync, which may only arrive after the
      // message was read on another device.
      _notifiedRooms[key] = _NotifiedRoom.quiet;
      _quietSince[key] = DateTime.now();
    }
  }

  /// Vommet issue 693: the account's own read receipt in [room] (from any
  /// device) is newer than [since].
  static bool readSince(Room room, DateTime? since) {
    if (since == null || room is! MatrixRoom) return false;
    final receipt = room.matrixRoom.receiptState.global.latestOwnReceipt;
    return receipt != null && receipt.ts > since.millisecondsSinceEpoch;
  }

  static void _watchReadRooms() {
    if (clientManager == null) return;
    _onSync ??= clientManager!.onSync.stream
        .listen((_) => closeReadRooms(afterSync: true));
    // Android shows notifications from the push isolate too, and Linux from
    // an earlier run: pick those up at start and whenever the app returns.
    // Counts may be stale until then, so the next sync judges them.
    _onResume ??= AppLifecycleListener(onResume: _noteShownNotifications);
    _noteShownNotifications();
  }

  static Future<void> _noteShownNotifications() async {
    try {
      await notifierLoading;
      final rooms = <(String, String)>[];
      final notifier = _notifier;
      if (notifier is LinuxNotifier) {
        for (final key in notifier.roomNotificationIds.keys) {
          final split = key.indexOf("|");
          if (split > 0) {
            rooms.add((key.substring(0, split), key.substring(split + 1)));
          }
        }
      }

      final android = androidNotifier;
      if (android != null) {
        for (final roomId in await android.activeMessageRoomIds()) {
          for (final client in clientManager?.clients ?? <Client>[]) {
            if (client.getRoom(roomId) != null) {
              rooms.add((client.identifier, roomId));
            }
          }
        }
      }

      for (final key in rooms) {
        if (_notifiedRooms[key] != _NotifiedRoom.unread) {
          _notifiedRooms[key] = _NotifiedRoom.recheck;
        }
      }
    } catch (e, s) {
      Log.onError(e, s);
    }
  }

  static Future<void> closeReadRooms({bool afterSync = false}) async {
    for (final key in _notifiedRooms.keys.toList()) {
      final room = clientManager?.getClient(key.$1)?.getRoom(key.$2);
      if (room == null) continue;
      if (room.notificationCount > 0) {
        _notifiedRooms[key] = _NotifiedRoom.unread;
        _quietSince.remove(key);
        continue;
      }
      final state = _notifiedRooms[key];
      final read = state == _NotifiedRoom.unread ||
          (afterSync && state == _NotifiedRoom.recheck) ||
          (afterSync &&
              state == _NotifiedRoom.quiet &&
              readSince(room, _quietSince[key]));
      if (!read) continue;

      _notifiedRooms.remove(key);
      _quietSince.remove(key);
      try {
        await clearNotifications(room);
      } catch (e, s) {
        Log.onError(e, s);
      }
    }
  }

  static Future<void> notify(NotificationContent notification,
      {bool forceShow = false,
      Function(String reason)? onNotificationRejected}) async {
    // Vommet: count what happened to each notification (opt-in diagnostics).
    final watch = Stopwatch()..start();
    var outcome = NotifyOutcome.failed;
    try {
      // Vommet: notification work (D-Bus on Linux) as a span of its own.
      outcome = await MainSpans.zone(
          "Notify",
          () => _notify(notification,
              forceShow: forceShow,
              onNotificationRejected: onNotificationRejected));
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
        if (modifier is NotificationModifierInAppBanner) continue;
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

enum _NotifiedRoom {
  /// Shown while the room counted nothing unread (e.g. a reaction).
  quiet,

  /// Sync has counted the room unread since.
  unread,

  /// Found on screen (another isolate or run): the next sync decides.
  recheck,
}
