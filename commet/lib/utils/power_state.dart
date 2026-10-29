import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/services.dart';

/// Vommet Deep Search: the device's battery state, for pausing background
/// work (the search index) on battery saver or a low battery. Android
/// (VommetPower.kt) and Linux laptops (/sys/class/power_supply); elsewhere
/// [read] returns null and nothing pauses.
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
    if (PlatformUtils.isLinux) return _readLinux();
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

  /// Linux: the first battery under /sys/class/power_supply. Desktops
  /// without a battery return null (never paused).
  static Future<PowerState?> _readLinux(
      {String root = "/sys/class/power_supply"}) async {
    try {
      final dir = Directory(root);
      if (!await dir.exists()) return null;
      await for (final entry in dir.list()) {
        Future<String?> read(String name) async {
          final f = File("${entry.path}/$name");
          if (!await f.exists()) return null;
          return (await f.readAsString()).trim();
        }

        if (await read("type") != "Battery") continue;
        final state = fromLinux(
            status: await read("status"), capacity: await read("capacity"));
        if (state != null) return state;
      }
    } catch (e) {
      Log.w("Power state unavailable: $e");
    }
    return null;
  }

  /// A battery's sysfs `status` and `capacity`; null when the capacity is
  /// missing (not a real battery reading).
  static PowerState? fromLinux({String? status, String? capacity}) {
    final percent = int.tryParse(capacity ?? "");
    if (percent == null) return null;
    // "Discharging" is the only state on battery; "Not charging" means
    // plugged in but held (charge limit).
    return PowerState(
        saver: false, percent: percent, charging: status != "Discharging");
  }
}
