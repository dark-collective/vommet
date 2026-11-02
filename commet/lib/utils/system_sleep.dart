import 'dart:async';

import 'package:commet/client/call_manager.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tells the app when the system is about to sleep and when it has woken up.
/// macOS: NSWorkspace notifications from the runner (MainFlutterWindow.swift).
/// Linux: logind's PrepareForSleep signal on the system bus.
class SystemSleep {
  static const _channel = MethodChannel("im.nether.chat/system_sleep");

  static final StreamController<void> _onWillSleep =
      StreamController.broadcast();
  static final StreamController<void> _onDidWake = StreamController.broadcast();

  static Stream<void> get onWillSleep => _onWillSleep.stream;
  static Stream<void> get onDidWake => _onDidWake.stream;

  static bool _started = false;

  static void init() {
    if (_started || kIsWeb) return;
    _started = true;

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case "willSleep":
            _onWillSleep.add(null);
          case "didWake":
            _onDidWake.add(null);
        }
      });
    } else if (PlatformUtils.isLinux) {
      _initLinux();
    }
  }

  static Future<void> _initLinux() async {
    try {
      var client = DBusClient.system();
      var signals = DBusSignalStream(client,
          sender: "org.freedesktop.login1",
          interface: "org.freedesktop.login1.Manager",
          name: "PrepareForSleep",
          signature: DBusSignature("b"));
      signals.listen((signal) {
        if (signal.values.first.asBoolean()) {
          _onWillSleep.add(null);
        } else {
          _onDidWake.add(null);
        }
      }, onError: (Object e) {
        Log.w("System sleep: logind signal error: $e");
      });
    } catch (e) {
      Log.w("System sleep: could not watch logind: $e");
    }
  }

  /// Vommet issue 598: leave every active call when the system goes to sleep,
  /// so others don't see a participant who isn't there. Runs again on wake to
  /// end any call whose hang-up didn't get out before the system slept.
  static void leaveCallsOnSleep(CallManager callManager) {
    onWillSleep.listen((_) => leaveCalls(callManager));
    onDidWake.listen((_) => leaveCalls(callManager));
  }

  static Future<void> leaveCalls(CallManager callManager) async {
    var sessions = callManager.currentSessions
        .where((e) => e.state != VoipState.incoming)
        .toList();
    if (sessions.isEmpty) return;

    Log.i("System sleep: leaving ${sessions.length} call(s)");
    await Future.wait(sessions.map((session) => session
            .hangUpCall()
            .timeout(const Duration(seconds: 5))
            .catchError((Object e) {
          Log.w("System sleep: hanging up ${session.sessionId} failed: $e");
        })));
  }
}
