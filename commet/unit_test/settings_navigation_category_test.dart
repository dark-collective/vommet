import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/account/settings_category_account.dart';
import 'package:commet/ui/pages/settings/categories/app/local_data_panel.dart';
import 'package:commet/ui/pages/settings/categories/app/settings_category_app.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/ui/pages/settings/settings_navigation.dart';
import 'package:commet/ui/pages/settings/settings_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

// Vommet: the account and the app category both have a "Privacy" tab. The
// New Home "encrypt your messages on this device · Set up" notice opened the
// ACCOUNT's Privacy tab (Chat Privacy, Message filters) because tabs were
// found by label alone; it must open App Settings › Privacy at Data on this
// device.

class _Category implements SettingsCategory {
  _Category(this.title, this.tabs);

  @override
  final String? title;

  @override
  final List<SettingsTab> tabs;
}

const _accountPrivacy = Key("account-privacy");
const _appPrivacy = Key("app-privacy");
const _panel = Key("local-data-panel");

// The real labels and category titles, account first as in the app, with
// stand-in pages. The panel sits far below the fold, so it only shows when
// the highlight scrolls to it.
List<SettingsCategory> _categories() => [
      _Category(SettingsNavigation.accountCategory, [
        SettingsTab(
          label: SettingsCategoryAccount().labelSettingsTabPrivacy,
          icon: Icons.lock,
          pageBuilder: (_) => const SizedBox(key: _accountPrivacy, height: 40),
        ),
      ]),
      _Category(SettingsNavigation.appCategory, [
        SettingsTab(
          label: SettingsCategoryApp().labelSettingsAppGeneral,
          icon: Icons.settings,
          pageBuilder: (_) => const SizedBox(height: 40),
        ),
        SettingsTab(
          label: labelSettingsPrivacy,
          icon: Icons.lock,
          pageBuilder: (_) => Column(key: _appPrivacy, children: const [
            SizedBox(height: 3000),
            SettingsSearchTarget(
                ids: [localDataSettingId],
                // Opaque, so hitTestable() finds it once on screen.
                child: ColoredBox(
                    key: _panel,
                    color: Colors.blue,
                    child: SizedBox(width: 200, height: 80))),
            SizedBox(height: 600),
          ]),
        ),
      ]),
    ];

// Taps a button that calls [open], in a [width] px wide window.
Future<void> _tapOpen(
    WidgetTester tester, double width, void Function(BuildContext) open) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => open(context),
          child: const Text("open"),
        ),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
}

const _layouts = [
  ("mobile", 400.0),
  ("desktop", 1000.0),
  ("desktop", 360.0),
];

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    SettingsNavigation.debugCategories = _categories();
  });

  tearDown(() => SettingsNavigation.debugCategories = null);

  test("the account and app categories both have a Privacy tab", () {
    expect(SettingsCategoryAccount().labelSettingsTabPrivacy,
        labelSettingsPrivacy);
    expect(SettingsNavigation.accountCategory,
        isNot(SettingsNavigation.appCategory));
  });

  test("findTab picks the tab in the named category", () {
    final cats = _categories();
    expect(
        SettingsNavigation.findTab(cats,
            tab: labelSettingsPrivacy,
            category: SettingsNavigation.appCategory),
        same(cats[1].tabs[1]));
    expect(
        SettingsNavigation.findTab(cats,
            tab: labelSettingsPrivacy,
            category: SettingsNavigation.accountCategory),
        same(cats[0].tabs[0]));
  });

  for (final (layout, width) in _layouts) {
    testWidgets(
        "Set up opens App Settings › Privacy at Data on this device "
        "($layout, ${width.toInt()} px)", (tester) async {
      await preferences.layoutOverride.set(layout);
      await _tapOpen(tester, width, openLocalDataSettings);

      expect(find.byKey(_accountPrivacy), findsNothing);
      expect(find.byKey(_appPrivacy), findsOneWidget);
      // Scrolled down to the panel.
      expect(find.byKey(_panel).hitTestable(), findsOneWidget);
    });

    testWidgets(
        "Deep Search's Turn on opens the app's Privacy tab "
        "($layout, ${width.toInt()} px)", (tester) async {
      await preferences.layoutOverride.set(layout);
      await _tapOpen(tester, width, SettingsNavigation.openSearchIndex);

      expect(find.byKey(_accountPrivacy), findsNothing);
      expect(find.byKey(_appPrivacy), findsOneWidget);
    });
  }
}
