import 'package:battery_plus/battery_plus.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/services.dart';

/// Vommet Deep Search: the device's battery state, for pausing background
/// work (the search index) on battery saver or a low battery. Android reads
/// it through VommetPower.kt; laptops (Linux, Windows, macOS) through
/// battery_plus. Elsewhere [read] returns null and nothing pauses.
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
    if (PlatformUtils.isAndroid) return _readAndroid();
    if (PlatformUtils.isWeb || PlatformUtils.isIOS) return null;
    return _readDesktop();
  }

  static bool _desktopWarned = false;

  static Future<PowerState?> _readAndroid() async {
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

  /// Desktops without a battery report an unknown state (and often 0%), so
  /// only a battery that is actually discharging counts as "not charging".
  /// Each value is read on its own: battery saver isn't available on every
  /// platform (Linux) and must not hide the level.
  static Future<PowerState?> _readDesktop() async {
    final battery = Battery();
    BatteryState state;
    try {
      state = await battery.batteryState;
    } catch (e) {
      // Checked every 2 minutes: say it once.
      if (!_desktopWarned) Log.w("Battery state unavailable: $e");
      _desktopWarned = true;
      return null;
    }
    var percent = -1;
    if (state == BatteryState.discharging) {
      try {
        percent = await battery.batteryLevel;
      } catch (_) {}
    }
    var saver = false;
    try {
      saver = await battery.isInBatterySaveMode;
    } catch (_) {}
    return PowerState(
      saver: saver,
      percent: percent,
      charging: state != BatteryState.discharging,
    );
  }
}
