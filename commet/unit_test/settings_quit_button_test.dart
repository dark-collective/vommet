import 'package:commet/ui/pages/settings/desktop_settings_page.dart';
import 'package:commet/ui/pages/settings/mobile_settings_page.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/ui/pages/settings/settings_quit_button.dart';
import 'package:commet/ui/pages/settings/settings_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Category implements SettingsCategory {
  @override
  String? get title => null;

  @override
  List<SettingsTab> get tabs => [
        SettingsTab(label: "General", pageBuilder: (_) => const SizedBox()),
      ];
}

final _quitButton = find.byKey(SettingsQuitButton.buttonKey);

Future<void> _pump(WidgetTester tester, Widget page) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(theme: ThemeDark.theme, home: page));
}

void main() {
  testWidgets("Quit quits", (tester) async {
    var quitCalls = 0;
    await _pump(
        tester,
        Scaffold(
            body:
                SettingsQuitButton(show: true, quit: () async => quitCalls++)));

    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    expect(find.byTooltip(SettingsQuitButton.promptQuitApp), findsOneWidget);
    await tester.tap(_quitButton);
    await tester.pump();

    expect(quitCalls, 1);
  });

  testWidgets("hidden where it doesn't apply", (tester) async {
    await _pump(tester, const Scaffold(body: SettingsQuitButton(show: false)));
    expect(_quitButton, findsNothing);
  });

  // Room and space settings use the same pages; they are not inside
  // AppSettingsPage, so they get no Quit button.
  testWidgets("not in room or space settings (desktop layout)", (tester) async {
    await _pump(tester, DesktopSettingsPage(settings: [_Category()]));
    expect(find.byType(SettingsQuitButton), findsOneWidget);
    expect(_quitButton, findsNothing);
    expect(find.byKey(DesktopSettingsPageState.backButtonKey), findsOneWidget);
  });

  testWidgets("not in room or space settings (narrow layout)", (tester) async {
    await _pump(tester, MobileSettingsPage(settings: [_Category()]));
    expect(find.byType(SettingsQuitButton), findsOneWidget);
    expect(_quitButton, findsNothing);
  });
}
