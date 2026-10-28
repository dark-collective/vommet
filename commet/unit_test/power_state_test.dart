import 'package:commet/utils/power_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("Linux battery: low and discharging pauses", () {
    expect(
        PowerState.fromLinux(status: "Discharging", capacity: "19")!.lowPower,
        isTrue);
    expect(
        PowerState.fromLinux(status: "Discharging", capacity: "20")!.lowPower,
        isFalse);
  });

  test("Linux battery: plugged in never pauses", () {
    for (final status in ["Charging", "Not charging", "Full", "Unknown"]) {
      expect(PowerState.fromLinux(status: status, capacity: "5")!.lowPower,
          isFalse,
          reason: status);
    }
  });

  test("Linux battery: no capacity is no reading", () {
    expect(PowerState.fromLinux(status: "Discharging", capacity: null), isNull);
    expect(PowerState.fromLinux(status: "Discharging", capacity: "x"), isNull);
  });
}
