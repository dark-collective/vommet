import 'package:commet/ui/pages/settings/desktop_settings_page.dart';
import 'package:commet/ui/pages/settings/mobile_settings_page.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/ui/pages/settings/settings_quit_button.dart';
import 'package:commet/ui/pages/settings/settings_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class _Category implements SettingsCategory {
  @override
  String? get title => null;

  @override
  List<SettingsTab> get tabs => [
        SettingsTab(
            label: "General",
            icon: Icons.settings,
            pageBuilder: (_) => const SizedBox()),
      ];
}

final _quitButton = find.byKey(SettingsQuitButton.buttonKey);
final _label = SettingsQuitButton.promptQuitApp("Vommet");

Future<void> _pump(WidgetTester tester, Widget page,
    {Size size = const Size(1280, 800)}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(theme: ThemeDark.theme, home: page));
  await tester.pumpAndSettle();
}

// The Quit row lines up with the tab rows: same icon x, same label x.
void _expectAligned(WidgetTester tester, {bool labels = true}) {
  expect(tester.getTopLeft(find.byIcon(Icons.power_settings_new)).dx,
      tester.getTopLeft(find.byIcon(Icons.settings).first).dx);
  if (labels) {
    expect(tester.getTopLeft(find.text(_label)).dx,
        tester.getTopLeft(find.text("General").first).dx);
  }
}

Future<void> _tapQuit(WidgetTester tester) async {
  await tester.ensureVisible(_quitButton);
  await tester.tap(_quitButton);
  await tester.pump();
}

void main() {
  test("label names the app", () {
    expect(_label, "Quit Vommet");
  });

  test("no Quit where the app can't quit itself", () {
    expect(SettingsQuitButton.buttons(supported: false), isNull);
    expect(SettingsQuitButton.buttons(supported: true), hasLength(1));
  });

  // Vommet issue 348: at the bottom of the list, below every tab, in the
  // list's own (neutral) colors, not in the header next to the back button.
  testWidgets("wide sidebar: last entry, neutral, quits", (tester) async {
    var quits = 0;
    await _pump(
        tester,
        DesktopSettingsPage(
            settings: [_Category()],
            buttons: SettingsQuitButton.buttons(
                supported: true, quit: () async => quits++)));

    expect(_quitButton, findsOneWidget);
    expect(find.text(_label), findsOneWidget);
    expect(
        find.descendant(
            of: _quitButton, matching: find.byIcon(Icons.power_settings_new)),
        findsOneWidget);
    final button = tester.widget<tiamat.TextButton>(find.descendant(
        of: _quitButton, matching: find.byType(tiamat.TextButton)));
    expect(button.textColor, isNull);
    expect(button.iconColor, isNull);
    expect(tester.getTopLeft(_quitButton).dy,
        greaterThan(tester.getTopLeft(find.text("General")).dy));
    expect(
        tester.getTopLeft(_quitButton).dy,
        greaterThan(tester
            .getBottomLeft(find.byKey(DesktopSettingsPageState.backButtonKey))
            .dy));
    _expectAligned(tester);

    await _tapQuit(tester);
    expect(quits, 1);
  });

  testWidgets("icon rail: power icon with the name as tooltip, quits",
      (tester) async {
    var quits = 0;
    await _pump(
        tester,
        DesktopSettingsPage(
            settings: [_Category()],
            buttons: SettingsQuitButton.buttons(
                supported: true, quit: () async => quits++)),
        size: const Size(500, 800));

    expect(_quitButton, findsOneWidget);
    expect(find.byTooltip(_label), findsOneWidget);
    _expectAligned(tester, labels: false);
    await _tapQuit(tester);
    expect(quits, 1);
  });

  testWidgets("single column: last entry, quits", (tester) async {
    var quits = 0;
    await _pump(
        tester,
        DesktopSettingsPage(
            settings: [_Category()],
            buttons: SettingsQuitButton.buttons(
                supported: true, quit: () async => quits++)),
        size: const Size(360, 800));

    expect(find.text(_label), findsOneWidget);
    _expectAligned(tester);
    await _tapQuit(tester);
    expect(quits, 1);
  });

  testWidgets("narrow layout: last entry, quits", (tester) async {
    var quits = 0;
    await _pump(
        tester,
        MobileSettingsPage(
            settings: [_Category()],
            buttons: SettingsQuitButton.buttons(
                supported: true, quit: () async => quits++)));

    expect(find.text(_label), findsOneWidget);
    expect(tester.getTopLeft(_quitButton).dy,
        greaterThan(tester.getTopLeft(find.text("General")).dy));
    _expectAligned(tester);
    await _tapQuit(tester);
    expect(quits, 1);
  });

  // Room and space settings use the same pages with their own buttons (or
  // none); only AppSettingsPage passes the Quit entry.
  testWidgets("not in room or space settings", (tester) async {
    await _pump(tester, DesktopSettingsPage(settings: [_Category()]));
    expect(_quitButton, findsNothing);
    expect(find.byIcon(Icons.power_settings_new), findsNothing);
    await _pump(tester, MobileSettingsPage(settings: [_Category()]));
    expect(_quitButton, findsNothing);
  });
}
