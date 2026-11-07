import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/ui/layout/unified_desktop_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PaneWidth pane;
  var outerEscapes = 0;
  setUp(() async {
    outerEscapes = 0;
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    pane = PaneWidth(DoublePreference('unified_test_width', defaultValue: 400),
        min: 280, max: 640, resizableWhen: () => true);
  });

  for (final folders in [0.0, 77.0]) {
    test('fits chat and recovers with hysteresis; folders=$folders', () {
      DesktopSideColumn fit(double width,
              {DesktopSideColumn? previous, bool collapsed = false}) =>
          UnifiedDesktopFit.column(width, folders,
              minimumListWidth: 280, collapsed: collapsed, previous: previous);
      expect(fit(680 + folders), DesktopSideColumn.full);
      expect(fit(679 + folders), DesktopSideColumn.compact);
      expect(fit(472 + folders), DesktopSideColumn.compact);
      expect(fit(471 + folders), DesktopSideColumn.hidden);
      expect(fit(680 + folders, previous: DesktopSideColumn.compact),
          DesktopSideColumn.compact);
      expect(fit(704 + folders, previous: DesktopSideColumn.compact),
          DesktopSideColumn.full);
      expect(fit(472 + folders, previous: DesktopSideColumn.hidden),
          DesktopSideColumn.hidden);
      expect(fit(496 + folders, previous: DesktopSideColumn.hidden),
          DesktopSideColumn.compact);
      expect(fit(1600, collapsed: true), DesktopSideColumn.compact);
      expect(fit(450, collapsed: true), DesktopSideColumn.hidden);
    });
  }

  test('drag starts at fitted width, collapse retains saved width', () async {
    pane.beginDrag(300);
    pane.drag(-79);
    expect(pane.pulledPastMin.value, isFalse);
    pane.drag(-2);
    expect(pane.pulledPastMin.value, isTrue);
    pane.endCollapsed();
    expect(pane.value, 400);
    expect(pane.preference.value, 400);
    pane.beginDrag(300);
    pane.drag(25);
    await pane.save();
    expect(pane.preference.value, 325);
  });

  final fullKey = GlobalKey();
  final layoutKey = GlobalKey<UnifiedDesktopLayoutState>();
  final search = TextEditingController();
  final chatFocus = FocusNode();
  final searchFocus = FocusNode();
  tearDown(() {
    search.clear();
  });
  tearDownAll(() {
    search.dispose();
    chatFocus.dispose();
    searchFocus.dispose();
  });
  Future<void> pump(WidgetTester tester, double width,
      {bool room = true}) async {
    tester.view.physicalSize = Size(width, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CallbackShortcuts(
                bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              outerEscapes++,
        },
                child: UnifiedDesktopLayout(
                  key: layoutKey,
                  pane: pane,
                  folderWidth: 77,
                  hasRoom: room,
                  navigation: SizedBox(
                      key: fullKey,
                      child: Column(children: [
                        TextField(
                            key: const ValueKey('search'),
                            controller: search,
                            focusNode: searchFocus),
                        Expanded(
                            child: ListView.builder(
                                key: const PageStorageKey('test-list'),
                                itemCount: 100,
                                itemBuilder: (_, i) =>
                                    ListTile(title: Text('Chat $i')))),
                      ])),
                  compactNavigation: const Center(child: Text('avatars')),
                  chatBuilder: (hidden, open) => Column(children: [
                    if (hidden)
                      IconButton(
                          tooltip: 'Open chats',
                          onPressed: open,
                          icon: const Icon(Icons.menu)),
                    TextField(
                        key: const ValueKey('composer'), focusNode: chatFocus),
                  ]),
                )))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final transition in ['setCollapsed', 'resize']) {
    testWidgets(
        'drawer focus survives $transition without a stale return target',
        (tester) async {
      await unifiedListCollapsed.set(true);
      await pump(tester, 1050);
      chatFocus.requestFocus();
      await tester.pumpAndSettle();
      layoutKey.currentState!.showNavigation();
      await tester.pumpAndSettle();
      searchFocus.requestFocus();
      await tester.pumpAndSettle();
      if (transition == 'setCollapsed') {
        layoutKey.currentState!.setCollapsed(true);
      } else {
        // Expanding to full navigation closes the overlay. Folding again
        // must hand focus off when the named navigation disappears.
        await unifiedListCollapsed.set(false);
        layoutKey.currentState!.setCollapsed(false);
        await pump(tester, 1200);
        await pump(tester, 650);
      }
      await tester.pumpAndSettle();
      expect(layoutKey.currentState!.drawerOpen, isFalse);
      expect(chatFocus.hasFocus, isTrue);
      expect(searchFocus.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(chatFocus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('full, compact, hidden, overlay; keep search and scroll state',
      (tester) async {
    await pump(tester, 1050);
    expect(tester.getSize(find.byKey(fullKey)).width, 477);
    await tester.enterText(find.byKey(const ValueKey('search')), 'remember me');
    final list = find.descendant(
        of: find.byKey(fullKey), matching: find.byType(ListView));
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)));
    final offset = scroll.position.pixels;
    await pump(tester, 650);
    expect(find.text('avatars'), findsOneWidget);
    expect(find.byKey(fullKey), findsNothing);
    expect(find.byKey(fullKey, skipOffstage: false), findsOneWidget);
    expect(search.text, 'remember me');
    expect(scroll.position.pixels, offset);
    expect(unifiedListCollapsed.hasStoredValue, isFalse);
    await pump(tester, 520);
    expect(find.text('avatars'), findsNothing);
    chatFocus.requestFocus();
    await tester.pump();
    await tester.tap(find.byTooltip('Open chats'));
    await tester.pumpAndSettle();
    expect(find.byKey(fullKey), findsOneWidget);
    expect(tester.getSize(find.byKey(fullKey)).width, 472);
    expect(chatFocus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(fullKey), findsNothing);
    await pump(tester, 1050);
    expect(search.text, 'remember me');
    expect(scroll.position.pixels, offset);
    expect(unifiedListCollapsed.hasStoredValue, isFalse);
  });

  testWidgets(
      'manual drag collapse persists on widening and expands by dragging',
      (tester) async {
    await pump(tester, 800);
    // Displayed width is 323, although the preference is still 400.
    final handle = find.byType(PaneResizeHandle);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-110, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('avatars'), findsOneWidget);
    expect(unifiedListCollapsed.value, isTrue);
    expect(pane.value, 400);
    await pump(tester, 1300);
    expect(find.text('avatars'), findsOneWidget);
    await tester.drag(find.byType(CollapsedPaneHandle), const Offset(65, 0));
    await tester.pumpAndSettle();
    expect(find.text('avatars'), findsNothing);
    expect(unifiedListCollapsed.value, isFalse);
    expect(tester.getSize(find.byKey(fullKey)).width, 477);
  });

  testWidgets(
      'keyboard collapse, hidden reveal and reset do not alter classic choice',
      (tester) async {
    await ResponsiveDesktop.setCollapsed(false);
    await pump(tester, 1050);
    Future<void> toggle() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await toggle();
    expect(find.text('avatars'), findsOneWidget);
    expect(ResponsiveDesktop.collapsed.value, isFalse);
    await toggle();
    expect(find.text('avatars'), findsNothing);
    await pump(tester, 500);
    await toggle();
    expect(layoutKey.currentState!.drawerOpen, isTrue);
    await toggle();
    expect(layoutKey.currentState!.drawerOpen, isFalse);
    await pump(tester, 1100);
    layoutKey.currentState!.setCollapsed(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CollapsedPaneHandle));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byType(CollapsedPaneHandle));
    await tester.pumpAndSettle();
    expect(pane.value, 400);
    expect(unifiedListCollapsed.value, isFalse);
  });

  testWidgets('no room at narrow widths keeps usable full-page navigation',
      (tester) async {
    await pump(tester, 440, room: false);
    expect(tester.getSize(find.byKey(fullKey)).width, 440);
    expect(find.byKey(const ValueKey('search')), findsOneWidget);
    expect(find.byType(PaneResizeHandle), findsNothing);
  });

  testWidgets('opening then widening closes overlay; room selection closes it',
      (tester) async {
    await pump(tester, 520);
    layoutKey.currentState!.showNavigation();
    await tester.pumpAndSettle();
    await pump(tester, 650);
    expect(layoutKey.currentState!.drawerOpen, isFalse);
    layoutKey.currentState!.showNavigation();
    await tester.pumpAndSettle();
    layoutKey.currentState!.closeNavigation(roomOpened: true);
    await tester.pumpAndSettle();
    expect(layoutKey.currentState!.drawerOpen, isFalse);
    expect(searchFocus.hasFocus, isFalse);
    expect(
        FocusManager.instance.primaryFocus?.debugLabel, 'Unified conversation');
  });
  testWidgets(
      'real window widening releases Escape after automatic overlay dismissal',
      (tester) async {
    await pump(tester, 520);
    layoutKey.currentState!.showNavigation();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1050, 650);
    await tester.pumpAndSettle();
    expect(layoutKey.currentState!.drawerOpen, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(outerEscapes, 1);
  });
}
