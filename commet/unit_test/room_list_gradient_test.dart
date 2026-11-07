import 'dart:convert';

import 'package:commet/client/client_manager.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/theme_config.dart';
import 'package:commet/config/theme_draft.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/ui/atoms/space_header.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/ui/layout/unified_desktop_layout.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:commet/ui/molecules/compact_room_list.dart';
import 'package:commet/ui/molecules/space_sidebar_list.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/main/main_page_view_desktop.dart';
import 'package:commet/ui/pages/main/main_page_view_mobile.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_color_picker.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/atoms/foundation.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';

import 'helpers/navigation_fixture.dart';
import 'room_list_theme_roles_test.dart' show paintedAt;
import 'roomlist_fixture.dart' as fixture;

Map<String, dynamic> gradientJson({double opacity = 1}) => {
      'gradient': {
        'colors': ['#ff0000', '#0000ff'],
        'stops': [0, 1],
        'angle': 180
      },
      'opacity': opacity,
    };

Future<ThemeData> gradientTheme(
        {Object? fill, Map<String, dynamic>? foundation}) =>
    ThemeJsonConverter.fromJson({
      ...ThemeDraft.fromTheme(ThemeDark.theme, '1194').toJson(),
      'foundation': foundation ?? {'color': '#101010'},
      'roomList': fill ?? gradientJson(),
    }, null)
        .then((value) => value!);

void main() {
  late ClientManager manager;
  final boundary = GlobalKey();
  const probe = ValueKey('other-low-tile');
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(const EventChannel("FlutterWebRTC.Event"),
            MockStreamHandler.inline(onListen: (_, __) {}));
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(
        {'vommet_now_playing': false, 'check_for_updates': false});
    await app.preferences.init();
    manager = ClientManager()..callManager.playSounds = false;
    final previous = app.clientManager;
    app.clientManager = manager;
    addTearDown(() => app.clientManager = previous);
    ResponsiveDesktop.collapsed.value = false;
    ResponsiveDesktop.drawerOpen.value = false;
    await unifiedListCollapsed.set(false);
  });

  test('Vommet issue 1194: JSON ZIP draft copy reset and malformed fallback',
      () async {
    final json = {
      ...ThemeDraft.fromTheme(ThemeDark.theme, '1194').toJson(),
      'roomList': gradientJson(opacity: .6),
      'futureKey': {'retained': true},
    };
    final files = ThemeConfig.themeFilesFromZip(ThemeDraft.zipFiles({
      'theme.json': utf8.encode(jsonEncode(json)),
    }))!;
    final portable = ThemeConfig.webThemeJson(files)!;
    final theme = (await ThemeJsonConverter.fromJson(portable, null))!;
    // Reopening without raw JSON proves this is loaded theme behavior.
    final reopened = ThemeDraft.fromTheme(theme, '1194').copy();
    expect((reopened.toJson()['roomList'] as Map)['opacity'], .6);
    expect((reopened.toJson()['roomList'] as Map)['gradient'], {
      'colors': ['#ffff0000', '#ff0000ff'],
      'stops': [0.0, 1.0],
      'angle': 180.0,
    });
    final preserved = ThemeDraft.fromTheme(theme, '1194', raw: portable);
    expect(preserved.toJson()['futureKey'], {'retained': true});
    for (final malformed in [
      'wrong',
      {
        'gradient': {
          'colors': ['#ff0000']
        }
      },
      {
        'gradient': {
          'colors': ['#oops', '#0000ff']
        }
      },
      {
        'gradient': {
          'colors': ['#ff0000', '#0000ff'],
          'stops': [1, 0]
        }
      },
      {
        'gradient': {
          'colors': ['#ff0000', '#0000ff'],
          'stops': [0, 2]
        }
      },
      {...gradientJson(), 'opacity': double.nan},
    ]) {
      final invalid = await gradientTheme(fill: malformed);
      expect(
          ThemeDraft.fromTheme(invalid, '1194', raw: {'roomList': malformed})
              .toJson()
              .containsKey('roomList'),
          isFalse);
    }
    final legacy = ThemeDraft.fromTheme(ThemeDark.theme, 'old');
    expect(legacy.toJson().containsKey('roomList'), isFalse);
  });

  test('1194 ARGB uneven and hard stops survive portable import and export',
      () async {
    final fill = {
      'gradient': {
        'colors': ['#80ff0000', '#ff00ff00', '#0000ff'],
        'stops': [0.1, 0.1, 0.9],
        'angle': 42
      },
      'opacity': .7
    };
    final theme = await gradientTheme(fill: fill);
    final draft = ThemeDraft.fromTheme(theme, '1194');
    final files = ThemeConfig.themeFilesFromZip(ThemeDraft.zipFiles({
      'theme.json': utf8.encode(jsonEncode(draft.copy().toJson())),
    }))!;
    final loaded = (await ThemeJsonConverter.fromJson(
        ThemeConfig.webThemeJson(files)!, null))!;
    final saved =
        ThemeDraft.fromTheme(loaded, '1194').toJson()['roomList'] as Map;
    expect(saved['gradient'], {
      'colors': ['#80ff0000', '#ff00ff00', '#ff0000ff'],
      'stops': [0.1, 0.1, 0.9],
      'angle': 42.0
    });
    expect(saved['opacity'], .7);
  });

  Future<void> pump(WidgetTester tester, ThemeData theme,
      {required bool phone, Widget? content}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(phone ? 390 : 1440, phone ? 844 : 900);
    await app.preferences.layoutOverride.set(phone ? 'mobile' : 'desktop');
    final state = NavigationPageFixture(manager);
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            theme: theme,
            home: Provider<ClientManager>.value(
                value: manager,
                child: OverlayWindowsManager(
                    child: Foundation(
                        child: Scaffold(
                            backgroundColor: Colors.transparent,
                            body: content ??
                                Row(children: [
                                  Expanded(
                                      child: phone
                                          ? MainPageViewMobile(state)
                                          : MainPageViewDesktop(state)),
                                  const SizedBox(
                                      width: 24,
                                      child: Tile.low(
                                          child: SizedBox.expand(key: probe))),
                                ]))))))));
    await tester.pumpAndSettle();
    if (phone && content == null) {
      tester
          .state<OverlappingPanelsState>(find.byType(OverlappingPanels))
          .reveal(RevealSide.left);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  }

  for (final style in LayoutStyle.values) {
    for (final unified in [false, true]) {
      for (final phone in [false, true]) {
        testWidgets(
            '1194 $style unified=$unified phone=$phone paints a local gradient',
            (tester) async {
          addTearDown(tester.view.reset);
          await pickLayoutStyle(style);
          await experimentUnifiedChatList.set(unified);
          final theme = await gradientTheme();
          await pump(tester, theme, phone: phone);
          final tiles = find.byWidgetPredicate(
              (w) => w is Tile && w.mode == TileType.surfaceContainerLow);
          // Production navigation occupies the left pane; avoid rows and footer.
          final rects = tiles
              .evaluate()
              .map((e) => tester.getRect(find.byWidget(e.widget)))
              .where((r) => r.height > 300 && r.width > 50 && r.width < 500)
              .toList();
          expect(rects, isNotEmpty);
          final rect = rects.first;
          final upper = await paintedAt(tester, boundary,
              Offset(rect.right - 3, rect.top + rect.height * .35));
          final lower = await paintedAt(tester, boundary,
              Offset(rect.right - 3, rect.top + rect.height * .8));
          expect(upper.r, greaterThan(lower.r));
          expect(lower.b, greaterThan(upper.b));
          expect(
              await paintedAt(
                  tester, boundary, tester.getCenter(find.byKey(probe))),
              theme.colorScheme.surfaceContainerLow);
          await pump(
              tester, await gradientTheme(fill: gradientJson(opacity: 0)),
              phone: phone);
          expect(
              await paintedAt(tester, boundary,
                  Offset(rect.right - 3, rect.top + rect.height * .8)),
              const Color(0xff101010));
          await pump(tester, ThemeDark.theme, phone: phone);
          expect(
              await paintedAt(tester, boundary,
                  Offset(rect.right - 3, rect.top + rect.height * .8)),
              ThemeDark.theme.colorScheme.surfaceContainerLow);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  testWidgets('1194 opacity reveals an imported window image', (tester) async {
    addTearDown(tester.view.reset);
    await experimentUnifiedChatList.set(true);
    final image = MemoryImage(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNg+M8AAAICAQB7CYF4AAAAAElFTkSuQmCC'));
    final theme = (await ThemeJsonConverter.fromJson({
      ...ThemeDraft.fromTheme(ThemeDark.theme, '1194').toJson(),
      'foundation': {
        'color': '#ffffff',
        'image': {'file': 'green.png', 'fit': 'cover'}
      },
      'roomList': gradientJson(opacity: 0),
    }, null, imageResolver: (_) => image))!;
    await pump(tester, theme, phone: false);
    await tester.runAsync(() =>
        precacheImage(image, tester.element(find.byType(Foundation).first)));
    await tester.pump();
    final pane = find.byWidgetPredicate(
        (w) => w is Tile && w.mode == TileType.surfaceContainerLow);
    final rect = pane
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)))
        .firstWhere((r) => r.height > 300 && r.width > 50 && r.width < 500);
    expect(
        await paintedAt(
            tester, boundary, Offset(rect.right - 3, rect.bottom - 50)),
        const Color(0xff00ff00));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      '1194 folded navigation uses a gradient without recoloring its rail',
      (tester) async {
    addTearDown(tester.view.reset);
    for (final unified in [false, true]) {
      await experimentUnifiedChatList.set(unified);
      await unifiedListCollapsed.set(true);
      ResponsiveDesktop.collapsed.value = true;
      await pump(tester, await gradientTheme(), phone: false);
      if (unified) {
        final compact = tester
            .widget<UnifiedDesktopLayout>(find.byType(UnifiedDesktopLayout))
            .compactNavigation;
        await pump(tester, await gradientTheme(),
            phone: false, content: SizedBox(width: 72, child: compact));
      }
      final rect = tester.getRect(unified
          ? find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'FoldedChatColumn')
          : find.byType(CompactRoomList));
      final top = await paintedAt(tester, boundary,
          Offset(rect.center.dx, rect.top + rect.height * .3));
      final bottom = await paintedAt(tester, boundary,
          Offset(rect.center.dx, rect.top + rect.height * .8));
      expect(top.r, greaterThan(bottom.r));
      expect(bottom.b, greaterThan(top.b));
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('1194 pinned header aligns and composites once over the window',
      (tester) async {
    addTearDown(tester.view.reset);
    final client =
        (await tester.runAsync(() => fixture.signedInClient('1194')))!;
    addTearDown(() => client.getMatrixClient().dispose(closeDatabase: true));
    final ids = [for (var i = 0; i < 40; i++) '!room$i:example.com'];
    await tester.runAsync(() => fixture.sync(client, join: {
          '!space:example.com': fixture.joined('!space:example.com',
              name: '1194 space', children: ids),
          for (final id in ids) id: fixture.joined(id, name: id),
        }));
    manager.addClient(client);
    await experimentUnifiedChatList.set(false);
    final state = NavigationPageFixture(manager,
        currentView: MainPageSubView.space,
        currentSpace: client.getSpace('!space:example.com'));
    final theme = await gradientTheme(fill: gradientJson(opacity: .5));
    await pump(tester, theme,
        phone: false, content: MainPageViewDesktop(state));
    final header = tester.getRect(find.byType(SpaceHeader));
    final list = tester.getRect(find
        .ancestor(
            of: find.byType(SpaceSidebarList), matching: find.byType(Tile))
        .first);
    final point = header.topRight + const Offset(-3, 3);
    final t = (point.dy - list.top) / list.height;
    final expected = Color.alphaBlend(
        Color.lerp(const Color(0xffff0000), const Color(0xff0000ff), t)!
            .withValues(alpha: .5),
        const Color(0xff101010));
    final before = await paintedAt(tester, boundary, point);
    expect((before.r - expected.r).abs(), lessThan(.02));
    expect((before.b - expected.b).abs(), lessThan(.02));
    await tester.drag(find.byType(SpaceSidebarList), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(await paintedAt(tester, boundary, point), before,
        reason:
            'scrolling rows cannot show through or restart the header gradient');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('1194 phone editor shows the list in the compact chat scene',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await app.preferences.layoutOverride.set('mobile');
    final theme = await gradientTheme();
    await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: ThemeEditorPage(draft: ThemeDraft.fromTheme(theme, '1194'))));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final preview = find.byType(ThemeLivePreview);
    expect(find.descendant(of: preview, matching: find.text('Lantern Club')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('1194 real editor enables edits and clears the optional fill',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    final draft = ThemeDraft.fromTheme(ThemeDark.theme, '1194');
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme, home: ThemeEditorPage(draft: draft)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Background').first);
    await tester.pumpAndSettle();
    final fillHeading = find.text('Room list fill');
    final controls = find.byKey(const ValueKey('theme-editor-controls'));
    final scroll =
        find.descendant(of: controls, matching: find.byType(Scrollable)).first;
    await tester.drag(scroll, const Offset(0, -1600));
    await tester.pumpAndSettle();
    expect(fillHeading, findsOneWidget);
    await tester.ensureVisible(fillHeading);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('room-list-gradient')));
    await tester.pumpAndSettle();
    expect(find.text('Position 1 0%'), findsOneWidget);
    expect(find.text('Opacity 100%'), findsOneWidget);
    for (var count = 3; count <= 5; count++) {
      final add = find.text('Add color');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Position $count 100%'), findsOneWidget);
    }
    expect(find.text('Add color'), findsNothing);

    final lastColor = find.byTooltip('Color 5');
    await tester.ensureVisible(lastColor);
    await tester.tap(lastColor);
    await tester.pumpAndSettle();
    final picker = find.byType(ThemeColorPicker);
    await tester.enterText(
        find.descendant(of: picker, matching: find.byType(TextField)),
        '#ffffff');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: lastColor,
            matching: find.byWidgetPredicate(
                (w) => w is CircleAvatar && w.backgroundColor == Colors.white)),
        findsOneWidget);
    expect(
        find.text(
            'Room list contrast may be low. Check text, icons and selected rows.'),
        findsOneWidget);
    await tester.ensureVisible(lastColor);
    await tester.tap(lastColor);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove color'));
    await tester.pumpAndSettle();
    expect(lastColor, findsNothing);
    expect(find.text('Add color'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('room-list-solid')));
    await tester.tap(find.byKey(const ValueKey('room-list-solid')));
    await tester.pumpAndSettle();
    expect(find.text('Opacity 100%'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
