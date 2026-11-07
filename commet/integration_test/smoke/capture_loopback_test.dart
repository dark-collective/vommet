// Vommet: microphone capture regression test (#78), no homeserver needed.
// The check itself is in capture_check.dart (shared with capture_probe.dart).
//
// Runs only with --dart-define=CAPTURE_TEST=true (it needs a fed virtual
// microphone: .vommet/it/capture-linux.sh).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'capture_check.dart';

const _enabled = bool.fromEnvironment('CAPTURE_TEST');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('microphone capture carries the fed signal', (tester) async {
    final failure = await runCaptureCheck();
    expect(failure, isNull, reason: failure);
  }, skip: !_enabled);
}
