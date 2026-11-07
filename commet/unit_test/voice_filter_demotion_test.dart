// The voice filter stats line (logged by the capture check and copied into
// bug reports) says why the filter fell back to RNNoise: the Windows silence
// watchdog's "(silent output)" must not be confused with the speed fallback.
import 'package:commet/client/components/voip/voice_filter_demotion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("not demoted: no reason", () {
    expect(describeDemotion(false, 0), "demoted=false");
  });

  test("too slow", () {
    expect(describeDemotion(true, 1), "demoted=true (too slow)");
  });

  test("silent output only for reason 2", () {
    expect(describeDemotion(true, 2), "demoted=true (silent output)");
    expect(describeDemotion(true, 1), isNot(contains("silent output")));
  });
}
