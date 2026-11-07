// Vommet issue 1100: drive the real folded Search and Chats actions.
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/ui/layout/unified_desktop_layout.dart';
import 'package:commet/ui/organisms/bookmarks/home_saved_messages.dart';
import 'package:commet/ui/organisms/bookmarks/saved_messages.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_main_page.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'helpers/unread_fixtures.dart';
import 'home_saved_messages_test.dart' show SavedAccountClient;
import 'support/room_page_fixtures.dart' as rooms;

class _Main extends Fake with Diagnosticable implements MainPageState {
  _Main(this.clientManager, {this.currentRoom});
  @override
  final ClientManager clientManager;
  @override
  final Room? currentRoom;
  @override
  Client? get filterClient => null;
  @override
  Profile? get currentUser => null;
  @override
  bool get showAsTextRoom => false;
}

class _Account extends SavedAccountClient {
  _Account(super.identifier, super.name);
  final _dms = UnreadDms();
  @override
  T? getComponent<T extends Component>() => _dms is T ? _dms as T : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(const EventChannel('FlutterWebRTC.Event'),
            MockStreamHandler.inline(onListen: (_, __) {}));
  });
  Future<ClientManager> pumpMenu(WidgetTester tester,
      {bool mountCompact = true}) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'vommet_now_playing': false});
    await app.preferences.init();
    await app.preferences.layoutOverride.set('desktop');
    final previous = app.clientManager;
    final manager = ClientManager()..callManager.playSounds = false;
    app.clientManager = manager;
    addTearDown(() => app.clientManager = previous);
    tester.view.physicalSize = const Size(880, 696);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget? compact;
    late StateSetter showCompact;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: StatefulBuilder(builder: (context, setState) {
        showCompact = setState;
        return Stack(children: [
          OverlayWindowsManager(child: UnifiedMainPageDesktop(_Main(manager))),
          if (compact != null)
            Positioned(
                left: 0,
                top: 0,
                width: 72,
                bottom: 0,
                child: Material(child: compact!)),
        ]);
      }),
    ));
    await tester.pumpAndSettle();
    if (!mountCompact) return manager;
    final shell =
        tester.widget<UnifiedDesktopLayout>(find.byType(UnifiedDesktopLayout));
    showCompact(() => compact = shell.compactNavigation);
    await tester.pumpAndSettle();
    return manager;
  }

  for (final count in [1, 2]) {
    testWidgets(
        'compact Chats Saved messages opens for $count eligible accounts',
        (tester) async {
      final manager = await pumpMenu(tester);
      final a = _Account('@alex:personal.example', 'Personal');
      final b = _Account('@alex:work.example', 'Work');
      manager.clients.addAll([a, if (count == 2) b]);
      await tester.pumpAndSettle();
      // Use the real folded column's callback on the base as well, where
      // the tooltip is still Menu, so failure is the missing menu entry.
      final column =
          tester.widget<FoldedChatColumn>(find.byType(FoldedChatColumn));
      column.onMenu!();
      await tester.pumpAndSettle();
      final action = find.widgetWithText(ListTile, 'Saved messages');
      expect(action, findsOneWidget);
      expect(tester.widget<ListTile>(action).enabled, isTrue);
      await tester.tap(action);
      await tester.pumpAndSettle();
      if (count == 2) {
        expect(find.text(HomeSavedMessages.chooseAccount), findsOneWidget);
        expect(find.text(a.identifier), findsOneWidget);
        expect(find.text(b.identifier), findsOneWidget);
        await tester.tap(find.text(b.identifier));
        await tester.pumpAndSettle();
      } else {
        expect(find.text(HomeSavedMessages.chooseAccount), findsNothing);
      }
      expect(tester.widget<SavedMessages>(find.byType(SavedMessages)).client,
          same(count == 1 ? a : b));
      expect(find.text(SavedMessages.labelNoSavedMessages), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('compact Saved messages availability updates in the open menu',
      (tester) async {
    final manager = await pumpMenu(tester);
    tester.widget<FoldedChatColumn>(find.byType(FoldedChatColumn)).onMenu!();
    await tester.pumpAndSettle();
    final action = find.widgetWithText(ListTile, 'Saved messages');
    expect(action, findsOneWidget);
    expect(tester.widget<ListTile>(action).enabled, isFalse);
    manager.clients.add(_Account('@alex:example.org', 'Alex'));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(action).enabled, isTrue);
    expect(find.text(HomeSavedMessages.unavailable), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('companion column menu retains Search without compact actions',
      (tester) async {
    await pumpMenu(tester, mountCompact: false);
    final dynamic page = tester.state(find.byType(UnifiedMainPageDesktop));
    // Supply a space model at the source boundary, then open it through
    // the page's normal navigation so listPane builds the companion rail.
    page.source.spaces['space'] = const SpaceEntry(
        key: 'space', spaceId: '!space:example.org', name: 'Studio');
    page.nav.openRoot('space');
    await tester.pumpAndSettle();
    final rail = find.byType(FoldedChatColumn);
    await tester
        .tap(find.descendant(of: rail, matching: find.byTooltip('Menu')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Search'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'New chat'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Saved messages'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('real folded Search returns focus after Enter and Escape',
      (tester) async {
    await tester.runAsync(rooms.roomPageSetUp);
    addTearDown(rooms.roomPageTearDown);
    await app.preferences.layoutOverride.set('desktop');
    await unifiedListCollapsed.set(true);
    tester.view.physicalSize = const Size(880, 696);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: OverlayWindowsManager(
          child: UnifiedMainPageDesktop(
        _Main(app.clientManager!,
            currentRoom: rooms.roomFor(rooms.RoomCase.empty)),
      )),
    ));
    await rooms.settle(tester);
    final rail = find.byType(FoldedChatColumn);
    final button =
        find.descendant(of: rail, matching: find.byTooltip('Search'));
    expect(button, findsOneWidget);
    final icon =
        find.descendant(of: button, matching: find.byIcon(Icons.search));
    final trigger = Focus.of(tester.element(icon));
    trigger.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await rooms.settle(tester);
    final layout = tester
        .state<UnifiedDesktopLayoutState>(find.byType(UnifiedDesktopLayout));
    expect(layout.drawerOpen, isTrue);
    expect(
        FocusManager.instance.primaryFocus?.debugLabel, 'Unified chat search');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await rooms.settle(tester);
    expect(layout.drawerOpen, isFalse);
    expect(trigger.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await rooms.finishRoomPage(tester);
  });
}
