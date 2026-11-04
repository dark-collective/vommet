import 'dart:ui' as ui;

import 'package:commet/client/client_manager.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/ui/atoms/message_box.dart';
import 'package:commet/ui/atoms/space_header.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/ui/layout/unified_desktop_layout.dart';
import 'package:commet/ui/molecules/compact_room_list.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:commet/ui/molecules/space_sidebar_list.dart';
import 'package:commet/ui/organisms/home_screen/single_rooms_list.dart';
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_view.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/main/main_page_view_desktop.dart';
import 'package:commet/ui/pages/main/main_page_view_mobile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import 'helpers/navigation_fixture.dart';
import 'helpers/unread_fixtures.dart';

const _list = Color(0xff154f3b);
const _panels = Color(0xff392d59);
const _composer = Color(0xff523318);
const _border = Color(0xffebc488);
const _panelKey = ValueKey('settings-panel-probe');
const _composerKey = ValueKey('composer-probe');

ThemeData navigationTheme({Color list = _list, Color panels = _panels}) {
  final base = ThemeDark.theme;
  return base.copyWith(
    colorScheme: base.colorScheme
        .copyWith(surfaceContainerLow: list, surfaceContainer: panels),
    extensions: [
      ...base.extensions.values.where((e) => e is! ExtraColors),
      base
          .extension<ExtraColors>()!
          .copyWith(composerBackground: _composer, composerBorder: _border),
    ],
  );
}

// Read the painted result rather than a Tile constructor or enum. The sample
// point is in empty list space, so no row/selection/hover fill can hide it.
Future<Color> paintedAt(
    WidgetTester tester, GlobalKey boundary, Offset point) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final local = render.globalToLocal(point);
  return tester.runAsync(() async {
    final image = await render.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = (local.dy.floor() * image.width + local.dx.floor()) * 4;
    final color = Color.fromARGB(
        bytes.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2));
    image.dispose();
    return color;
  }).then((color) => color!);
}

void main() {
  late ClientManager manager;
  late UnreadClient spaceClient;
  final boundary = GlobalKey();
  setUp(() async {
    // unit_test/ is not a recognized test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(
        {'vommet_now_playing': false, 'check_for_updates': false});
    await app.preferences.init();
    await app.preferences.checkForUpdates.set(false);
    manager = ClientManager()..callManager.playSounds = false;
    final previous = app.clientManager;
    app.clientManager = manager;
    addTearDown(() => app.clientManager = previous);
    spaceClient = UnreadClient('theme-account');
    addTearDown(spaceClient.close);
    ResponsiveDesktop.collapsed.value = false;
    ResponsiveDesktop.drawerOpen.value = false;
    await unifiedListCollapsed.set(false);
  });

  Future<void> pump(
      WidgetTester tester, NavigationPageFixture state, ThemeData theme,
      {required bool phone, Widget? content}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(phone ? 520 : 1200, 760);
    await app.preferences.layoutOverride.set(phone ? 'mobile' : 'desktop');
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            theme: theme,
            home: Provider<ClientManager>.value(
                value: manager,
                child: OverlayWindowsManager(
                    child: Scaffold(
                        body: Row(children: [
                  Expanded(
                      child: content ??
                          (phone
                              ? MainPageViewMobile(state)
                              : MainPageViewDesktop(state))),
                  const SizedBox(
                      width: 90,
                      child: Column(children: [
                        Expanded(
                            child: Tile.surfaceContainer(
                                child: SizedBox.expand(key: _panelKey))),
                        MessageBox(
                            borderRadius: BorderRadius.zero,
                            child: SizedBox(
                                key: _composerKey, height: 60, width: 90)),
                      ])),
                ])))))));
    await tester.pumpAndSettle();
    if (phone && content == null) {
      tester
          .state<OverlappingPanelsState>(find.byType(OverlappingPanels))
          .reveal(RevealSide.left);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> check(WidgetTester tester, Finder list, Color expected,
      {Offset? point}) async {
    final rect = tester.getRect(list);
    expect(
        await paintedAt(tester, boundary,
            point ?? Offset(rect.center.dx, rect.bottom - 20)),
        expected,
        reason: 'room-list pane must use Room list, independently of Panels');
    expect(
        await paintedAt(
            tester, boundary, tester.getCenter(find.byKey(_panelKey))),
        _panels);
    expect(
        await paintedAt(
            tester, boundary, tester.getCenter(find.byKey(_composerKey))),
        _composer);
    final box = tester.widget<Container>(find
        .descendant(
            of: find.byType(MessageBox), matching: find.byType(Container))
        .first);
    expect(
        ((box.foregroundDecoration! as BoxDecoration).border! as Border)
            .top
            .color,
        _border);
  }

  for (final style in LayoutStyle.values) {
    for (final unified in [false, true]) {
      for (final phone in [false, true]) {
        for (final view in (!unified && phone
            ? [
                MainPageSubView.home,
                MainPageSubView.rooms,
                MainPageSubView.space
              ]
            : [MainPageSubView.rooms])) {
          testWidgets(
              '$style unified=$unified phone=$phone $view: list and panels are independent',
              (tester) async {
            addTearDown(tester.view.reset);
            addTearDown(() => tester.pumpWidget(const SizedBox()));
            await pickLayoutStyle(style);
            await experimentUnifiedChatList.set(unified);
            final state = NavigationPageFixture(manager,
                currentView: view,
                currentSpace: view == MainPageSubView.space
                    ? NavigationSpaceFixture(spaceClient)
                    : null);
            final anchor = unified
                ? find.byType(ChatListPane)
                : switch (view) {
                    MainPageSubView.home => find.byType(HomeColumn),
                    MainPageSubView.space => find.byType(SpaceSidebarList),
                    _ => find.byType(SingleRoomsList),
                  };
            await pump(tester, state, navigationTheme(), phone: phone);
            await check(tester, anchor, _list);
            const changed = Color(0xff235a66);
            await pump(tester, state, navigationTheme(list: changed),
                phone: phone);
            await check(tester, anchor, changed);
            const panels = Color(0xff613d57);
            await pump(
                tester, state, navigationTheme(list: changed, panels: panels),
                phone: phone);
            final rect = tester.getRect(anchor);
            expect(
                await paintedAt(
                    tester, boundary, Offset(rect.center.dx, rect.bottom - 20)),
                changed);
            expect(
                await paintedAt(
                    tester, boundary, tester.getCenter(find.byKey(_panelKey))),
                panels);
            expect(
                await paintedAt(tester, boundary,
                    tester.getCenter(find.byKey(_composerKey))),
                _composer);
            await tester.pumpWidget(const SizedBox());
          });
        }
      }
    }
  }

  testWidgets(
      'folded classic and unified navigation keep the Room list background',
      (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    for (final unified in [false, true]) {
      await experimentUnifiedChatList.set(unified);
      await unifiedListCollapsed.set(true);
      ResponsiveDesktop.collapsed.value = true;
      final state = NavigationPageFixture(manager);
      await pump(tester, state, navigationTheme(), phone: false);
      if (unified) {
        // No room is selected in this account fixture, so the page keeps the
        // named list visible. Mount its actual compact navigation branch.
        final compact = tester
            .widget<UnifiedDesktopLayout>(find.byType(UnifiedDesktopLayout))
            .compactNavigation;
        await pump(tester, state, navigationTheme(),
            phone: false,
            content: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 72, child: compact)));
      }
      final anchor = unified
          ? find.byType(FoldedChatColumn)
          : find.byType(CompactRoomList);
      await check(tester, anchor, _list, point: tester.getCenter(anchor));
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'pinned space header follows Room list and retains an explicit override',
      (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final state = NavigationPageFixture(manager);
    final space = NavigationSpaceFixture(spaceClient);
    Widget header([Color? override]) => SpaceSidebarList(space,
        headerBackground: override, child: const SizedBox(height: 1000));
    Future<Color> color() {
      final rect = tester.getRect(find.byType(SpaceHeader));
      return paintedAt(tester, boundary, rect.topRight + const Offset(-4, 4));
    }

    await pump(tester, state, navigationTheme(),
        phone: false, content: header());
    expect(await color(), _list);
    await tester.drag(find.byType(SpaceSidebarList), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(await color(), _list);
    const explicit = Color(0xff753849);
    await pump(tester, state, navigationTheme(),
        phone: false, content: header(explicit));
    expect(await color(), explicit);
    await tester.pumpWidget(const SizedBox());
  });
}
