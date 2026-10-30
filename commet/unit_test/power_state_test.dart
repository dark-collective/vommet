import 'package:commet/utils/power_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, String> battery(String capacity,
          {String status = "Discharging", String? scope}) =>
      {
        "type": "Battery",
        "status": status,
        "capacity": capacity,
        if (scope != null) "scope": scope,
      };
  Map<String, String> ac(bool online, {String type = "Mains"}) =>
      {"type": type, "online": online ? "1" : "0"};

  test("Linux battery: low and discharging pauses", () {
    expect(PowerState.fromLinux([battery("19"), ac(false)])!.lowPower, isTrue);
    expect(PowerState.fromLinux([battery("20"), ac(false)])!.lowPower, isFalse);
  });

  test("Linux battery: plugged in never pauses", () {
    expect(PowerState.fromLinux([battery("5"), ac(true)])!.lowPower, isFalse);
    expect(
        PowerState.fromLinux([battery("5"), ac(false), ac(true, type: "USB")])!
            .lowPower,
        isFalse);
  });

  test("Linux battery: without an adapter entry the status decides", () {
    for (final status in ["Charging", "Not charging", "Full", "Unknown"]) {
      expect(PowerState.fromLinux([battery("5", status: status)])!.lowPower,
          isFalse,
          reason: status);
    }
    expect(PowerState.fromLinux([battery("5")])!.charging, isFalse);
  });

  test("Linux battery: a low mouse or headset battery is ignored", () {
    final mouse = battery("3", scope: "Device");
    expect(PowerState.fromLinux([mouse]), isNull);
    expect(PowerState.fromLinux([mouse, ac(true)]), isNull);
    final laptop = PowerState.fromLinux(
        [mouse, battery("80", scope: "System"), ac(false)])!;
    expect(laptop.percent, 80);
    expect(laptop.lowPower, isFalse);
  });

  test("Linux battery: two system batteries are averaged", () {
    expect(
        PowerState.fromLinux([battery("10"), battery("30"), ac(false)])!
            .percent,
        20);
  });

  test("Linux battery: no capacity is no reading", () {
    expect(PowerState.fromLinux([battery("x"), ac(false)]), isNull);
    expect(PowerState.fromLinux([ac(true)]), isNull);
    expect(PowerState.fromLinux([]), isNull);
  });

  test("Pause on battery power: pauses whenever unplugged", () {
    final unplugged = PowerState.fromLinux([battery("90"), ac(false)])!;
    final plugged = PowerState.fromLinux([battery("90"), ac(true)])!;
    expect(unplugged.shouldPause(pauseOnBattery: true), isTrue);
    expect(unplugged.shouldPause(pauseOnBattery: false), isFalse);
    expect(plugged.shouldPause(pauseOnBattery: true), isFalse);
    final low = PowerState.fromLinux([battery("10"), ac(false)])!;
    expect(low.shouldPause(pauseOnBattery: false), isTrue);
  });

  test("Windows battery", () {
    // No system battery (desktop) or unknown: no reading.
    expect(PowerState.fromWindows(ac: 1, flag: 128, percent: 255, saver: 0),
        isNull);
    expect(PowerState.fromWindows(ac: 1, flag: 255, percent: 255, saver: 0),
        isNull);
    final onBattery =
        PowerState.fromWindows(ac: 0, flag: 1, percent: 80, saver: 0)!;
    expect(onBattery.charging, isFalse);
    expect(onBattery.shouldPause(pauseOnBattery: true), isTrue);
    expect(onBattery.lowPower, isFalse);
    expect(
        PowerState.fromWindows(ac: 0, flag: 2, percent: 15, saver: 0)!.lowPower,
        isTrue);
    expect(PowerState.fromWindows(ac: 1, flag: 8, percent: 50, saver: 1)!.saver,
        isTrue);
    // Unknown AC state counts as plugged in; unknown percent is -1.
    final unknown =
        PowerState.fromWindows(ac: 255, flag: 0, percent: 255, saver: 0)!;
    expect(unknown.charging, isTrue);
    expect(unknown.percent, -1);
  });
}
