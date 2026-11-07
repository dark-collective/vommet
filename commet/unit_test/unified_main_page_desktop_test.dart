import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/ui/pages/main/main_page_view_desktop.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/unified_desktop_layout.dart';
import 'package:commet/ui/molecules/current_session_panel.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_main_page.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Main extends Fake with Diagnosticable implements MainPageState {
  _Main(this.clientManager);
  @override
  final ClientManager clientManager;
  @override
  Client? get filterClient => null;
  @override
  Room? currentRoom;
  @override
  bool get showAsTextRoom => false;
  @override
  Profile? get currentUser => null;
}

class _Permissions extends Permissions {}

class _Pushes extends NavigatorObserver {
  _Pushes(this.routes);
  final List<Route> routes;
  @override
  void didPush(Route route, Route? previousRoute) => routes.add(route);
}

class _Room extends Fake implements Room {
  _Room(this.localId);
  @override
  final String localId;
  @override
  Permissions get permissions => _Permissions();
}

void main() {
  test('shared conversation keeps room identity when unified shell owns flex',
      () {
    final state = _Main(ClientManager())..currentRoom = _Room('first');
    final builder = MainPageViewDesktop(state);
    final regular = builder.roomChatView();
    final unified = builder.roomChatView(expanded: false);
    expect(regular, isA<Expanded>());
    expect(unified, isA<KeyedSubtree>());
    expect(unified.key, regular.key);
    state.currentRoom = _Room('second');
    expect(builder.roomChatView(expanded: false).key, isNot(unified.key));
  });

  testWidgets('actual desktop page exposes navigation with no selected room',
      (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'vommet_now_playing': false});
    await app.preferences.init();
    await app.preferences.layoutOverride.set('desktop');
    final previous = app.clientManager;
    final manager = ClientManager()..callManager.playSounds = false;
    app.clientManager = manager;
    addTearDown(() => app.clientManager = previous);
    tester.view.physicalSize = const Size(440, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pushes = <Route>[];
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        navigatorObservers: [_Pushes(pushes)],
        home: OverlayWindowsManager(
            child: UnifiedMainPageDesktop(_Main(manager)))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(UnifiedDesktopLayout), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('No chats yet'), findsOneWidget);
    pushes.clear();
    // Vommet issue 1010: with the list shown in full, Menu still opens
    // Settings directly (a page route), not the folded column's menu dialog.
    await tester.tap(find.byTooltip('Menu'));
    expect(pushes, hasLength(1));
    expect(pushes.single, isA<PageRouteBuilder>());
    expect(find.text('Archived chats'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('folded column Menu opens the Chats menu', (tester) async {
    // At a compact width beside a room, the layout shows the folded column,
    // whose Menu reaches its onMenu.
    tester.view.physicalSize = const Size(520, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var menus = 0;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
            body: UnifiedDesktopLayout(
                pane: PaneWidths.chatList,
                folderWidth: 0,
                hasRoom: true,
                navigation: const Text('full list'),
                compactNavigation:
                    FoldedChatColumn(rows: const [], onMenu: () => menus++),
                chatBuilder: (hidden, open) => const SizedBox()))));
    await tester.pumpAndSettle();
    expect(find.text('full list'), findsNothing);
    await tester.tap(find.byTooltip('Menu'));
    expect(menus, 1);

    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'vommet_now_playing': false});
    await app.preferences.init();
    await app.preferences.layoutOverride.set('desktop');
    final previous = app.clientManager;
    final manager = ClientManager()..callManager.playSounds = false;
    app.clientManager = manager;
    addTearDown(() => app.clientManager = previous);
    tester.view.physicalSize = const Size(440, 700);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: OverlayWindowsManager(
            child: UnifiedMainPageDesktop(_Main(manager)))));
    await tester.pumpAndSettle();
    // The folded column only shows beside an open room or space, which this
    // fake client manager cannot provide, so call its onMenu directly.
    final page = tester.state(find.byType(UnifiedMainPageDesktop));
    final menu = (page as dynamic).openFoldedMenu() as Future;
    await tester.pumpAndSettle();
    expect(find.text('Archived chats'), findsOneWidget);
    expect(find.text('Invitations'), findsOneWidget);
    await tester.tap(find.text('Archived chats'));
    await tester.pumpAndSettle();
    await menu;
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('folded desktop has one Search action and moves chat actions', (
    tester,
  ) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'vommet_now_playing': false});
    await app.preferences.init();
    await app.preferences.layoutOverride.set('desktop');
    final previous = app.clientManager;
    final manager = ClientManager()..callManager.playSounds = false;
    app.clientManager = manager;
    addTearDown(() => app.clientManager = previous);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeDark.theme,
        home: OverlayWindowsManager(
          child: UnifiedMainPageDesktop(_Main(manager)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Mount the real compact pane independently of the room view. The page
    // stays mounted as the owner of the navigation and dialog callbacks.
    final layout = tester.widget<UnifiedDesktopLayout>(
      find.byType(UnifiedDesktopLayout),
    );
    final overlay = tester.state<OverlayState>(find.byType(Overlay).first);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        width: 72,
        height: 440,
        child: Material(child: layout.compactNavigation),
      ),
    );
    overlay.insert(entry);
    addTearDown(() {
      if (entry.mounted) entry.remove();
      entry.dispose();
    });
    await tester.pumpAndSettle();
    final rail = find.byType(FoldedChatColumn);
    expect(
      find.descendant(of: rail, matching: find.byTooltip('Search')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.byTooltip('New chat')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: rail,
        matching: find.byIcon(Icons.bookmarks_outlined),
      ),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Chats menu'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Search'), findsNothing);
    final saved = find.widgetWithText(ListTile, 'Saved messages');
    expect(tester.widget<ListTile>(saved).enabled, isFalse);
    await tester.tap(find.text('New chat'));
    await tester.pumpAndSettle();
    expect(find.text('New direct message'), findsOneWidget);
    entry.remove();
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [72.0, 134.0, 149.0]) {
    testWidgets(
        'compact account controls fit $width without losing mute/settings',
        (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'vommet_now_playing': false});
      await app.preferences.init();
      await app.preferences.layoutOverride.set('desktop');
      final previous = app.clientManager;
      final manager = ClientManager()..callManager.playSounds = false;
      app.clientManager = manager;
      addTearDown(() => app.clientManager = previous);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: width,
                      child: const CurrentSessionPanel(compact: true))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(tester.getSize(find.byType(CurrentSessionPanel)).height,
          lessThanOrEqualTo(width >= 134 ? 100 : 150));
      expect(manager.callManager.isMuted, isFalse);
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();
      expect(manager.callManager.isMuted, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
