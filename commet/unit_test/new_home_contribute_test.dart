import 'dart:convert';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/new_home/new_home_text.dart';
import 'package:commet/ui/organisms/new_home/new_home_text_model.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_light.dart';

class _Manager extends Fake implements ClientManager {
  @override
  final clients = NotifyingList<Client>.empty(growable: true);
}

class _TextClient extends Fake implements MatrixClient {
  @override
  String get identifier => 'text-card-fixture';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saved layouts never acquire a tab, including empty and legacy layouts',
      () {
    final old = HomeTabs.defaults.removeTab(HomeTabs.contribute);
    for (final saved in [
      old.toJson(),
      old.removeTab(HomeTabs.people).toJson(),
      const HomeTabs([]).toJson(),
      HomeLayout.defaults.toJson(),
      const HomeLayout([]).toJson(),
      <String, dynamic>{},
    ]) {
      final parsed = HomeTabs.parse(saved);
      expect(parsed.tab(HomeTabs.contribute), isNull);
      expect(parsed.removedDefaults, contains(HomeTabs.contribute));
      expect(HomeTabs.parse(parsed.toJson()).tab(HomeTabs.contribute), isNull);
    }
    expect(HomeTabs.parse(const HomeTabs([]).toJson()).tabs, isEmpty);
    expect(HomeTabs.parse(null).tabs.last.id, HomeTabs.contribute);
  });

  test('the default Contribute tab removes, restores, and resets normally', () {
    final removed = HomeTabs.defaults.removeTab(HomeTabs.contribute);
    final (restored, id) = removed.createTab(
        name: 'Contribute', icon: 'heart', restore: HomeTabs.contribute);
    expect(id, HomeTabs.contribute);
    expect(restored.tabs.last.main.cards.single.preset, 'contribute');
    expect(removed.reset().tabs.last.id, HomeTabs.contribute);
    expect(HomeTabs.parse(removed.toJson()).tab(HomeTabs.contribute), isNull);
  });

  test(
      'bundled contribution copy is a normal Text preset with all requests expanded',
      () async {
    final presets =
        parseTextPresets(await rootBundle.loadString(HomeTextPresets.asset));
    final preset = presets['contribute']!;
    final card = HomeTabs.defaultTab(HomeTabs.contribute)!.main.cards.single;
    expect(card.type, HomeLayout.textCard);
    expect(card.configurable, isFalse);
    expect(textCollapses(preset.body), isFalse);
    expect(
        preset.body,
        contains(
            'Hire me if you’re looking for a programmer, Linux sysadmin, or networking guru.'));
    final headings = [
      '1. Hire the maintainer',
      '2. Dart and Flutter',
      '3. AI-assisted work',
      '4. Test Vommet',
      '5. App-store packaging'
    ];
    final positions = headings.map(preset.body.indexOf).toList();
    expect(positions.every((p) => p >= 0), isTrue);
    expect(positions, orderedEquals([...positions]..sort()));
    expect(preset.buttons.map((b) => b.target), [
      'https://nether.codes/nether/vommet/src/branch/main/CONTRIBUTING.md',
      'https://nether.codes/nether/meta/src/branch/master/agents/vommet-contributor.md',
    ]);
    expect(preset.buttons.every((b) => b.valid), isTrue);
  });

  test('a bundled card can become an editable copy on a custom Home tab',
      () async {
    final store = HomeLayoutStore.instance;
    final original =
        HomeTabs.defaultTab(HomeTabs.contribute)!.main.cards.single;
    final own = HomeTabs.defaults
        .newTab('My notes', 'book')
        .copyWith(main: HomeLayout([original], inTab: true));
    await store.saveTabs(HomeTabs([own]));
    newHomeTab.value = own.id;
    await copyTextPreset(original);
    final cards = store.currentView.main.cards;
    expect(cards, hasLength(2));
    expect(cards.first.preset, 'contribute');
    expect(cards.last.preset, isNull);
    expect(cards.last.configurable, isTrue);
    expect(cards.last.body, contains('networking guru'));
    expect(cards.last.buttons, hasLength(2));
    final saved =
        HomeTabs.parse(jsonDecode(jsonEncode(store.tabs.value.toJson())));
    expect(saved.tabs.single.main.cards.last.body, cards.last.body);
    await store.saveTabs(HomeTabs.defaults);
    newHomeTab.value = HomeTabs.overview;
  });

  for (final theme in [ThemeDark.theme, ThemeLight.theme]) {
    testWidgets(
        'Text-card buttons have readable contrast (${theme.brightness})',
        (tester) async {
      final manager = _Manager()..clients.add(_TextClient());
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: NewHomeTextCardBody(
                clientManager: manager,
                card: const HomeCard(
                  'links',
                  type: HomeLayout.textCard,
                  name: 'Resources',
                  body: 'Useful links.',
                  buttons: [
                    TextButtonTarget('Contribution guide',
                        kind: TextButtonTarget.link,
                        target: 'https://nether.codes/nether/vommet')
                  ],
                )),
          )));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final foreground = button.style!.foregroundColor!.resolve({})!;
      final a = foreground.computeLuminance();
      final b = theme.colorScheme.primary.computeLuminance();
      final contrast = ((a > b ? a : b) + 0.05) / ((a < b ? a : b) + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'people can author their own Text card and place it on any Home tab',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    HomeCard? created;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        created = await showTextCardEditor(context, _Manager(),
                            card: const HomeCard('my-text',
                                type: HomeLayout.textCard));
                      },
                      child: const Text('Write a card')),
                ))));
    await tester.tap(find.text('Write a card'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('NewHomeTextTitle')), 'My notes');
    await tester.enterText(find.byKey(const ValueKey('NewHomeTextBody')),
        '## My own heading\n\n**Anything I choose**');
    await tester.tap(find.byKey(const ValueKey('NewHomeTextSave')));
    await tester.pumpAndSettle();
    expect(created!.preset, isNull);
    expect(created!.body, contains('**Anything I choose**'));
    final mine = HomeTabs.defaults.newTab('Personal', 'book');
    for (final tab in [...HomeTabs.defaults.tabs, mine]) {
      final next = tab.copyWith(main: tab.main.insert(created!));
      final saved = HomeTab.fromJson(next.toJson())!;
      expect(saved.main.card('my-text').name, 'My notes');
      expect(saved.main.card('my-text').configurable, isTrue);
    }
  });
}
