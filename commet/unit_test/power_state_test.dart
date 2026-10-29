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
}
