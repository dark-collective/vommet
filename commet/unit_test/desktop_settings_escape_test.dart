import 'package:commet/ui/pages/settings/desktop_settings_page.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/ui/pages/settings/settings_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Category implements SettingsCategory {
  _Category(this.tabs);

  @override
  String? get title => null;

  @override
  final List<SettingsTab> tabs;
}

// Opens the settings page on top of a home page, like the gear icon does.
Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DesktopSettingsPage(settings: [
                  _Category([
                    SettingsTab(
                      label: "Page",
                      pageBuilder: (_) => const SizedBox(key: Key("page")),
                    ),
                  ]),
                ]))),
        child: const Text("open"),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
  expect(find.byType(DesktopSettingsPage), findsOneWidget);
}

void main() {
  testWidgets("Esc closes the settings page", (tester) async {
    await _open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(DesktopSettingsPage), findsNothing);
    expect(find.text("open"), findsOneWidget);
  });

  testWidgets("Esc clears an active search before closing", (tester) async {
    await _open(tester);
    final state = tester
        .state<DesktopSettingsPageState>(find.byType(DesktopSettingsPage));
    state.searchController.text = "theme";

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(state.searchController.text, isEmpty);
    expect(find.byType(DesktopSettingsPage), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopSettingsPage), findsNothing);
  });
}
