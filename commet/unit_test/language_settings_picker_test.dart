// Vommet issue 751: Settings › General shows the app language as one row
// that opens the full list in a picker; onboarding keeps the inline list.
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/language_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

void main() {
  setUp(() async {
    // Debug translations make a pick skip the live switch (restart path).
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(
        {"vommet_app_language": "de", "enable_translations_debug": true});
    Preference.preferences = await SharedPreferences.getInstance();
  });

  Future<void> pump(WidgetTester tester, {required bool collapsed}) {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: SingleChildScrollView(
            child: LanguageSettingsPanel(collapsed: collapsed)),
      ),
    ));
  }

  testWidgets('collapsed: one row with the chosen language', (tester) async {
    await pump(tester, collapsed: true);
    expect(find.byKey(const ValueKey("language-settings-current")),
        findsOneWidget);
    expect(find.text("Deutsch"), findsOneWidget);
    expect(find.text("System default"), findsNothing);
    expect(find.text("Español"), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('inline (onboarding): the full list', (tester) async {
    await pump(tester, collapsed: false);
    expect(
        find.byKey(const ValueKey("language-settings-current")), findsNothing);
    expect(find.text("System default"), findsOneWidget);
    expect(find.text("Español"), findsOneWidget);
  });

  testWidgets('the picker searches and applies a pick', (tester) async {
    await pump(tester, collapsed: true);
    await tester.tap(find.byKey(const ValueKey("language-settings-current")));
    await tester.pumpAndSettle();

    expect(find.text("System default"), findsOneWidget);

    // The current language is the checked one.
    await tester.enterText(find.byType(TextField), "germ");
    await tester.pump();
    expect(find.text("Deutsch"), findsNWidgets(2));
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

    await tester.enterText(find.byType(TextField), "span");
    await tester.pump();
    expect(find.text("Español"), findsOneWidget);
    expect(find.text("System default"), findsNothing);

    await tester.tap(find.text("Español"));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(preferences.appLanguage.value, "es");
    expect(find.text("Español"), findsOneWidget);
  });
}
