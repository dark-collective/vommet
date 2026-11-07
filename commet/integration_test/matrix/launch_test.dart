// Vommet: launch the app the way main() does. The other tests build App
// themselves (setupApp), so startGui() ran under no test at all, and a
// startup crash there shipped (testing.859).
import 'package:commet/main.dart';
import 'package:commet/ui/pages/fatal_error/fatal_error_page.dart';
import 'package:commet/utils/first_time_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches through startGui', (WidgetTester tester) async {
    await tester.clearUserData();
    addTearDown(() async {
      // startGui() registers post-login setup screens (welcome, telemetry
      // consent, ...) process-wide; left in, the later tests' logins would
      // land on them instead of the home screen.
      FirstTimeSetup.postLogin.clear();
      // initNecessary() starts fileCache.clean() without awaiting it; this
      // test is quick enough to close the cache under it otherwise.
      await Future.delayed(const Duration(seconds: 3));
      await clientManager?.close();
      await tester.clean();
    });

    await initNecessary();
    // Throws out of the test if anything on the startup path does.
    await startGui();

    await tester.waitFor(() => find.byType(App).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30));
    expect(find.byType(FatalErrorPage), findsNothing);
  });
}
