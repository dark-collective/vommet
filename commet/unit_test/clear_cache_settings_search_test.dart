import 'package:commet/cache/file_cache.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/advanced_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/settings_category_app.dart';
import 'package:commet/ui/pages/settings/desktop_settings_page.dart';
import 'package:commet/ui/pages/settings/mobile_settings_page.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/settings/search/settings_search_entries.dart';
import 'package:commet/ui/pages/settings/settings_page.dart';
import 'package:commet/utils/clear_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';
import 'package:intl/src/intl_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Only cache availability is needed: search never reads or clears its data.
class _FileCache extends Fake implements FileCache {}

// A test locale verifies the search uses the existing panel's message.
class _Messages extends MessageLookupByLibrary {
  @override
  String get localeName => 'fr';

  @override
  final messages = <String, Function>{
    'labelClearCache': () => 'Vider le cache',
    'labelSettingsAppAdvanced': () => 'Avancé',
  };
}

const _queries = ['cache', 'clear', 'close', 'restart', 'reload'];

Finder _clearCacheResult() => find.descendant(
    of: find.byType(SettingsSearchResults),
    matching: find.text('Clear cache', findRichText: true));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    final previousCache = fileCache;
    fileCache = _FileCache();
    addTearDown(() => fileCache = previousCache);
  });

  test('Vommet issue 1178: all action words locate the real Advanced tab', () {
    final app = SettingsCategoryApp();
    expect(searchAppSettings('cache', [app]), isNotEmpty,
        reason: 'The reporter already sees media-cache search results');
    for (final query in [
      ..._queries,
      'Clear cache and close',
      'clear reload'
    ]) {
      final hits = searchAppSettings(query, [app])
          .where((hit) => hit.entry.title == 'Clear cache');
      expect(hits, hasLength(1), reason: query);
      final hit = hits.single;
      expect(hit.isPage, isFalse);
      expect(hit.entry.hasInlineToggle, isFalse);
      expect(app.tabs[hit.tabIndex].label, app.labelSettingsAppAdvanced);
      expect(app.tabs[hit.tabIndex].pageBuilder, isNotNull);
    }
  });

  test('Vommet issue 1178: localized title keeps English aliases and target',
      () {
    initializeInternalMessageLookup(() => CompositeMessageLookup());
    messageLookup.addLocale('fr', (_) => _Messages());
    final previousLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'fr';
    addTearDown(() => Intl.defaultLocale = previousLocale);
    final app = SettingsCategoryApp();
    for (final query in ['vider', ..._queries]) {
      final hits = searchAppSettings(query, [app])
          .where((hit) => hit.entry.title == 'Vider le cache');
      expect(hits, hasLength(1), reason: query);
      final hit = hits.single;
      expect(app.tabs[hit.tabIndex].label, 'Avancé');
      expect(hit.entry.targetId, 'advanced.clear-cache');
      expect(hit.entry.hasInlineToggle, isFalse);
    }
  });

  for (final style in LayoutStyle.values) {
    for (final phone in [false, true]) {
      testWidgets(
          'Vommet issue 1178: ${style.name} ${phone ? '360x800 phone' : '1280x800 desktop'} opens the panel and preserves confirmation',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(phone ? 360 : 1280, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await pickLayoutStyle(style);
        await preferences.layoutOverride.set(phone ? 'mobile' : 'desktop');
        final app = SettingsCategoryApp();
        // Advanced avoids unrelated General settings services at startup.
        // Phone starts with its real tab/search list.
        await tester.pumpWidget(MaterialApp(
            theme: ThemeDark.theme,
            home: SettingsPage(
                settings: [app],
                initialTab: app.labelSettingsAppAdvanced,
                initialCategory: app.title)));
        await tester.pumpAndSettle();
        expect(find.byType(phone ? MobileSettingsPage : DesktopSettingsPage),
            findsOneWidget);

        for (final query in _queries) {
          final field = find.byKey(const ValueKey('SETTINGS_SEARCH_FIELD'));
          await tester.enterText(field, query);
          await tester.pumpAndSettle();
          final result = _clearCacheResult();
          expect(result, findsOneWidget, reason: query);
          await tester.ensureVisible(result);
          await tester.tap(result);
          await tester.pumpAndSettle();
          expect(find.byType(AdvancedSettingsPage), findsOneWidget);
          final button = find.widgetWithText(
              tiamat.Button,
              ClearCache.restartsItself
                  ? 'Clear cache and restart'
                  : 'Clear cache and close');
          // Search must bring the real action into view, even on the phone.
          expect(button.hitTestable(), findsOneWidget, reason: query);
          expect(find.text('Clear cache?'), findsNothing);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(find.text('Clear cache?'), findsWidgets);
          expect(
              find.textContaining(
                  'You stay logged in and keep your encryption keys.'),
              findsWidgets);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
          expect(tester.widget<tiamat.Button>(button).isLoading, isFalse);
          expect(tester.takeException(), isNull);
          if (phone) {
            // Return from the real SettingsSubPage to search again.
            Navigator.of(tester.element(find.byType(AdvancedSettingsPage)))
                .pop();
            await tester.pumpAndSettle();
          }
        }
      });
    }
  }
}
