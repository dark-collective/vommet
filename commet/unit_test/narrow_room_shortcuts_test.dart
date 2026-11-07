import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/ui/layout/unified_desktop_layout.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/main/main_page_view_desktop.dart';
import 'package:commet/utils/room_list_navigation.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

// Supply the public room/client facts used by both the existing unread
// predicate and PR 1016's unread index. The production contract stays untouched.
class _Client extends Fake implements Client {
  @override
  T? getComponent<T extends Component>() => null;
  @override
  final NotifyingList<Room> rooms = NotifyingList.empty(growable: true);
  @override
  Stream<void> get onSync => const Stream.empty();
  @override
  Stream<Room> get onRoomAdded => const Stream.empty();
  @override
  Stream<Room> get onRoomRemoved => const Stream.empty();
}

final _client = _Client();

class _Room extends Fake implements Room {
  _Room(this.name, {this.notificationCount = 0});
  final String name;
  @override
  Client get client => _client;
  @override
  String get localId => name;
  @override
  Stream<void> get onUpdate => const Stream.empty();
  @override
  int get highlightedNotificationCount => 0;
  @override
  bool get messagesAreNoisy => false;
  @override
  final int notificationCount;
  @override
  PushRule get pushRule => PushRule.notify;
  @override
  String toString() => name;
}

class _Page extends Fake with Diagnosticable implements MainPageState {
  @override
  Room? get currentRoom => null;
}

const _composer = ValueKey('composer');
const _search = ValueKey('navigation-search');

Widget navigation(List<Room> rooms, {bool compact = false}) =>
    RoomListRegistration(
      rooms: () => rooms,
      child: Material(
        child: Column(children: [
          const TextField(key: _search),
          Text(compact ? 'compact rooms' : 'named rooms'),
        ]),
      ),
    );

// Exercise the production desktop responsive tree, substituting only the
// account/room contents. Registration is the widget used by room lists.
class _Desktop extends MainPageViewDesktop {
  _Desktop(this.rooms) : super(_Page());
  final List<Room> rooms;

  @override
  Widget sideColumn(BuildContext context,
          {required bool compact,
          double? width,
          bool collapsible = true,
          bool expandable = false}) =>
      SizedBox(
        width: width ??
            (compact
                ? ResponsiveDesktop.spaceBarWidth +
                    ResponsiveDesktop.compactListWidth
                : 320),
        child: navigation(rooms, compact: compact),
      );

  @override
  Widget mainView(BuildContext context, {bool sideHidden = false}) =>
      const Expanded(child: Material(child: TextField(key: _composer)));
}

void main() {
  final rooms = [
    _Room('first unread', notificationCount: 1),
    _Room('previous'),
    _Room('current'),
    _Room('next'),
    _Room('last unread', notificationCount: 1),
  ];
  Room? selected;
  bool handler(KeyEvent e) =>
      RoomListNavigation.handleKey(e, selected, (r) => selected = r);

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    ResponsiveDesktop.drawerOpen.value = false;
    ResponsiveDesktop.collapsed.value = false;
    selected = rooms[2];
    HardwareKeyboard.instance.addHandler(handler);
  });
  tearDown(() => HardwareKeyboard.instance.removeHandler(handler));

  Future<void> size(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 700);
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester, Widget child, double width,
      {double textScale = 1}) async {
    addTearDown(tester.view.reset);
    await size(tester, width);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: OverlayWindowsManager(child: child),
    ));
    await tester.pumpAndSettle();
  }

  final aliases = [
    (LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.altLeft, false, 1),
    (LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.altLeft, false, 3),
    (LogicalKeyboardKey.pageUp, LogicalKeyboardKey.controlLeft, false, 1),
    (LogicalKeyboardKey.pageDown, LogicalKeyboardKey.controlLeft, false, 3),
    (LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.altLeft, true, 0),
    (LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.altLeft, true, 4),
  ];

  Future<void> press(WidgetTester tester,
      (LogicalKeyboardKey, LogicalKeyboardKey, bool, int) alias) async {
    selected = rooms[2];
    await tester.sendKeyDownEvent(alias.$2);
    if (alias.$3) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(alias.$1);
    if (alias.$3) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(alias.$2);
    await tester.pump();
    expect(selected, rooms[alias.$4]);
  }

  for (final initialWidth in [480.0, 1000.0]) {
    testWidgets('classic aliases through hide/show; start $initialWidth',
        (tester) async {
      await pump(tester, _Desktop(rooms), initialWidth);
      for (final width in [initialWidth, 1000.0, 600.0, 480.0]) {
        await size(tester, width);
        await tester.tap(find.byKey(_composer));
        await tester.pump();
        for (final alias in aliases) {
          await press(tester, alias);
        }
        expect(find.byType(RoomListRegistration, skipOffstage: false),
            findsOneWidget);
      }
      // Hidden after compact retains that list until its named drawer opens.
      expect(find.text('compact rooms', skipOffstage: false), findsOneWidget);
      expect(find.byKey(_search), findsNothing);
      ResponsiveDesktop.drawerOpen.value = true;
      await tester.pumpAndSettle();
      expect(find.text('named rooms'), findsOneWidget);
      await tester.tap(find.byKey(_search));
      for (final alias in aliases) {
        await press(tester, alias);
      }
      EventBus.onSelectedRoomChanged.add(rooms.last);
      await tester.pumpAndSettle();
      expect(ResponsiveDesktop.drawerOpen.value, isFalse);
      expect(find.byKey(_search), findsNothing);
      expect(find.byType(RoomListRegistration, skipOffstage: false),
          findsOneWidget);
      await tester.tap(find.byKey(_composer));
      for (final alias in aliases) {
        await press(tester, alias);
      }
    });
  }

  testWidgets('hidden list retains state and current rooms at 200% text',
      (tester) async {
    final filtered = List<Room>.of(rooms);
    await pump(tester, _Desktop(filtered), 1000, textScale: 2);
    final search = find.byKey(_search);
    await tester.enterText(search, 'retained search');
    final before = tester.state(search);
    final editable = tester.widget<EditableText>(
        find.descendant(of: search, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue);
    await size(tester, 480);
    expect(editable.focusNode.hasFocus, isFalse);
    expect(
        tester.state(find.byKey(_search, skipOffstage: false)), same(before));
    await tester.tap(find.byKey(_composer));
    // Empty and filtered lists preserve the existing endpoint behavior.
    filtered.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(selected, rooms[2]);
    filtered.add(rooms.last);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(selected, rooms.last);
    selected = rooms[2];
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    expect(selected, rooms.last);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await size(tester, 1000);
    expect(tester.state(find.byKey(_search)), same(before));
    expect(find.text('retained search'), findsOneWidget);
  });

  testWidgets('mobile offstage panel keeps aliases through reveal/hide',
      (tester) async {
    final key = GlobalKey<OverlappingPanelsState>();
    await pump(
        tester,
        OverlappingPanels(
          key: key,
          left: navigation(rooms),
          main: const Material(child: TextField(key: _composer)),
        ),
        400);
    for (final side in [RevealSide.main, RevealSide.left, RevealSide.main]) {
      key.currentState!.reveal(side);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(side == RevealSide.left ? _search : _composer));
      for (final alias in aliases) {
        await press(tester, alias);
      }
    }
  });

  testWidgets('unified shell keeps aliases through hide/show/resize',
      (tester) async {
    final key = GlobalKey<UnifiedDesktopLayoutState>();
    await pump(
        tester,
        UnifiedDesktopLayout(
          key: key,
          pane: PaneWidths.chatList,
          folderWidth: 77,
          hasRoom: true,
          navigation: navigation(rooms),
          compactNavigation: const Text('avatars'),
          chatBuilder: (hidden, open) =>
              const Material(child: TextField(key: _composer)),
        ),
        440);
    for (final width in [440.0, 1100.0, 650.0, 440.0]) {
      await size(tester, width);
      await tester.tap(find.byKey(_composer));
      for (final alias in aliases) {
        await press(tester, alias);
      }
    }
    key.currentState!.showNavigation();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_search));
    for (final alias in aliases) {
      await press(tester, alias);
    }
    key.currentState!.closeNavigation();
    await tester.pumpAndSettle();
    for (final alias in aliases) {
      await press(tester, alias);
    }
  });
}
