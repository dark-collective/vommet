import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/services.dart';

import 'power_state_windows_stub.dart'
    if (dart.library.io) 'power_state_windows.dart';

/// Vommet Deep Search: the device's battery state, for pausing background
/// work (the search index) on battery power, battery saver or a low battery.
/// Android (VommetPower.kt), Linux (/sys/class/power_supply) and Windows
/// (GetSystemPowerStatus); elsewhere, and on devices without a battery,
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

  /// [lowPower], or running on battery while [pauseOnBattery] is set
  /// (Settings › Privacy › Search › "Pause on battery power").
  bool shouldPause({required bool pauseOnBattery}) =>
      lowPower || (pauseOnBattery && !charging);

  static Future<PowerState?> read() async {
    if (PlatformUtils.isLinux) return _readLinux();
    if (PlatformUtils.isWindows) {
      try {
        final s = readWindowsPowerStatus();
        return s == null
            ? null
            : fromWindows(
                ac: s.ac, flag: s.flag, percent: s.percent, saver: s.saver);
      } catch (e) {
        Log.w("Power state unavailable: $e");
        return null;
      }
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

  /// Linux: the laptop's own batteries under /sys/class/power_supply.
  /// Desktops without a system battery return null (never paused).
  static Future<PowerState?> _readLinux(
      {String root = "/sys/class/power_supply"}) async {
    try {
      final dir = Directory(root);
      if (!await dir.exists()) return null;
      final supplies = <Map<String, String>>[];
      await for (final entry in dir.list()) {
        final attrs = <String, String>{};
        for (final name in _linuxAttrs) {
          final f = File("${entry.path}/$name");
          if (await f.exists()) attrs[name] = (await f.readAsString()).trim();
        }
        supplies.add(attrs);
      }
      return fromLinux(supplies);
    } catch (e) {
      Log.w("Power state unavailable: $e");
    }
    return null;
  }

  static const _linuxAttrs = ["type", "scope", "status", "capacity", "online"];

  /// The sysfs attributes of every power supply (`type`, `scope`, `status`,
  /// `capacity`, `online`). Only system batteries count: a wireless mouse or
  /// headset reports `scope=Device` and is ignored. On battery means no AC
  /// adapter or USB-C charger is online; without any adapter entry, a
  /// battery's "Discharging" status decides. Null when there's no system
  /// battery with a capacity.
  static PowerState? fromLinux(List<Map<String, String>> supplies) {
    bool system(Map<String, String> s) =>
        s["scope"] == null || s["scope"] == "System";
    final batteries = supplies
        .where((s) => s["type"] == "Battery" && system(s))
        .map((s) =>
            (status: s["status"], percent: int.tryParse(s["capacity"] ?? "")))
        .where((b) => b.percent != null)
        .toList();
    if (batteries.isEmpty) return null;
    final adapters =
        supplies.where((s) => s["type"] != "Battery" && system(s)).toList();
    final bool charging;
    if (adapters.any((s) => s.containsKey("online"))) {
      charging = adapters.any((s) => s["online"] == "1");
    } else {
      // "Not charging" means plugged in but held (charge limit).
      charging = batteries.every((b) => b.status != "Discharging");
    }
    final percent = batteries.fold<int>(0, (sum, b) => sum + b.percent!) ~/
        batteries.length;
    return PowerState(saver: false, percent: percent, charging: charging);
  }

  /// SYSTEM_POWER_STATUS: `ACLineStatus` (0 offline, 1 online, 255 unknown),
  /// `BatteryFlag` (128 no system battery, 255 unknown), `BatteryLifePercent`
  /// (255 unknown), `SystemStatusFlag` (1 battery saver on). Null without a
  /// known system battery; an unknown AC state counts as plugged in.
  static PowerState? fromWindows(
      {required int ac,
      required int flag,
      required int percent,
      required int saver}) {
    if (flag == 255 || flag & 128 != 0) return null;
    return PowerState(
        saver: saver & 1 != 0,
        percent: percent > 100 ? -1 : percent,
        charging: ac != 0);
  }
}
