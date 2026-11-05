// Microphone capture regression test (#78), desktop platforms. Needs a fed
// virtual microphone: .vommet/it/capture-linux.sh or capture-windows.ps1.

import 'package:commet/main.dart';
import 'package:integration_test/integration_test.dart';
import 'smoke/capture_loopback_test.dart' as capture_test;

void main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await preferences.init();

  capture_test.main();
}
