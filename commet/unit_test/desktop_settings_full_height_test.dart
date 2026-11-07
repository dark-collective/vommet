import 'package:commet/ui/pages/settings/desktop_settings_page.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/ui/pages/settings/settings_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/tiamat.dart';

class _Category implements SettingsCategory {
  _Category(this.tabs);

  @override
  String? get title => null;

  @override
  final List<SettingsTab> tabs;
}

Future<void> _pump(WidgetTester tester, {required bool scrollable}) {
  return tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    home: DesktopSettingsPage(settings: [
      _Category([
        SettingsTab(
          label: "Short",
          makeScrollable: scrollable,
          pageBuilder: (_) => const SizedBox(key: Key("short"), height: 40),
        ),
      ]),
    ]),
  ));
}

void main() {
  // A short page used to shrink the content panel to its own height, so the
  // theme's foundation (a background image, say) showed below it.
  for (final scrollable in [true, false]) {
    testWidgets("content panel fills the height (makeScrollable: $scrollable)",
        (tester) async {
      await _pump(tester, scrollable: scrollable);

      final panel = find.ancestor(
          of: find.byKey(const Key("short")), matching: find.byType(Tile));
      expect(tester.getSize(panel.first).height,
          tester.view.physicalSize.height / tester.view.devicePixelRatio);
    });
  }

  testWidgets("a scrollable page scrolls inside the panel", (tester) async {
    await _pump(tester, scrollable: true);

    final scroll = find.ancestor(
        of: find.byKey(const Key("short")),
        matching: find.byType(SingleChildScrollView));
    expect(scroll, findsOneWidget);
    expect(
        find.ancestor(of: scroll, matching: find.byType(Tile)), findsWidgets);
  });
}
