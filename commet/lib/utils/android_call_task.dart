import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/hang_up_on_quit.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/services.dart';

/// Vommet issue 285 (Android): hangs up when the app is swiped away from
/// recents during a call.
///
/// Only a service hears that its task was removed, so this keeps the native
/// CallTaskService (VommetCallTask.kt) started while there is a call, and
/// hangs up when it reports the swipe.
class AndroidCallTask {
  static const channel = MethodChannel("im.nether.vommet/call_task");

  static StreamSubscription? _subscription;
  static bool _running = false;

  static void attach(NotifyingList<VoipSession> sessions, {bool? android}) {
    if (!(android ?? PlatformUtils.isAndroid)) return;
    _subscription?.cancel();
    _running = false;
    channel.setMethodCallHandler((call) async {
      if (call.method != "taskRemoved") return;
      Log.i("Swiped away during a call");
      await hangUpCallsForQuit(sessions);
    });
    _subscription = sessions.onListUpdated.listen((_) {
      final want = sessions.isNotEmpty;
      if (want == _running) return;
      _running = want;
      channel.invokeMethod(want ? "start" : "stop").catchError((Object e) {
        // No native side (a bubble's or a headless engine): nothing to watch.
        Log.w("Call task service not available: $e");
        return null;
      });
    });
  }
}
