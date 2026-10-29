import 'package:commet/utils/power_state.dart';
import 'package:test/test.dart';

void main() {
  group("Linux", () {
    test("no battery (desktop PC) never pauses", () {
      expect(PowerState.linuxState([], mains: true), isNull);
    });

    test("low and discharging pauses", () {
      final s = PowerState.linuxState([(percent: 15, status: "Discharging")],
          mains: false);
      expect(s!.lowPower, isTrue);
    });

    test("low but plugged in doesn't pause", () {
      expect(
          PowerState.linuxState([(percent: 15, status: "Charging")],
                  mains: true)!
              .lowPower,
          isFalse);
      expect(
          PowerState.linuxState([(percent: 15, status: "Not charging")],
                  mains: false)!
              .lowPower,
          isFalse);
    });

    test("the lowest of two batteries counts", () {
      final s = PowerState.linuxState([
        (percent: 80, status: "Discharging"),
        (percent: 10, status: "Discharging"),
      ], mains: false);
      expect(s!.percent, 10);
      expect(s.lowPower, isTrue);
    });

    test("above 20% doesn't pause", () {
      expect(
          PowerState.linuxState([(percent: 50, status: "Discharging")],
                  mains: false)!
              .lowPower,
          isFalse);
    });
  });

  group("macOS", () {
    test("low on battery power pauses", () {
      final s = PowerState.macOSState(
          "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1234)\t"
          "15%; discharging; 0:45 remaining present: true\n");
      expect(s!.percent, 15);
      expect(s.lowPower, isTrue);
    });

    test("low on AC power doesn't pause", () {
      final s = PowerState.macOSState(
          "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1234)\t"
          "15%; charging; 1:10 remaining present: true\n");
      expect(s!.lowPower, isFalse);
    });

    test("no internal battery (desktop Mac) never pauses", () {
      expect(PowerState.macOSState("Now drawing from 'AC Power'\n"), isNull);
    });
  });
}
