import 'package:commet/utils/power_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('low power when saver is on, or below 20% and not charging', () {
    PowerState state(
            {bool saver = false, int percent = 50, bool charging = false}) =>
        PowerState(saver: saver, percent: percent, charging: charging);

    expect(state(saver: true).lowPower, isTrue);
    expect(state(percent: 19).lowPower, isTrue);
    expect(state(percent: 19, charging: true).lowPower, isFalse);
    expect(state(percent: 20).lowPower, isFalse);
    expect(state(percent: -1).lowPower, isFalse);
  });
}
