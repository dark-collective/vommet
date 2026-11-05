// Vommet: opt-in diagnostics event "notify_setup", once per account per
// session, that says whether notifications can work at all: which notifier is active, whether it
// has permission, whether a push distributor/endpoint and a pusher on the
// homeserver exist, whether the account mutes everything, and how many rooms
// are unread, muted or mentions-only. Only booleans and counts: never the
// endpoint, push key, gateway, room or account.

import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/push_notification/notifier.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/notify_counts.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:unifiedpush/unifiedpush.dart';

class NotifySetupTelemetry {
  static bool _done = false;

  /// One of the schema's `notifier` values.
  static String notifierKind(Notifier? notifier) {
    if (notifier == null) return "none";
    return switch (notifier.runtimeType.toString()) {
      "UnifiedPushNotifier" => "unifiedpush",
      "FirebasePushNotifier" => "firebase",
      "AndroidNotifier" => "android_local",
      "LinuxNotifier" => "linux",
      "WindowsNotifier" => "windows",
      _ => "other",
    };
  }

  /// Unread / muted / mentions-only counts over [rooms].
  static Map<String, int> roomCounts(Iterable<Room> rooms) {
    var unread = 0, muted = 0, mentions = 0, total = 0;
    for (final room in rooms) {
      total++;
      if (room.displayNotificationCount > 0 ||
          room.displayHighlightedNotificationCount > 0) {
        unread++;
      }
      switch (room.pushRule) {
        case PushRule.dontNotify:
          muted++;
        case PushRule.mentionsOnly:
          mentions++;
        case PushRule.notify:
          break;
      }
    }
    return {
      "rooms": total,
      "rooms_unread": unread,
      "rooms_muted": muted,
      "rooms_mentions": mentions,
    };
  }

  static Future<void> record(ClientManager manager) async {
    if (_done || !Telemetry.enabled) return;
    _done = true;

    final notifier = NotificationManager.notifier;
    final common = <String, Object?>{
      "notifier": notifierKind(notifier),
      if (notifier != null) "permission": notifier.hasPermission,
      if (notifier != null) "enabled": notifier.enabled,
    };

    if (notifier is UnifiedPushNotifier) {
      common["up_endpoint"] = notifier.endpoint != null;
      try {
        common["up_distributor"] = await UnifiedPush.getDistributor() != null;
      } catch (_) {}
    }

    // Vommet (schema v9): one event per account, numbered by position in the
    // account list (never which account), so a problem with the second
    // account shows up too.
    final accounts = manager.clients.whereType<MatrixClient>().toList();
    for (final (index, matrix) in accounts.indexed) {
      final fields = <String, Object?>{
        ...common,
        "account_index": index,
        "accounts": accounts.length,
        ...roomCounts(matrix.rooms),
      };
      final mx = matrix.getMatrixClient();
      fields["master_muted"] = mx.allPushNotificationsMuted;
      Object? error;
      try {
        final pushers = await mx.getPushers() ?? const [];
        fields["pushers"] = pushers.length;
        final pushKey = BuildConfig.ENABLE_GOOGLE_SERVICES
            ? preferences.fcmKey.value
            : preferences.unifiedPushEndpoint.value;
        if (pushKey != null) {
          fields["own_pusher"] = pushers.any((p) => p.pushkey == pushKey);
        }
      } catch (e) {
        error = e;
      }
      Telemetry.record("notify_setup", {
        ...fields,
        ...Telemetry.errorFields(error, withType: false),
      });
    }
    if (accounts.isEmpty) {
      Telemetry.record("notify_setup", {
        ...common,
        "accounts": 0,
        ...roomCounts(manager.rooms),
        ...Telemetry.errorFields(null, withType: false),
      });
    }

    // What happened to notifications since the last report.
    await NotifyCounts.report();
  }
}
