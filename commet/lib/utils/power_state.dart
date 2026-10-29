import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/services.dart';

/// Vommet Deep Search: the device's battery state, for pausing background
/// work (the search index) on battery saver or a low battery. Android uses
/// VommetPower.kt; Windows, macOS and Linux use battery_plus (desktops
/// without a battery report none, so nothing pauses). Elsewhere [read]
/// returns null.
class PowerState {
  const PowerState(
      {required this.saver, required this.percent, required this.charging});

  final bool saver;

  /// 0–100, or -1 when unknown.
  final int percent;
  final bool charging;

  static const _channel = MethodChannel("im.nether.vommet/power");

  /// Battery saver is on, or the battery is below 20% and not charging.
  bool get lowPower => saver || (!charging && percent >= 0 && percent < 20);

  static Future<PowerState?> read() async {
    if (PlatformUtils.isLinux ||
        PlatformUtils.isWindows ||
        (!PlatformUtils.isWeb && Platform.isMacOS)) {
      return _readDesktop();
    }
    if (!PlatformUtils.isAndroid) return null;
    try {
      final map = await _channel.invokeMapMethod<String, Object?>("state");
      if (map == null) return null;
      return PowerState(
        saver: map["saver"] == true,
        percent: map["percent"] is int ? map["percent"] as int : -1,
        charging: map["charging"] == true,
      );
    } catch (e) {
      Log.w("Power state unavailable: $e");
      return null;
    }
  }

  static Future<PowerState?> _readDesktop() async {
    try {
      final battery = Battery();
      final percent = await battery.batteryLevel;
      final status = await battery.batteryState;
      bool saver = false;
      try {
        saver = await battery.isInBatterySaveMode;
      } catch (_) {
        // Not reported on every desktop; the percentage rule still applies.
      }
      return PowerState(
        saver: saver,
        percent: percent,
        charging: status == BatteryState.charging ||
            status == BatteryState.full ||
            status == BatteryState.connectedNotCharging,
      );
    } catch (e) {
      // No battery (desktop PC) or no power service: don't pause.
      Log.w("Power state unavailable: $e");
      return null;
    }
  }
}
