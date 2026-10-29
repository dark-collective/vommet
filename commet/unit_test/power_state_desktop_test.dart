// Vommet issue 845: Deep Search pauses background indexing on a laptop's
// battery saver or low battery, like phones. A desktop without a battery
// (unknown state, often 0%) must never pause.

import 'package:battery_plus_platform_interface/battery_plus_platform_interface.dart';
import 'package:commet/utils/power_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBattery extends BatteryPlatform {
  _FakeBattery(this.state, this.level, {this.saver});

  final BatteryState state;
  final int level;

  /// Null: not available on this platform (Linux).
  final bool? saver;

  @override
  Future<BatteryState> get batteryState async => state;

  @override
  Future<int> get batteryLevel async => level;

  @override
  Future<bool> get isInBatterySaveMode async =>
      saver ?? (throw UnimplementedError());
}

Future<bool?> _lowPower(BatteryState state, int level, {bool? saver}) async {
  BatteryPlatform.instance = _FakeBattery(state, level, saver: saver);
  return (await PowerState.read())?.lowPower;
}

void main() {
  test("discharging below 20% pauses", () async {
    expect(await _lowPower(BatteryState.discharging, 15), isTrue);
  });

  test("discharging at 20% or more keeps going", () async {
    expect(await _lowPower(BatteryState.discharging, 20), isFalse);
    expect(await _lowPower(BatteryState.discharging, 80), isFalse);
  });

  test("charging, full or plugged in keeps going even when low", () async {
    expect(await _lowPower(BatteryState.charging, 5), isFalse);
    expect(await _lowPower(BatteryState.full, 5), isFalse);
    expect(await _lowPower(BatteryState.connectedNotCharging, 5), isFalse);
  });

  test("a desktop without a battery keeps going", () async {
    expect(await _lowPower(BatteryState.unknown, 0), isFalse);
  });

  test("battery saver pauses", () async {
    expect(await _lowPower(BatteryState.discharging, 90, saver: true), isTrue);
  });

  test("no battery saver API (Linux) still reads the level", () async {
    expect(await _lowPower(BatteryState.discharging, 10), isTrue);
    expect(await _lowPower(BatteryState.discharging, 60), isFalse);
  });
}
