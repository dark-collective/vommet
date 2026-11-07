import 'dart:io';
import 'dart:ui' as ui;

import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/room_layout_options.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/rail_pill.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_overview.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:commet/ui/organisms/side_navigation_bar/side_navigation_bar_direct_messages.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_main_page.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/main/main_page_view_desktop.dart';
import 'package:commet/ui/pages/main/main_page_view_mobile.dart';
import 'package:commet/utils/app_localizations.dart';
import 'package:commet/utils/bridged_users.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_light.dart';

import 'helpers/navigation_fixture.dart';
import 'roomlist_fixture.dart';

const dm = '!mina:example.com';
const mina = '@mina:example.com';
const _captureDirectory = String.fromEnvironment('VOMMET_1250_CAPTURES');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MatrixClient client;
  late MatrixClient invitedClient;
  late ClientManager manager;

  void showOnlyRecent() {
    final store = HomeLayoutStore.instance..attach(manager);
    final overview = store.tabs.value.tab(HomeTabs.overview)!;
    final layout = HomeLayout([
      overview.main.cards.firstWhere((card) => card.type == HomeLayout.recent),
    ]);
    store.tabs.value =
        store.tabs.value.replaceTab(overview.copyWith(main: layout));
    store.layout.value = layout;
  }

  setUpAll(() async {
    if (_captureDirectory.isNotEmpty) {
      final flutter = Platform.environment['FLUTTER_ROOT']!;
      for (final (name, path) in [
        ('RobotoCustom', 'assets/font/roboto/Roboto-Regular.ttf'),
        (
          'MaterialIcons',
          '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
        ),
      ]) {
        final loader = FontLoader(name)
          ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
        await loader.load();
      }
    }
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await app.preferences.init();
    await app.preferences.checkForUpdates.set(false);
    await BridgedUsers.mark.set(false);
    await experimentNewHome.set(true);
    await peopleInRail.set(true);
    await homeBadgeCountsDms.set(true);
    client = await signedInClient('new-home-placement');
    await sync(client, join: {
      dm: joined(dm, name: 'Mina')
    }, accountData: [
      directChats({
        mina: [dm]
      })
    ]);
    await sync(client, join: {
      dm: matrix.JoinedRoomUpdate(
        unreadNotifications: matrix.UnreadNotificationCounts(
            notificationCount: 2, highlightCount: 2),
        timeline: matrix.TimelineUpdate(events: [
          for (var i = 1; i <= 2; i++)
            matrix.MatrixEvent(
                type: 'm.room.message',
                content: {'msgtype': 'm.text', 'body': 'Message $i from Mina'},
                senderId: mina,
                eventId: '\$mina-$i',
                originServerTs:
                    DateTime.fromMillisecondsSinceEpoch(1700000000000 + i)),
        ]),
      ),
    });
    manager = ClientManager()..callManager.playSounds = false;
    manager.addClient(client);
    app.clientManager = manager;
    newHomeTab.value = HomeTabs.overview;
    showOnlyRecent();
    invitedClient = await signedInClient('new-home-placement-invites');
    matrix.InvitedRoomUpdate invite({required bool direct}) =>
        matrix.InvitedRoomUpdate(inviteState: [
          matrix.StrippedStateEvent(
              type: 'm.room.member',
              stateKey: me,
              senderId: mina,
              content: {'membership': 'invite', 'is_direct': direct}),
        ]);
    await sync(invitedClient, invite: {
      '!direct-invite:example.com': invite(direct: true),
      '!room-invite:example.com': invite(direct: false),
    });
  });

  tearDownAll(() async {
    app.clientManager = null;
    await client.getMatrixClient().dispose(closeDatabase: true);
    await invitedClient.getMatrixClient().dispose(closeDatabase: true);
  });

  Finder peopleRailSlot() => find.ancestor(
        of: find.byKey(NewHomeRailShortcuts.peopleKey),
        matching: find.byWidgetPredicate((widget) =>
            widget is Stack && widget.children.any((c) => c is RailSlot)),
      );

  Finder within(Finder parent, String label) =>
      find.descendant(of: parent, matching: find.text(label));

  Future<void> capture(
      WidgetTester tester, GlobalKey boundary, String file) async {
    if (_captureDirectory.isEmpty) return;
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('$_captureDirectory/$file.png')
          .writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<GlobalKey> pumpHome(WidgetTester tester,
      {required bool phone, required ThemeData theme}) async {
    tester.view.physicalSize =
        phone ? const Size(390, 844) : const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await app.preferences.layoutOverride.set(phone ? 'mobile' : 'desktop');
    final boundary = GlobalKey();
    final state =
        NavigationPageFixture(manager, currentView: MainPageSubView.home);
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.delegates,
        debugShowCheckedModeBanner: false,
        theme: _captureDirectory.isEmpty
            ? theme
            : theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'RobotoCustom')),
        home: Provider<ClientManager>.value(
          value: manager,
          child: OverlayWindowsManager(
            child: Scaffold(
              body: phone
                  ? MainPageViewMobile(state)
                  : MainPageViewDesktop(state),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return boundary;
  }

  for (final phone in [false, true]) {
    for (final (name, theme) in [
      ('dark', ThemeDark.theme),
      ('light', ThemeLight.theme),
      ('amoled', ThemeAmoled.theme),
    ]) {
      testWidgets(
          'two unread DMs show at the approved surfaces ($name, phone=$phone)',
          (tester) async {
        await pickLayoutStyle(LayoutStyle.discord);
        final boundary = await pumpHome(tester, phone: phone, theme: theme);
        final overview = find.byType(NewHomeOverview);
        if (phone) {
          tester
              .state<OverlappingPanelsState>(find.byType(OverlappingPanels))
              .reveal(RevealSide.main);
          await tester.pumpAndSettle();
        }
        final recent = within(overview, '2').evaluate().length;
        final recentBadges = find
            .descendant(of: overview, matching: find.byType(NotificationBadge))
            .evaluate()
            .length;
        if (phone) {
          await capture(tester, boundary, '$name-phone-overview');
          tester
              .state<OverlappingPanelsState>(find.byType(OverlappingPanels))
              .reveal(RevealSide.left);
          await tester.pumpAndSettle();
        }
        await capture(
            tester, boundary, '$name-${phone ? 'phone-list' : 'desktop'}');

        final rail = find.byType(SideNavigationBar);
        final avatars = find.byType(SideNavigationBarDirectMessages);
        final people = peopleRailSlot();
        final column = find.byType(NewHomeColumn);
        final header = find.byType(SideListSectionHeader);
        expect(rail, findsOneWidget);
        expect(within(rail, '2'), findsOneWidget);
        expect(within(people, '2'), findsNothing);
        expect(within(avatars, '2'), findsNothing);
        expect(
            find.descendant(
                of: avatars, matching: find.byType(NotificationBadge)),
            findsOneWidget);
        expect(within(header, '2'), findsNothing);
        expect(within(column, '2'), findsOneWidget);
        expect(recent, 0);
        expect(recentBadges, 1);
        if (name == 'dark') {
          await pickLayoutStyle(LayoutStyle.custom);
          await tester.pumpAndSettle();
          expect(within(column, '2'), findsOneWidget);
          await pickLayoutStyle(LayoutStyle.telegram);
          await pumpHome(tester, phone: phone, theme: theme);
          final unified = phone
              ? find.byType(UnifiedMainPageMobile)
              : find.byType(UnifiedMainPageDesktop);
          expect(unified, findsOneWidget);
          expect(rail, findsNothing);
          await pickLayoutStyle(LayoutStyle.custom);
          await tester.pumpAndSettle();
          expect(unified, findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'the DM header counts collapsed rows only, even without the Home DM total',
      (tester) async {
    await pickLayoutStyle(LayoutStyle.discord);
    await homeBadgeCountsDms.set(false);
    await peopleInRail.set(false);
    await pumpHome(tester, phone: false, theme: ThemeDark.theme);
    final rail = find.byType(SideNavigationBar);
    final header = find.byType(SideListSectionHeader);
    expect(find.byKey(NewHomeRailShortcuts.peopleKey), findsNothing);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(within(header, '2'), findsOneWidget);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(within(header, '2'), findsNothing);
    expect(within(rail, '2'), findsNothing);
    await experimentNewHome.set(false);
    await tester.pumpAndSettle();
    expect(within(find.byType(SideNavigationBarDirectMessages), '2'),
        findsOneWidget);
    await experimentNewHome.set(true);
    await peopleInRail.set(true);
    await homeBadgeCountsDms.set(true);
    await tester.pumpAndSettle();
  });

  testWidgets('People shows received DM invites for the selected account only',
      (tester) async {
    await pickLayoutStyle(LayoutStyle.discord);
    await peopleInRail.set(true);
    await homeBadgeCountsDms.set(true);
    manager = ClientManager()..callManager.playSounds = false;
    // The first manager already owns the DM client's single-subscription call
    // stream. Only its existing aggregate unread data is needed here.
    manager.addClient(invitedClient);
    manager.clients.add(client);
    app.clientManager = manager;
    showOnlyRecent();
    await pumpHome(tester, phone: false, theme: ThemeDark.theme);
    await tester.pump(const Duration(milliseconds: 500));
    final railPeople = peopleRailSlot();
    final columnPeople = find.byKey(const ValueKey('NewHomeRowPeopleBadge'));
    expect(within(railPeople, '1'), findsOneWidget);
    expect(within(columnPeople, '1'), findsOneWidget);
    EventBus.setFilterClient.add(client);
    await tester.pumpAndSettle();
    expect(within(railPeople, '1'), findsNothing);
    expect(columnPeople, findsNothing);
    EventBus.setFilterClient.add(null);
    await tester.pumpAndSettle();
    expect(within(railPeople, '1'), findsOneWidget);
  });
}
