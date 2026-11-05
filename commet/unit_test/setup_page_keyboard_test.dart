import 'package:commet/main.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/setup/menus/telemetry_consent.dart';
import 'package:commet/ui/pages/setup/setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

void main() {
  testWidgets('first-run diagnostics keeps the tag and Next above the keyboard',
      (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Builder(builder: (context) {
        return TextButton(
          onPressed: () => NavigationUtils.navigateTo(
            context,
            SetupPage([TelemetryConsentSetup()]),
          ),
          child: const Text('Open'),
        );
      }),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final yes = find.text(telemetryConsentYes);
    await tester.ensureVisible(yes);
    await tester.pumpAndSettle();
    await tester.tap(yes);
    await tester.pumpAndSettle();

    final tag = find.byType(TextField);
    await tester.ensureVisible(tag);
    await tester.pumpAndSettle();
    await tester.enterText(tag, 'MOSSFERN');
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();

    await tester.ensureVisible(tag);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final next = find.text('Next');
    expect(tester.getBottomRight(tag).dy, lessThanOrEqualTo(380));
    expect(tester.getBottomRight(next).dy, lessThanOrEqualTo(380));
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(preferences.telemetryTag.value, 'MOSSFERN');
  });
}
