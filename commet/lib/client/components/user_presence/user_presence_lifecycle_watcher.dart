import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:flutter/widgets.dart';

class UserPresenceLifecycleWatcher {
  static final UserPresenceLifecycleWatcher _singleton =
      UserPresenceLifecycleWatcher._internal();

  UserPresenceLifecycleWatcher._internal();

  factory UserPresenceLifecycleWatcher() {
    return _singleton;
  }

  bool isInit = false;
  DateTime? lastUpdatedStatus = null;
  Timer? inactivityTimer;

  void init() {
    if (!isInit) {
      AppLifecycleListener(
        onResume: () {
          inactivityTimer?.cancel();
          inactivityTimer = null;
          setState(UserPresenceStatus.online);
        },
        onInactive: () {
          inactivityTimer = Timer(Duration(seconds: 15), () {
            setState(UserPresenceStatus.unavailable);
          });
        },
      );
    }

    isInit = true;
  }

  Future<void> setState(UserPresenceStatus state) async {
    final now = DateTime.now();

    if (lastUpdatedStatus != null) {
      if (now.difference(lastUpdatedStatus!).inSeconds < 10) {
        return;
      }
    }

    lastUpdatedStatus = now;

    if (clientManager != null) {
      await setStatusForClients(clientManager!.clients, state);
    }
  }

  /// Vommet: skips accounts that aren't signed in (failed to load, mid sign-in
  /// or sign-out) and logs a failure instead of leaving it unhandled. Both
  /// used to surface as an uncaught "Null check operator" crash from
  /// `getPresence` whenever the app went to the background or came back.
  static Future<void> setStatusForClients(
      Iterable<Client> clients, UserPresenceStatus state) async {
    await Future.wait(clients.toList().map((client) async {
      try {
        if (!client.isLoggedIn()) return;
        await client.getComponent<UserPresenceComponent>()?.setStatus(state);
      } catch (e, s) {
        Log.onError(e, s,
            content: "Setting presence to ${state.name} failed for an account");
      }
    }));
  }
}
