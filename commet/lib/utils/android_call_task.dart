import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/hang_up_on_quit.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Vommet issue 285 (Android): hangs up when the app is swiped away from
/// recents during a call.
///
/// Only a service hears that its task was removed, so this keeps the native
/// CallTaskService (VommetCallTask.kt) started while there is a call, and
/// hangs up when it reports the swipe.
///
/// Vommet issue 855: the service is a foreground service (microphone, and
/// camera when allowed) with an ongoing call notification, so Android keeps
/// the mic and the network alive with the screen off or the app in the
/// background. Its "Hang up" action hangs up like the swipe does.
class AndroidCallTask {
  static const channel = MethodChannel("im.nether.vommet/call_task");

  static String get notificationTitleCallInProgress => Intl.message(
        "Call in progress",
        desc: "Title of the ongoing notification shown while a call is running",
        name: "notificationTitleCallInProgress",
      );

  static String get notificationChannelCalls => Intl.message(
        "Calls",
        desc: "Name of the Android notification channel for ongoing calls",
        name: "notificationChannelCalls",
      );

  static String get notificationActionHangUp => Intl.message(
        "Hang up",
        desc: "Button on the ongoing call notification that ends the call",
        name: "notificationActionHangUp",
      );

  static StreamSubscription? _subscription;
  static bool _running = false;

  static void attach(NotifyingList<VoipSession> sessions, {bool? android}) {
    if (!(android ?? PlatformUtils.isAndroid)) return;
    _subscription?.cancel();
    _running = false;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "taskRemoved":
          Log.i("Swiped away during a call");
        case "hangUp":
          Log.i("Hang up pressed on the call notification");
        default:
          return;
      }
      await hangUpCallsForQuit(sessions);
    });
    _subscription = sessions.onListUpdated.listen((_) {
      final want = sessions.isNotEmpty;
      if (want == _running) return;
      _running = want;
      final Future<Object?> request = want
          ? channel.invokeMethod("start", {
              "roomName": sessions.first.roomName,
              "title": notificationTitleCallInProgress,
              "channelName": notificationChannelCalls,
              "hangUp": notificationActionHangUp,
            })
          : channel.invokeMethod("stop");
      request.then((started) {
        if (started == false) {
          Log.w("Call task service could not start in the foreground");
        }
      }).catchError((Object e) {
        // No native side (a bubble's or a headless engine): nothing to watch.
        Log.w("Call task service not available: $e");
        return null;
      });
    });
  }
}
