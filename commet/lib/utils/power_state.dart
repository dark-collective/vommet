import 'dart:ffi';
import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// Vommet Deep Search: the device's battery state, for pausing background
/// work (the search index) on battery saver or a low battery. Android via
/// VommetPower.kt; Linux from /sys/class/power_supply (also in the Flatpak),
/// Windows from GetSystemPowerStatus, macOS from `pmset -g batt`. Elsewhere,
/// or without a battery, [read] returns null and nothing pauses.
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
    try {
      if (PlatformUtils.isAndroid) return await _readAndroid();
      if (PlatformUtils.isLinux) return await _readLinux();
      if (PlatformUtils.isWindows) return _readWindows();
      if (!PlatformUtils.isWeb && Platform.isMacOS) return await _readMacOS();
      return null;
    } catch (e) {
      Log.w("Power state unavailable: $e");
      return null;
    }
  }

  static Future<PowerState?> _readAndroid() async {
    final map = await _channel.invokeMapMethod<String, Object?>("state");
    if (map == null) return null;
    return PowerState(
      saver: map["saver"] == true,
      percent: map["percent"] is int ? map["percent"] as int : -1,
      charging: map["charging"] == true,
    );
  }

  static Future<PowerState?> _readLinux() async {
    final dir = Directory("/sys/class/power_supply");
    if (!await dir.exists()) return null;
    final batteries = <({int percent, String status})>[];
    var mains = false;
    await for (final entry in dir.list()) {
      Future<String?> attr(String name) async {
        final file = File("${entry.path}/$name");
        if (!await file.exists()) return null;
        return (await file.readAsString()).trim();
      }

      final type = await attr("type");
      if (type == "Mains" && await attr("online") == "1") mains = true;
      // Peripherals (mice, headsets) report scope "Device".
      if (type != "Battery" || await attr("scope") == "Device") continue;
      final capacity = int.tryParse(await attr("capacity") ?? "");
      batteries
          .add((percent: capacity ?? -1, status: await attr("status") ?? ""));
    }
    return linuxState(batteries, mains: mains);
  }

  /// Combines the laptop's batteries (lowest level counts); "Discharging"
  /// on any of them means on battery unless the charger is plugged in.
  static PowerState? linuxState(List<({int percent, String status})> batteries,
      {required bool mains}) {
    if (batteries.isEmpty) return null;
    final discharging = batteries.any((b) => b.status == "Discharging");
    final known = batteries.where((b) => b.percent >= 0).map((b) => b.percent);
    return PowerState(
      saver: false,
      percent: known.isEmpty ? -1 : known.reduce((a, b) => a < b ? a : b),
      charging: mains || !discharging,
    );
  }

  static PowerState? _readWindows() {
    final status = calloc<_SystemPowerStatus>();
    try {
      final getStatus = DynamicLibrary.open("kernel32.dll").lookupFunction<
          Int32 Function(Pointer<_SystemPowerStatus>),
          int Function(Pointer<_SystemPowerStatus>)>("GetSystemPowerStatus");
      if (getStatus(status) == 0) return null;
      final s = status.ref;
      // BatteryFlag 128: no system battery (desktop PC).
      if (s.batteryFlag == 128) return null;
      return PowerState(
        saver: s.systemStatusFlag == 1,
        percent: s.batteryLifePercent == 255 ? -1 : s.batteryLifePercent,
        charging: s.acLineStatus == 1,
      );
    } finally {
      calloc.free(status);
    }
  }

  static Future<PowerState?> _readMacOS() async {
    final result = await Process.run("/usr/bin/pmset", ["-g", "batt"]);
    if (result.exitCode != 0) return null;
    return macOSState(result.stdout as String);
  }

  /// Parses `pmset -g batt`, e.g. "Now drawing from 'Battery Power'
  /// -InternalBattery-0 (id=…)	15%; discharging; 0:45 remaining".
  static PowerState? macOSState(String output) {
    final match = RegExp(r"InternalBattery[^\t]*\t(\d+)%").firstMatch(output);
    if (match == null) return null;
    return PowerState(
      saver: false,
      percent: int.parse(match.group(1)!),
      charging: !output.contains("'Battery Power'"),
    );
  }
}

/// SYSTEM_POWER_STATUS (winbase.h).
final class _SystemPowerStatus extends Struct {
  @Uint8()
  external int acLineStatus;
  @Uint8()
  external int batteryFlag;
  @Uint8()
  external int batteryLifePercent;
  @Uint8()
  external int systemStatusFlag;
  @Uint32()
  external int batteryLifeTime;
  @Uint32()
  external int batteryFullLifeTime;
}
