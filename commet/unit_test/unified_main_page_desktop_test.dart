import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/ui/pages/main/main_page_view_desktop.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/ui/layout/unified_desktop_layout.dart';
import 'package:commet/ui/molecules/current_session_panel.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
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
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: OverlayWindowsManager(
            child: UnifiedMainPageDesktop(_Main(manager)))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(UnifiedDesktopLayout), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('No chats yet'), findsOneWidget);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Archived chats'), findsOneWidget);
    expect(find.text('Invitations'), findsOneWidget);
    await tester.tap(find.text('Archived chats'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
