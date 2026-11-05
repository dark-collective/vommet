import 'dart:convert';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/room_layout_options.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/ui/atoms/sidebar_room_icon.dart';
import 'package:commet/ui/atoms/space_list.dart';
import 'package:commet/ui/molecules/compact_room_list.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/space_summary/space_summary_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_main_page.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'package:commet/ui/pages/room_info/space_info_page.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'roomlist_fixture.dart';

const parent = '!garden:example.com';
const a = '!a:example.com';
const b = '!b:example.com';
const orderType = 'im.nether.chat.space_child_order';

class _Main extends Fake with Diagnosticable implements MainPageState {
  _Main(this.clientManager, this.currentSpace);
  @override
  final ClientManager clientManager;
  @override
  final Space currentSpace;
  @override
  MainPageSubView get currentView => MainPageSubView.space;
  @override
  Client? get filterClient => null;
  @override
  Room? get currentRoom => null;
  @override
  bool get showAsTextRoom => false;
  @override
  Profile? get currentUser => null;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(const EventChannel('FlutterWebRTC.Event'),
            MockStreamHandler.inline(onListen: (_, __) {}));
  });
  late MatrixSpace space;
  late _Main main;
  late Future<void> Function(List<String>) receive;
  late List<http.Request> writes;
  var reject = false;
  var nextClient = 0;
  Future<void> setup(WidgetTester tester,
      {LayoutStyle style = LayoutStyle.discord,
      bool desktop = true,
      bool admin = true,
      bool empty = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize =
        desktop ? const Size(1280, 900) : const Size(390, 900);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'vommet_now_playing': false});
      await preferences.init();
      await pickLayoutStyle(style);
      await preferences.layoutOverride.set(desktop ? 'desktop' : 'mobile');
      await experimentRoomInfoPage.set(true);
      final client = await signedInClient('personal-view-${nextClient++}');
      final mx = client.getMatrixClient();
      await mx.abortSync();
      final previous = clientManager, previousTasks = backgroundTaskManager;
      backgroundTaskManager = BackgroundTaskManager();
      final manager = ClientManager()..callManager.playSounds = false;
      clientManager = manager;
      manager.addClient(client);
      addTearDown(() async {
        clientManager = previous;
        backgroundTaskManager = previousTasks;
        await mx.dispose(closeDatabase: true);
      });
      writes = [];
      reject = false;
      final server = mx.httpClient;
      mx.httpClient = MockClient((request) async {
        if (request.method != 'PUT') {
          return http.Response.fromStream(
              await server.send(http.Request(request.method, request.url)
                ..headers.addAll(request.headers)
                ..bodyBytes = request.bodyBytes));
        }
        writes.add(request);
        return http.Response(
            reject
                ? '{"errcode":"M_FORBIDDEN","error":"Denied"}'
                : '{"event_id":"\$saved"}',
            reject ? 403 : 200,
            headers: {'content-type': 'application/json'});
      });
      await sync(client, join: {
        parent: matrix.JoinedRoomUpdate(state: [
          ...roomState(parent, children: empty ? [] : [a, b], name: 'Garden'),
          stateEvent('m.room.power_levels', {
            'users': {me: admin ? 100 : 0},
            'state_default': 50
          }),
        ]),
        a: joined(a, name: 'Alpha'),
        b: joined(b, name: 'Beta'),
      });
      space = client.getSpace(parent) as MatrixSpace;
      await space.loadExtra();
      main = _Main(manager, space);
      receive = (order) => sync(client, join: {
            parent: matrix.JoinedRoomUpdate(accountData: [
              matrix.BasicEvent(type: orderType, content: {'order': order}),
            ]),
          });
      await receive([b, a]);
    });
  }

  Future<void> pump(WidgetTester t, Widget child, {double scale = 1}) async {
    await t.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        builder: (context, body) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: body!),
        home: OverlayWindowsManager(child: child)));
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester t, {double scale = 1}) async {
    late List<SpaceMenuEntry> entries;
    await pump(t, Scaffold(body: Builder(builder: (context) {
      entries = SpaceMenu.entries(context, space);
      return TextButton(
          onPressed: () => entries
              .firstWhere((e) => e.label == 'Arrange for me')
              .onSelected(),
          child: const Text('Open arrangement'));
    })), scale: scale);
    final labels = entries.map((e) => e.label);
    expect(labels, contains('Arrange for me'));
    if (!space.permissions.canEditChildren) {
      expect(labels, isNot(contains('Change default for everyone')));
    }
    await tap(t, find.text('Open arrangement'));
    expect(find.text('Arrange for me'), findsOneWidget);
  }

  void expectOrder(WidgetTester t, Finder first, Finder second) {
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(t.getTopLeft(first).dy, lessThan(t.getTopLeft(second).dy));
  }

  Widget summary() => SingleChildScrollView(
      child: SpaceSummaryView(space: space, displayName: 'Garden'));

  for (final style in LayoutStyle.values) {
    for (final desktop in [false, true]) {
      for (final view in ['classic', 'compact', 'summary', 'unified']) {
        testWidgets(
            '$view follows saved and synced order ($style, desktop=$desktop)',
            (t) async {
          await setup(t, style: style, desktop: desktop);
          final Widget widget = switch (view) {
            'classic' => SpaceList(space),
            'compact' => SizedBox(width: 56, child: CompactRoomList(main)),
            'summary' => summary(),
            _ => desktop
                ? UnifiedMainPageDesktop(main)
                : UnifiedMainPageMobile(main),
          };
          await pump(t, Scaffold(body: widget));
          if (view == 'unified') await tap(t, find.text('Garden'));
          Finder row(String id, String label) => switch (view) {
                'compact' => find.byWidgetPredicate(
                    (w) => w is SidebarRoomIcon && w.room.identifier == id),
                'summary' || 'classic' => find.byWidgetPredicate((w) =>
                    w is RoomPanel && w.room.identifier == id ||
                    w is RoomTextButton && w.room.identifier == id),
                _ => find.text(label),
              };
          final alpha = row(a, 'Alpha'), beta = row(b, 'Beta');
          expectOrder(t, beta, alpha);
          await t.runAsync(() => receive([a, b]));
          await t.pump(const Duration(milliseconds: 200));
          await t.pumpAndSettle();
          expectOrder(t, alpha, beta);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        });
      }

      testWidgets(
          'unified header opens scoped menu and space info ($style, desktop=$desktop)',
          (t) async {
        await setup(t, style: style, desktop: desktop);
        await preferences.experimentManageSpaceRooms.set(true);
        await pump(
            t,
            desktop
                ? UnifiedMainPageDesktop(main)
                : UnifiedMainPageMobile(main));
        await tap(t, find.text('Garden'));
        final connectionBadge = find.text('Error connecting...');
        if (connectionBadge.evaluate().isNotEmpty)
          await tap(t, connectionBadge);
        await tap(t, find.byTooltip('Space options'));
        expect(find.text('Arrange for me'), findsOneWidget);
        expect(find.text('Change default for everyone'), findsOneWidget);
        await tap(t, find.text('Space settings'));
        expect(find.byType(SpaceInfoPage), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('shared summary mode enters, cancels and saves room state',
      (t) async {
    await setup(t);
    await preferences.experimentManageSpaceRooms.set(false);
    await spaceHomeLikeRoomList.set(true);
    await pump(t, Scaffold(body: summary()));
    final edit = find.text('Change default for everyone');
    expectOrder(t, find.text('Beta'), find.text('Alpha'));
    await tap(t, edit);
    expectOrder(t, find.text('Alpha'), find.text('Beta'));
    await tap(t, find.text('Cancel changing default for everyone'));
    expect(writes, isEmpty);
    expectOrder(t, find.text('Beta'), find.text('Alpha'));
    await tap(t, edit);
    t
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorder(0, 2);
    await t.pumpAndSettle();
    await tap(t, find.byIcon(Icons.save));
    expect(writes.map((r) => Uri.decodeComponent(r.url.path)), [
      endsWith('/state/m.space.child/$b'),
      endsWith('/state/m.space.child/$a')
    ]);
    final orders = writes.map((r) => jsonDecode(r.body)['order'] as String);
    expect(orders.first.compareTo(orders.last), lessThan(0));
    expect(edit, findsOneWidget);
    expect(find.text('Cancel changing default for everyone'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'member arranges, retries and resets using only self account data',
      (t) async {
    await setup(t, desktop: false, admin: false);
    await preferences.experimentManageSpaceRooms.set(true);
    await openEditor(t, scale: 2);
    final semantics = t.ensureSemantics();
    final move = find.byTooltip('Move Alpha up or down');
    await t.ensureVisible(move);
    try {
      expect(find.bySemanticsLabel(RegExp('Alpha, position 2 of 2')),
          findsOneWidget);
    } finally {
      semantics.dispose();
    }
    await tap(t, move);
    await tap(t, find.text('Move up'));
    expect(writes, isEmpty);
    reject = true;
    await tap(t, find.text('Save'));
    expect(find.textContaining('Could not save'), findsOneWidget);
    reject = false;
    await t.drag(find.byType(ReorderableListView), const Offset(0, -280));
    await t.pumpAndSettle();
    await tap(t, find.text('Retry'));
    expect(find.text('Personal order saved'), findsOneWidget);
    expect(jsonDecode(writes.last.body)['order'], [a, b]);
    await tap(t, find.text('Reset to space default'));
    expect(find.text('Space default · preview'), findsOneWidget);
    await tap(t, find.text('Cancel'));
    expect(writes, hasLength(2));
    await tap(t, find.text('Reset to space default'));
    await tap(t, find.text('Save reset'));
    expect(jsonDecode(writes.last.body), isEmpty);
    expect(
        writes.map((r) => Uri.decodeComponent(r.url.path)),
        everyElement(
            endsWith('/user/$me/rooms/$parent/account_data/$orderType')));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('empty space still opens personal arrangement', (t) async {
    await setup(t, empty: true);
    await openEditor(t);
    expect(find.text('No rooms or subspaces yet.'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('incoming order blocks saving an unsaved arrangement', (t) async {
    await setup(t);
    await openEditor(t);
    await tap(t, find.byTooltip('Move Alpha up or down'));
    await tap(t, find.text('Move up'));
    await t.runAsync(() => receive([a, b]));
    await t.pumpAndSettle();
    expect(find.textContaining('changed elsewhere'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(writes, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
}
