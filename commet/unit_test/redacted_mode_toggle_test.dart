import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redacted_mode_pill.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/utils/redaction/redaction_preferences.dart';
import 'package:commet/utils/redaction/redaction_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 474: redacted mode's quick toggle and its "Redacted" pill.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> load({required bool experiment, required bool enabled}) async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.experimentRedactedMode.set(experiment);
    await preferences.redactionEnabled.set(enabled);
  }

  Widget app() => const GlobalRedactionScope(
        child: MaterialApp(
          home: Scaffold(body: Center(child: RedactedModePill())),
        ),
      );

  testWidgets('the pill shows only while redacted mode is on', (tester) async {
    await tester.runAsync(() => load(experiment: true, enabled: false));
    await tester.pumpWidget(app());
    expect(find.text(redactedModeIndicator), findsNothing);

    await tester.runAsync(() => setRedactedMode(null, true));
    await tester.pump();
    expect(find.text(redactedModeIndicator), findsOneWidget);
  });

  testWidgets('tapping the pill turns redacted mode off', (tester) async {
    await tester.runAsync(() => load(experiment: true, enabled: true));
    await tester.pumpWidget(app());
    expect(find.text(redactedModeIndicator), findsOneWidget);

    await tester.tap(find.text(redactedModeIndicator));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(preferences.redactionEnabled.value, isFalse);
    expect(find.text(redactedModeIndicator), findsNothing);
    expect(find.text(redactedModeTurnedOff), findsOneWidget);
  });

  testWidgets('without the experiment the toggle does nothing', (tester) async {
    await tester.runAsync(() => load(experiment: false, enabled: false));
    await toggleRedactedMode(null);
    expect(preferences.redactionEnabled.value, isFalse);
    expect(preferences.redactionActive, isFalse);
  });
}
