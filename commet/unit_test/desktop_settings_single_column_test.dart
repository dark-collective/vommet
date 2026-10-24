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

final _tabs = [
  SettingsTab(
    label: "First",
    pageBuilder: (_) => const SizedBox(key: Key("first"), height: 40),
  ),
  SettingsTab(
    label: "Second",
    pageBuilder: (_) => const SizedBox(key: Key("second"), height: 40),
  ),
];

// Opens the settings page on top of a home page in a [width] px wide window.
Future<void> _open(WidgetTester tester,
    {required double width, String? initialTab}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DesktopSettingsPage(
                initialTab: initialTab, settings: [_Category(_tabs)]))),
        child: const Text("open"),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("wide window: tab list and first tab side by side",
      (tester) async {
    await _open(tester, width: 800);
    expect(find.text("Second"), findsOneWidget);
    expect(find.byKey(const Key("first")), findsOneWidget);
    expect(find.byKey(DesktopSettingsPageState.tabBackButtonKey), findsNothing);
  });

  testWidgets("narrow window: the tab list fills the page, a tab opens alone",
      (tester) async {
    await _open(tester, width: 400);
    expect(find.text("Second"), findsOneWidget);
    expect(find.byKey(const Key("first")), findsNothing);

    await tester.tap(find.text("Second"));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key("second")), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key("second"))).width,
        greaterThan(300));

    await tester.tap(find.byKey(DesktopSettingsPageState.tabBackButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key("second")), findsNothing);
    expect(find.text("First"), findsOneWidget);
  });

  testWidgets("narrow window: initialTab opens that tab", (tester) async {
    await _open(tester, width: 400, initialTab: "Second");
    expect(find.byKey(const Key("second")), findsOneWidget);
    expect(
        find.byKey(DesktopSettingsPageState.tabBackButtonKey), findsOneWidget);
  });

  testWidgets("narrow window: Esc goes from a tab to the list, then closes",
      (tester) async {
    await _open(tester, width: 400, initialTab: "Second");

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key("second")), findsNothing);
    expect(find.byType(DesktopSettingsPage), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopSettingsPage), findsNothing);
  });

  testWidgets("shrinking the window keeps the open tab, with the back arrow",
      (tester) async {
    await _open(tester, width: 800);
    await tester.tap(find.text("Second"));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(400, 600);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key("second")), findsOneWidget);
    expect(
        find.byKey(DesktopSettingsPageState.tabBackButtonKey), findsOneWidget);

    await tester.tap(find.byKey(DesktopSettingsPageState.tabBackButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key("second")), findsNothing);
    expect(find.text("First"), findsOneWidget);
  });
}
