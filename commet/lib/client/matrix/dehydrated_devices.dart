// Vommet issue 965: messages while signed out (MSC3814 dehydrated devices).
//
// A locked stand-in session kept on the server receives message keys while
// the user is signed out everywhere; signing back in with the recovery key
// opens it, reads what it received and puts a fresh one in its place. The
// SDK (ss.29.28) does the work and keeps it safe next to Element: a device
// Element keeps is left alone, an unsupported server gets nothing written,
// and an identity reset removes a device the new identity can't open
// (issue 964). Here: the per-account switch (default on), the runs on each
// recovery key entry, and the status for Settings › Security.

import 'dart:async';
import 'dart:convert';

import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;

/// What Settings › Security shows for the stand-in session.
enum StandInStatus {
  /// Ours is on the server.
  on,

  /// Another app (Element) keeps it; Vommet leaves it alone.
  otherApp,

  /// Turned off for this account.
  off,

  /// The server doesn't support it.
  serverCant,

  /// On, but not there yet: starts at the next recovery key entry.
  starting,

  /// The server couldn't be asked right now (network, rate limit, 5xx).
  unknown,
}

class DehydratedDevices {
  /// Accounts (user ids) that turned it off; on by default.
  static final StringListPreference _off =
      StringListPreference("vommet_dehydrated_devices_off", defaultValue: []);

  /// When ours was last put in place, per account: {user id: epoch ms}.
  static final StringPreference _refreshed = StringPreference(
      "vommet_dehydrated_devices_refreshed",
      defaultValue: "{}");

  static final StreamController<void> _refreshDone =
      StreamController<void>.broadcast();

  static Stream<void> get onChanged => _off.onChanged;

  /// A refresh finished: the status may differ.
  static Stream<void> get onRefreshed => _refreshDone.stream;

  static DateTime? lastRefreshed(matrix.Client client) {
    try {
      final ms = (jsonDecode(_refreshed.value) as Map)[client.userID];
      return ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _noteRefreshed(matrix.Client client) async {
    final userId = client.userID;
    if (userId == null) return;
    Map<String, Object?> all;
    try {
      all = Map<String, Object?>.from(jsonDecode(_refreshed.value) as Map);
    } catch (_) {
      all = {};
    }
    all[userId] = DateTime.now().millisecondsSinceEpoch;
    await _refreshed.set(jsonEncode(all));
  }

  static bool isOn(matrix.Client client) => !_off.value.contains(client.userID);

  /// Whether the SDK may create or refresh ours for [userId]: never before
  /// the account is known, so a turned-off switch holds from the start.
  static bool shouldEnable(String? userId) =>
      userId != null && !_off.value.contains(userId);

  /// Sets the SDK flags from the switch. The issue 964 cleanup after an
  /// identity reset runs whatever the switch says.
  static void apply(matrix.Client client) {
    client.enableDehydratedDevices = shouldEnable(client.userID);
    client.dehydratedDeviceResetCleanup = true;
  }

  /// Applies the switch now and again whenever the client logs in, since
  /// the user id isn't known when the client is created.
  static void watch(matrix.Client client) {
    apply(client);
    client.onLoginStateChanged.stream.listen((state) {
      if (state == matrix.LoginState.loggedIn) apply(client);
    });
  }

  /// The user entered their recovery key ([handle] is open): open the
  /// stand-in session, read what it received and put a fresh one in its
  /// place, or create the first one. Runs in the background and never fails
  /// what it rides on.
  static void refresh(matrix.Client client, OpenSSSS handle,
      {required String trigger}) {
    apply(client);
    if (!client.enableDehydratedDevices) {
      // Turned off, but removing ours may have failed then: try again.
      if (client.userID != null) {
        unawaited(() async {
          try {
            if (!await client.removeOwnDehydratedDevice()) {
              Log.w("Stand-in session ($trigger): couldn't remove ours yet");
            }
          } catch (e, s) {
            Log.onError(e, s, content: "Stand-in session ($trigger): off");
          }
        }());
      }
      return;
    }
    unawaited(() async {
      try {
        final result = await client.dehydratedDeviceSetup(handle);
        Log.i("Stand-in session ($trigger): ${result.name}");
        switch (result) {
          case matrix.DehydratedDeviceSetupResult.created:
          case matrix.DehydratedDeviceSetupResult.rehydrated:
          case matrix.DehydratedDeviceSetupResult.replaced:
          case matrix.DehydratedDeviceSetupResult.staleRemoved:
            await _noteRefreshed(client);
          default:
        }
      } catch (e, s) {
        Log.onError(e, s, content: "Stand-in session ($trigger)");
      }
      _refreshDone.add(null);
    }());
  }

  static Future<StandInStatus> status(matrix.Client client) async {
    if (!isOn(client)) return StandInStatus.off;
    switch (await client.dehydratedDeviceSlot()) {
      case matrix.DehydratedDeviceSlot.ours:
        return StandInStatus.on;
      case matrix.DehydratedDeviceSlot.foreign:
        return StandInStatus.otherApp;
      case matrix.DehydratedDeviceSlot.unsupported:
        return StandInStatus.serverCant;
      case matrix.DehydratedDeviceSlot.empty:
        return StandInStatus.starting;
      case matrix.DehydratedDeviceSlot.unknown:
        return StandInStatus.unknown;
    }
  }

  /// The switch. Turning it off removes our stand-in session from the
  /// server (never another app's); turning it on starts at the next
  /// recovery key entry. Returns false when ours couldn't be removed; the
  /// next recovery key entry tries again.
  static Future<bool> setOn(matrix.Client client, bool on) async {
    final userId = client.userID;
    if (userId == null) return false;
    final off = {..._off.value};
    if (on) {
      off.remove(userId);
    } else {
      off.add(userId);
    }
    await _off.set(off.toList());
    apply(client);
    if (on) return true;
    final removed = await client.removeOwnDehydratedDevice();
    if (!removed) Log.w("Stand-in session: couldn't remove ours yet");
    return removed;
  }
}
