import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/services.dart';

/// Vommet Deep Search: the device's power state, for pausing background
/// work (the search index) on battery saver or a low battery. Android reads
/// VommetPower.kt; Linux reads /sys/class/power_supply. Elsewhere [read]
/// returns null and nothing pauses.
class PowerState {
  const PowerState(
      {required this.saver, required this.percent, required this.charging});

  final bool saver;

  /// 0–100, or -1 when unknown.
  final int percent;
  final bool charging;

  static const _channel = MethodChannel("im.nether.vommet/power");

  static const _sysfsRoot = "/sys/class/power_supply";

  static bool get supported => PlatformUtils.isAndroid || PlatformUtils.isLinux;

  /// Battery saver is on, or the battery is below 20% and not charging.
  bool get lowPower => saver || (!charging && percent >= 0 && percent < 20);

  static Future<PowerState?> read() async {
    if (PlatformUtils.isAndroid) return _readAndroid();
    if (PlatformUtils.isLinux) return _readLinux();
    return null;
  }

  static Future<PowerState?> _readLinux() async {
    try {
      final root = Directory(_sysfsRoot);
      if (!await root.exists()) return null;
      String? battery;
      var mainsOnline = false;
      await for (final entry in root.list()) {
        final type = await _readSysfs(entry.path, "type");
        if (type == "Battery") battery ??= entry.path;
        if (type == "Mains" && await _readSysfs(entry.path, "online") == "1") {
          mainsOnline = true;
        }
      }
      if (battery == null) return null;
      final status = await _readSysfs(battery, "status");
      final percent =
          int.tryParse(await _readSysfs(battery, "capacity") ?? "") ?? -1;
      return PowerState(
        saver: false,
        percent: percent,
        charging: mainsOnline || status == "Charging" || status == "Full",
      );
    } catch (e) {
      Log.w("Power state unavailable: $e");
      return null;
    }
  }

  static Future<String?> _readSysfs(String dir, String name) async {
    try {
      return (await File("$dir/$name").readAsString()).trim();
    } catch (_) {
      return null;
    }
  }

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
}
